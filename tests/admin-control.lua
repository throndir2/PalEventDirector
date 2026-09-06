return function(test, equal, truthy, native_fname_constructor)
    local Config = require("ped.config")
    local Director = require("ped.director")
    local Bridge = require("ped.palworld")
    local Scheduler = require("ped.scheduler")

    local function command_fixture()
        local config = Config.defaults()
        config.siegeLeague.chatStartPolicy = "anyUser"
        for name in pairs(config.capabilities) do config.capabilities[name] = name ~= "grantItems" end
        local now, replies, controls, writes = 1000, {}, {}, {}
        local bridge = {
            preflight_environment = function() return true end,
            preflight_start = function(_, _, control)
                controls[#controls + 1] = control
                return false, "fixture native admission failure"
            end,
            send_chat = function(_, message) replies[#replies + 1] = message; return true end,
            announce = function() return true end,
        }
        local director = Director.new({
            config = config, bridge = bridge, clock = function() return now end,
            logger = { info = function() end, warn = function() end, error = function() end },
            store = { load_snapshot = function() return nil end,
                append = function(_, kind) writes[#writes + 1] = kind; return true end, save_snapshot = function() return true end },
        })
        return director, replies, controls, writes, function(value) now = value end
    end

    test("admin commands bypass ordinary chat and start throttles with trusted context", function()
        local director, replies, controls = command_fixture()
        local admin = { uid = "fixture-admin", palworldAdminReadable = true, palworldAdmin = true }
        truthy(director:handle_chat(admin, "!siege status"))
        truthy(director:handle_chat(admin, "!siege status"))
        equal(#replies, 2)
        truthy(director:handle_chat(admin, "!siege start native 0"))
        truthy(director:handle_chat(admin, "!ped start native 0"))
        equal(#controls, 2)
        equal(controls[1].admin, true)
        equal(controls[2].admin, true)
        equal(director.state.lastUserStartAt or 0, 0)
        truthy(director:status_text():match("^Latest Siege League start failed: fixture native admission failure"))
        equal(director.scheduler.state.manualNonce, 2)
        director:handle_operator_command("start native 0", "console")
        equal(controls[3].admin, true)
        director:handle_operator_command("start native 0")
        equal(controls[4].admin, true)
    end)

    test("due admin work is processed ahead of ordinary scheduler work", function()
        local order = {}
        local scheduler = Scheduler.new({ schedules = {}, clock = function() return 1000 end,
            notify = function() return true end, persist = function() return true end,
            can_start = function() return true end, start_event = function() return true end })
        scheduler.state.occurrences = {
            ordinary = { key = "ordinary", status = "planned", manual = true, intendedAt = 1000, schedule = {} },
            admin = { key = "admin", status = "planned", manual = true, intendedAt = 1000, adminOverride = true, schedule = {} },
        }
        scheduler._process = function(_, _, occurrence) order[#order + 1] = occurrence.key end
        scheduler:tick(1000)
        equal(order[1], "admin")
        equal(order[2], "ordinary")
    end)

    test("ordinary users cannot claim admin priority and retain both throttles", function()
        local director, replies, controls, _, set_time = command_fixture()
        local ordinary = { uid = "fixture-user", palworldAdminReadable = true, palworldAdmin = false,
            adminOverride = true, authority = "palworld-admin", displayName = "Admin" }
        director:handle_chat(ordinary, "!siege status")
        director:handle_chat(ordinary, "!siege status")
        equal(#replies, 1)
        set_time(1003)
        director:handle_chat(ordinary, "!siege start native 0")
        equal(#controls, 1)
        equal(controls[1].admin, false)
        set_time(1006)
        director:handle_chat(ordinary, "!siege start native 0")
        equal(#controls, 1)
        truthy(replies[#replies]:match("rate%-limited"))
        local admin = { uid = "fixture-admin", palworldAdminReadable = true, palworldAdmin = true }
        director:handle_chat(admin, "!siege start native 0")
        equal(#controls, 2)
        equal(controls[2].admin, true)
    end)

    test("new admin countdown supersedes pending manual work with atomic rollback", function()
        local fail = false
        local scheduler = Scheduler.new({
            schedules = {}, clock = function() return 1000 end,
            notify = function() return true end, can_start = function() return true end,
            start_event = function() return false, "fixture" end,
            persist = function(kind) return not (fail and kind == "manual_countdown_armed") end,
        })
        local ok, original = scheduler:arm_manual("native", "ordinary", 600, "Original")
        truthy(ok)
        local nonce = scheduler.state.manualNonce
        fail = true
        equal(scheduler:arm_manual("native", "admin", 300, "Replacement", true), false)
        equal(original.status, "planned")
        equal(scheduler.state.manualNonce, nonce)
        fail = false
        local replaced, latest = scheduler:arm_manual("native", "admin", 300, "Replacement", true)
        truthy(replaced)
        equal(original.status, "cancelled")
        equal(original.reason, "superseded_by_admin")
        equal(latest.adminOverride, true)
        equal(latest.countdownSeconds, 300)
        equal(latest.superseded[1], original.key)
        equal(scheduler:arm_manual("native", "ordinary", 60, "Ordinary"), false)
        equal(latest.status, "planned")
    end)

    test("admin target discovery ignores gameplay flags without changing their native values", function()
        local world = {}
        local base = {
            IsValid = function() return true end, IsAvailable = function() return true end,
            GetId = function() return "base" end, GetGroupIdBelongTo = function() return "guild" end,
            bIgnoreInvader = false,
        }
        local observer = { TargetBaseCamp = base, TargetBaseCampID = "base", bIsInvading = false,
            bIsInvaderPathSearching = false, bIsCoolTime = true, CoolTimeFinish = 10000, CoolTimeElapsed = 25 }
        local manager = { Observers = { ForEach = function(_, callback) callback("base", observer) end } }
        local bridge = Bridge.new({ config = Config.defaults(), logger = {} })
        bridge.utility = { IsValid = function() return true end,
            GetGuildByPlayerUId = function() return { IsValid = function() return true end, GetId = function() return "guild" end } end }
        local roster = { { uid = "fixture", world = world, guid = "fixture-guid" } }
        equal(bridge:_eligible_online_guild_bases(manager, roster, false), nil)
        local expected = bridge:_eligible_online_guild_bases(manager, roster, true)
        truthy(expected.base)
        equal(observer.bIsCoolTime, true)
        equal(observer.CoolTimeFinish, 10000)
        equal(observer.CoolTimeElapsed, 25)
        observer.bIsInvading = true
        truthy(bridge:_eligible_online_guild_bases(manager, roster, true).base)
        observer.bIsInvading = false
        observer.bIsInvaderPathSearching = true
        truthy(bridge:_eligible_online_guild_bases(manager, roster, true).base)
        observer.bIsInvaderPathSearching = false
        observer.bIsCoolTime = "unknown"
        truthy(bridge:_eligible_online_guild_bases(manager, roster, true).base)
        base.bIgnoreInvader = true
        base.IsAvailable = function() error("admin discovery must not use availability as a prerequisite") end
        truthy(bridge:_eligible_online_guild_bases(manager, roster, true).base)
        observer.TargetBaseCampID = "wrong-base"
        equal(bridge:_eligible_online_guild_bases(manager, roster, true), nil)
    end)

    test("admin native admission is explicit and never substitutes a void march or fake lifecycle", function()
        for _, acceptance in ipairs({ true, false, "invalid" }) do
            local calls = 0
            local observer = { IsValid = function() return true end }
            local manager = { IsValid = function() return true end,
                RequestIncidentInvaderEnemy = function(_, id, target)
                    equal(id, "native-guid"); equal(target, observer); calls = calls + 1; return acceptance
                end,
                StartInvaderMarchForBaseCamp = function() error("admin request used ambient march entry point") end,
            }
            local config = Config.defaults()
            config.capabilities.startAllInvasions = true
            local bridge = Bridge.new({ config = config, delivery_profile = "laboratory-native-test", logger = {
                info = function() end, error = function() end, preflight_breadcrumb = function() return true end,
            } })
            bridge.registered, bridge.periodic_active, bridge.event_admin_override = true, true, true
            bridge.event_manager = manager
            bridge.event_nearest_test = { route = "admission", baseId = "base", controller = {}, world = {} }
            bridge._nearest_test_base = function() return "base" end
            bridge._dispatch_snapshot = function()
                return { worldInvaderEnabled = true, baseAvailable = true, baseIgnoreInvader = false,
                    observerInvading = false, observerPathSearching = false, observerCoolTime = true, incidentForBase = false },
                    { nativeId = "native-guid", observer = observer }
            end
            local result = bridge:_dispatch_selected_base("base", "probe")
            equal(calls, 1)
            if acceptance == true then
                equal(result.status, "probe_call_returned")
                equal(bridge.probe_confirmed, false)
            else
                equal(result.status, "dispatch_call_failed")
                if acceptance == false then truthy(result.error:match("rejected the base")) end
            end
            if acceptance == "invalid" then truthy(bridge.native_fault) end
        end
    end)

    test("the probe prefers an occupied eligible base without removing other targets", function()
        local config = Config.defaults()
        config.capabilities.startAllInvasions = true
        local bridge = Bridge.new({ config = config, logger = {
            preflight_breadcrumb = function() return true end, error = function() end,
        } })
        bridge.registered, bridge.periodic_active = true, true
        bridge.expected_bases = { ["a-empty"] = true, ["z-occupied"] = true, ["m-empty"] = true }
        bridge.event_manager = { IsValid = function() return true end, Observers = {
            ForEach = function(_, callback)
                callback("a-empty", { PlayerHandlesCache = {}, PlayerInBaseCampTimer = 0 })
                callback("z-occupied", { PlayerHandlesCache = { {} }, PlayerInBaseCampTimer = 5 })
                callback("m-empty", { PlayerHandlesCache = {}, PlayerInBaseCampTimer = 0 })
            end,
        } }
        local calls = {}
        bridge._dispatch_selected_base = function(_, id, phase)
            calls[#calls + 1] = id
            return { baseId = id, status = phase .. "_call_returned" }
        end
        local ok, result = bridge:start_all_invasions()
        truthy(ok)
        equal(calls[1], "z-occupied")
        equal(#calls, 1)
        equal(#result.requests, 3)
        equal(bridge.dispatch_order[2], "a-empty")
        equal(bridge.dispatch_order[3], "m-empty")
        equal(bridge:continue_invasion_dispatch(), false)
        equal(#calls, 1)
    end)

    test("timeout capture records current probe state without starting another invasion", function()
        local bridge = Bridge.new({ config = Config.defaults(), logger = {
            preflight_breadcrumb = function() return true end, info = function() end,
        } })
        bridge.event_manager = { IsValid = function() return true end }
        bridge.probe_base_id = "fixture"
        local snapshots = 0
        bridge._dispatch_snapshot = function(_, _, base, phase)
            equal(base, "fixture")
            equal(phase, "probe-timeout")
            snapshots = snapshots + 1
            return { observerPathSearching = true, incidentForBase = false, startHookCalls = 0 }
        end
        local ok, snapshot = bridge:capture_start_timeout()
        truthy(ok)
        equal(snapshot.observerPathSearching, true)
        equal(snapshot.startHookCalls, 0)
        equal(snapshots, 1)
    end)

    test("native hook counters observe post callbacks without overriding return values", function()
        local previous = _G.RegisterHook
        local pre, post, calls = nil, nil, 0
        _G.RegisterHook = function(_, before, after) pre, post = before, after; return 1, 2 end
        local bridge = Bridge.new({ config = Config.defaults(), logger = {} })
        local ok, failure = pcall(function()
            truthy(bridge:_register_hook("invasion_start", "/Script/Fixture:Start", function() calls = calls + 1; return true end))
            equal(pre(), nil)
            equal(bridge.hook_observed.invasion_start, nil)
            equal(post(), nil)
            equal(bridge.hook_observed.invasion_start, 1)
            equal(calls, 1)
        end)
        _G.RegisterHook = previous
        truthy(ok, failure)
    end)

    test("nearest native test is admin-only and has fixed native scope", function()
        local director, replies, controls = command_fixture()
        local ordinary = { uid = "fixture-user", palworldAdminReadable = true, palworldAdmin = false }
        local admin = { uid = "fixture-admin", palworldAdminReadable = true, palworldAdmin = true }
        director:handle_chat(ordinary, "!siege test-native")
        equal(#controls, 0)
        truthy(replies[#replies]:match("requires an authorized"))
        director:handle_chat(admin, "!siege test-native")
        equal(#controls, 1)
        equal(controls[1].nearestNativeTest, true)
        equal(controls[1].requesterUid, admin.uid)
        equal(controls[1].admin, true)
        director:handle_chat(admin, "!ped test-native extra")
        equal(#controls, 1)
    end)

    test("nearest native RPC uses only the validated requester and stock group", function()
        local old_fname = _G.FName
        local calls, moved, records = 0, false, {}
        local world = { IsValid = function() return true end }
        local controller = { IsValid = function() return true end,
            Debug_InvaderMarchForNearCamp = function(_, group, skip)
                if native_fname_constructor then equal(type(group), "userdata") end
                equal(type(group) == "string" and group or group:ToString(), "Invader_Group_NPC_Grade5_Hunter")
                equal(skip, true)
                calls = calls + 1
            end }
        local bridge = Bridge.new({ config = Config.defaults(), logger = {
            info = function() end, error = function() end,
            preflight_breadcrumb = function(_, step) records[#records + 1] = step; return true end,
        } })
        bridge.config.capabilities.startAllInvasions = true
        bridge.registered, bridge.periodic_active, bridge.event_admin_override = true, true, true
        bridge.event_manager = { IsValid = function() return true end,
            RequestIncidentInvaderEnemy = function() error("nearest test used lower-level request") end,
            StartInvaderMarchForBaseCamp = function() error("nearest test used march fallback") end }
        bridge.event_nearest_test = { controller = controller, world = world, baseId = "base" }
        bridge._nearest_test_base = function(_, caller, owner_world)
            equal(caller, controller); equal(owner_world, world)
            return moved and "other-base" or "base"
        end
        bridge._dispatch_snapshot = function()
            return { worldInvaderEnabled = true, baseAvailable = true, baseIgnoreInvader = false,
                observerInvading = false, observerPathSearching = false, observerCoolTime = true, incidentForBase = false },
                { nativeId = "native-guid", observer = { IsValid = function() return true end } }
        end
        local constructor = native_fname_constructor or function(name) return name end
        _G.FName = constructor
        local ok, failure = pcall(function()
            local result = bridge:_dispatch_selected_base("base", "probe")
            equal(result.status, "probe_call_returned")
            equal(calls, 1)
            equal(bridge.probe_confirmed, false)
            moved = true
            equal(bridge:_dispatch_selected_base("base", "probe").status, "dispatch_call_failed")
            equal(calls, 1, "moved requester dispatched against another base")
            moved = false
            _G.FName = nil
            local failed = bridge:_dispatch_selected_base("base", "probe")
            equal(failed.status, "dispatch_call_failed")
            truthy(failed.error:find("at test-native-group [fname-constructor-unavailable]", 1, true))
            truthy(records[#records]:match("test%-native%-group.before$"))
            local record_count = #records
            _G.FName = constructor
            equal(bridge:_dispatch_selected_base("base", "probe").status, "dispatch_quarantined")
            equal(#records, record_count, "failed construction was retried")
            equal(calls, 1)
        end)
        _G.FName = old_fname
        truthy(ok, failure)
    end)

    test("nearest and in-range identity checks reject a changed world or wrong base", function()
        local world = { IsValid = function() return true end, GetAddress = function() return 1 end }
        local foreign = { IsValid = function() return true end, GetAddress = function() return 2 end }
        local current_world, nearest_id = world, "base"
        local location = {}
        local controller = { IsValid = function() return true end, GetWorld = function() return current_world end,
            GetDefaultPlayerCharacter = function() return {
                IsValid = function() return true end, K2_GetActorLocation = function() return location end,
            } end }
        local base_manager = { IsValid = function() return true end, GetWorld = function() return world end,
            GetInRangedBaseCamp = function(_, value, margin)
                equal(value, location); equal(margin, 0)
                return { IsValid = function() return true end, GetId = function() return "base" end }
            end,
            GetNearestBaseCamp = function(_, value)
                equal(value, location)
                return { IsValid = function() return true end, GetId = function() return nearest_id end }
            end }
        local bridge = Bridge.new({ config = Config.defaults(), logger = {
            preflight_breadcrumb = function() return true end, error = function() end,
        } })
        bridge.utility = { IsValid = function() return true end, GetBaseCampManager = function() return base_manager end }
        equal(bridge:_nearest_test_base(controller, world), "base")
        nearest_id = "other"
        equal(bridge:_nearest_test_base(controller, world), nil)
        current_world = foreign
        equal(bridge:_nearest_test_base(controller, world), nil)
    end)

    test("explicit admission and march experiments stay on the same single target without fallback", function()
        for _, route in ipairs({ "admission", "march" }) do
            local calls = {}
            local bridge = Bridge.new({ config = Config.defaults(), logger = {
                info = function() end, error = function() end, preflight_breadcrumb = function() return true end,
            } })
            bridge.config.capabilities.startAllInvasions = true
            bridge.registered, bridge.periodic_active, bridge.event_admin_override = true, true, true
            local observer = { IsValid = function() return true end }
            local manager = { IsValid = function() return true end,
                RequestIncidentInvaderEnemy = function(_, id, value)
                    equal(route, "admission"); equal(id, "fixed-guid"); equal(value, observer)
                    calls[#calls + 1] = "admission"
                    return false
                end,
                StartInvaderMarchForBaseCamp = function(_, id)
                    equal(route, "march"); equal(id, "fixed-guid"); calls[#calls + 1] = "march"
                end,
                StartInvaderMarchAll = function() error("experiment widened its scope") end }
            bridge.event_manager = manager
            bridge.event_nearest_test = { route = route, baseId = "base", world = {}, controller = {
                Debug_InvaderMarchForNearCamp = function() error("experiment fell back to the debug RPC") end,
            } }
            bridge._nearest_test_base = function() return "base" end
            bridge._dispatch_snapshot = function()
                return { worldInvaderEnabled = true, baseAvailable = true, baseIgnoreInvader = false,
                    observerInvading = false, observerPathSearching = false, observerCoolTime = true, incidentForBase = false },
                    { nativeId = "fixed-guid", observer = observer }
            end
            local result = bridge:_dispatch_selected_base("base", "probe")
            equal(#calls, 1)
            equal(result.status, route == "admission" and "dispatch_call_failed" or "probe_call_returned")
            equal(bridge.probe_confirmed, false)
        end
    end)

    test("inspection and navigation experiments remain admin-only under any-user start policy", function()
        local director, replies = command_fixture()
        local count = 0
        director.bridge.inspect_native_control = function(_, principal, paths)
            count = count + 1
            equal(principal.uid, "fixture-admin")
            equal(paths, true)
            return true, { observation = 1, slots = 1, occupied = true, probeRadiusMatches2D = 1,
                probeRadiusMatches3D = 1, probeNavigationNotDisabled = 1, probeNavigationChecked = 1,
                completePaths = 0, pathQueries = 1 }
        end
        director:handle_chat({ uid = "ordinary", palworldAdmin = false, palworldAdminReadable = true }, "!siege inspect-native")
        equal(count, 0)
        director:handle_chat({ uid = "fixture-admin", palworldAdmin = true, palworldAdminReadable = true }, "!siege test-path")
        equal(count, 1)
        truthy(replies[#replies]:find("complete default-agent paths=0/1", 1, true))
    end)

    test("nearest native validation narrows scope to one eligible requester base", function()
        local world = { IsValid = function() return true end, GetAddress = function() return 1 end }
        local manager = { IsValid = function() return true end, GetAddress = function() return 2 end, GetWorld = function() return world end }
        local controller = { IsValid = function() return true end }
        local roster = { { uid = "requester", controller = controller, world = world } }
        local config = Config.defaults()
        config.capabilities.startAllInvasions = true
        local bridge = Bridge.new({ config = config, logger = {
            preflight_breadcrumb = function() return true end, error = function() end,
        } })
        bridge.registered, bridge.periodic_active = true, true
        bridge.utility = { IsValid = function() return true end,
            GetInvaderManager = function() return manager end,
            GetOptionSubsystem = function() return {
                IsValid = function() return true end, GetWorld = function() return world end,
                OptionWorldSettings = { bEnableInvaderEnemy = true },
            } end }
        bridge.preflight_environment = function() return true end
        bridge.list_online_players = function() return roster end
        bridge._registered_base_ids = function() return { "near", "far" } end
        bridge.active_invasion_count = function() return 0 end
        bridge._eligible_online_guild_bases = function()
            return { near = true, far = true }, { near = "near-id", far = "far-id" },
                { near = "guild", far = "guild" }, roster
        end
        local selected = "near"
        bridge._nearest_test_base = function(_, caller, owner) equal(caller, controller); equal(owner, world); return selected end
        bridge._static_find = function(_, path)
            equal(path, "/Script/Pal.PalPlayerController:Debug_InvaderMarchForNearCamp")
            return { IsValid = function() return true end }
        end
        local context = { admin = true, requesterUid = "requester", nearestNativeTest = true }
        truthy(bridge:preflight_start("native", context))
        equal(bridge.pending_expected_bases.near, true)
        equal(bridge.pending_expected_bases.far, nil)
        local targets = bridge:begin_event_discovery("native", "test-occurrence")
        equal(#targets, 1)
        equal(bridge.event_nearest_test.baseId, "near")
        bridge:end_event_tracking()
        equal(bridge.event_nearest_test, nil)
        selected = "outside"
        equal(bridge:preflight_start("native", context), false)
        equal(bridge:preflight_start("native", { admin = false, requesterUid = "requester", nearestNativeTest = true }), false)
    end)
end
