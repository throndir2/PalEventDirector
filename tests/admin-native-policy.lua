return function(test, equal, truthy)
    local separator = package.config:sub(1, 1)
    local fixture = dofile("tests" .. separator .. "native-probe-diagnostics.lua")(function() end, equal, truthy)
    local json = require("ped.json")
    local Config = require("ped.config")
    local Director = require("ped.director")
    local util = require("ped.util")
    local bounties = require("ped.bounties")

    local function director_fixture()
        local config = Config.defaults()
        config.siegeLeague.chatStartPolicy = "anyUser"
        for key in pairs(config.capabilities) do config.capabilities[key] = key ~= "grantItems" end
        local control = { now = 1000, calls = 0, writes = {}, clears = {}, messages = {}, prepared = false }
        local bridge = {
            preflight_environment = function() return true end,
            preflight_start = function()
                control.prepared = not control.reject_prepare
                return not control.reject_prepare, "fixture target is unavailable"
            end,
            begin_event_discovery = function()
                truthy(control.prepared, "supersession cleared the newly prepared targets")
                control.prepared = false
                return { "base-a", "base-b" }, {}
            end,
            start_all_invasions = function()
                control.calls = control.calls + 1
                return true, { phase = "admin-all", requested = 1, attempted = 2, requests = {
                    { baseId = "base-a", phase = "probe", status = "dispatch_call_failed", error = "native returned false",
                        native = { method = "RequestIncidentInvaderEnemy", returned = true, returnKind = "boolean", boolean = false } },
                    { baseId = "base-b", phase = "fanout", status = "fanout_call_returned",
                        native = { method = "RequestIncidentInvaderEnemy", returned = true, returnKind = "boolean", boolean = true } },
                } }
            end,
            continue_invasion_dispatch = function() error("admin callbacks attempted duplicate fanout") end,
            active_invasion_count = function() return 0 end,
            end_event_tracking = function(_, preserve)
                control.clears[#control.clears + 1] = preserve == true
                if not preserve then control.prepared = false end
            end,
            announce = function() return true end,
            send_chat = function(_, message) control.messages[#control.messages + 1] = message; return true end,
        }
        local director = Director.new({ config = config, bridge = bridge, clock = function() return control.now end,
            logger = { info = function() end, warn = function() end, error = function() end },
            store = {
                load_snapshot = function() return nil end,
                append = function(_, kind, _, state)
                    if kind == control.fail_kind then return false, "fixture disk failure" end
                    control.writes[#control.writes + 1] = { kind = kind, state = util.deep_copy(state) }
                    return true
                end,
                save_snapshot = function() return true end,
            } })
        return director, control, { uid = "admin", palworldAdmin = true, palworldAdminReadable = true }
    end

    test("admin dispatch submits despite visitor, busy, disabled and unavailable gameplay state", function()
        fixture({ experiments = true }, function(bridge, manager, base, stats)
            local observer
            manager.Observers:ForEach(function(_, value) observer = value end)
            observer.bIsInvading, observer.bIsInvaderPathSearching, observer.bIsCoolTime = true, true, true
            base.bIgnoreInvader = true
            base.IsAvailable = function() return false end
            local visitor = { IsValid = function() return true end, GetAddress = function() return 999 end,
                GroupGuid = "PRIVATE_EXISTING_GROUP", BroadcastGroupGuid = "PRIVATE_EXISTING_BROADCAST",
                InvaderType = 2, bCanExecute = true }
            manager.Incidents = { ForEach = function(_, callback) callback("fixture-base", visitor) end }
            bridge.utility.GetOptionSubsystem = function() return {
                IsValid = function() return true end, GetWorld = function() return stats.world end,
                OptionWorldSettings = { bEnableInvaderEnemy = false },
            } end
            bridge.native_observer.prepare = function() error("optional signature/hook preparation blocked dispatch") end
            bridge.native_observer.workers = function() error("optional worker inventory blocked dispatch") end
            bridge._capture_probe_prerequisites = function() error("optional spawn/group inspection blocked dispatch") end
            manager.RequestIncidentInvaderEnemy = function(_, id, target)
                equal(id, "fixture-base"); equal(target, observer)
                stats.dispatches = stats.dispatches + 1
                return false
            end
            bridge.event_admin_override = true
            bridge.event_nearest_test = nil
            bridge.event_native_control = { requestNumber = 11, requesterUid = "PRIVATE_ADMIN" }
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(stats.dispatches, 1)
            equal(result.status, "dispatch_call_failed")
            truthy(result.error:find("Native enemy-incident request rejected", 1, true))
            equal(result.native.returned, true)
            equal(result.native.boolean, false)
            equal(result.native.method, "RequestIncidentInvaderEnemy")
            equal(bridge.native_fault, nil)
            equal(result.before.incidentForBase, true)
            equal(result.before.worldInvaderEnabled, false)
            equal(result.before.baseAvailable, false)
            equal(bridge:_request_identity_is_new("fixture-base", "private_existing_group"), false)
            equal(bridge:_request_identity_is_new("fixture-base", "new_group"), true)
            equal(bridge:_request_identity_is_new("fixture-base", "new_group", visitor), false)
            equal(observer.bIsInvading, true)
            equal(observer.bIsInvaderPathSearching, true)
            equal(observer.bIsCoolTime, true)
            equal(base.bIgnoreInvader, true)
            equal(stats.experiments[#stats.experiments].code, "rejected")
            equal(json.encode(result):find("PRIVATE_EXISTING_GROUP", 1, true), nil)
        end)
    end)

    test("ordinary dispatch retains policy vetoes and a native fault still forbids all further calls", function()
        fixture({}, function(bridge, manager, _, stats)
            bridge.event_nearest_test = nil
            local observer
            manager.Observers:ForEach(function(_, value) observer = value end)
            observer.bIsInvading = true
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "dispatch_precondition_failed")
            equal(stats.dispatches, 0)
            bridge.event_admin_override = true
            manager.RequestIncidentInvaderEnemy = function() error("PRIVATE_NATIVE_FAILURE", 0) end
            result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "dispatch_call_failed")
            truthy(bridge.native_fault)
            equal(result.error:find("PRIVATE_NATIVE_FAILURE", 1, true), nil)
            local count = #stats.records
            equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "dispatch_quarantined")
            equal(#stats.records, count)
        end)
    end)

    test("admin start validation never uses global occupancy or world-enable policy as a veto", function()
        fixture({}, function(bridge, manager, _, stats)
            local controller = { IsValid = function() return true end }
            local roster = { { uid = "PRIVATE_ADMIN", controller = controller } }
            bridge.preflight_environment = function() return true end
            bridge.list_online_players = function() return roster end
            bridge._resolve_world_manager = function() return manager, stats.world end
            bridge._world_invaders_enabled = function() error("admin world-policy gate invoked") end
            bridge._registered_base_ids = function() error("admin global incident-slot gate invoked") end
            bridge.active_invasion_count = function() error("admin global active-incident gate invoked") end
            bridge._nearest_test_base = function() return "fixture-base" end
            bridge._eligible_online_guild_bases = function(_, _, _, admin, selected)
                equal(admin, true); equal(selected, "fixture-base")
                return { ["fixture-base"] = true }, { ["fixture-base"] = "fixed-guid" },
                    { ["fixture-base"] = "guild" }, roster
            end
            bridge._static_find = function(_, path)
                equal(path, "/Script/Pal.PalInvaderManager:RequestIncidentInvaderEnemy")
                return { IsValid = function() return true end }
            end
            truthy(bridge:preflight_start("native", { admin = true, nearestNativeTest = true,
                nativeTestRoute = "admission", requesterUid = "PRIVATE_ADMIN" }))
            equal(bridge.pending_nearest_test.baseId, "fixture-base")
            equal(stats.dispatches, 0)
        end)
    end)

    test("unidentifiable existing native state prevents attribution, not the admin request", function()
        fixture({}, function(bridge, manager, _, stats)
            manager.Incidents = { ForEach = function(_, callback) callback("fixture-base", {}) end }
            bridge.event_nearest_test = nil
            bridge.event_admin_override = true
            manager.RequestIncidentInvaderEnemy = function() stats.dispatches = stats.dispatches + 1; return true end
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "probe_call_returned")
            equal(stats.dispatches, 1)
            equal(bridge:_request_identity_is_new("fixture-base", "NEW_GROUP"), false)
            equal(bridge.probe_confirmed, false)
        end)
    end)

    test("admin all-target starts do not wait on the first probe or repeat a rejected target", function()
        fixture({}, function(bridge, _, _, stats)
            bridge.event_admin_override = true
            bridge.event_nearest_test = nil
            bridge.expected_bases = { ["fixture-base"] = true, ["other-base"] = true, ["third-base"] = true }
            local calls = {}
            bridge._dispatch_selected_base = function(_, id, phase)
                calls[#calls + 1] = id
                if #calls == 1 then
                    return { baseId = id, phase = phase, status = "dispatch_call_failed", error = "native returned false" }
                end
                return { baseId = id, phase = phase, status = phase .. "_call_returned" }
            end
            local ok, result = bridge:start_all_invasions()
            truthy(ok, result)
            equal(#calls, 3)
            equal(result.requested, 2)
            equal(result.attempted, 3)
            equal(result.allTargetsAttempted, true)
            equal(bridge.probe_confirmed, false)
            truthy(bridge:continue_invasion_dispatch())
            equal(#calls, 3)
            equal(stats.dispatches, 0)
        end)
    end)

    test("native faults still stop admin all-target requests before the next base", function()
        fixture({}, function(bridge)
            bridge.event_admin_override = true
            bridge.event_nearest_test = nil
            bridge.expected_bases = { ["fixture-base"] = true, ["other-base"] = true }
            local calls = 0
            bridge._dispatch_selected_base = function(_, id, phase)
                calls = calls + 1
                bridge.native_fault = "fixture native fault"
                return { baseId = id, phase = phase, status = "dispatch_call_failed", error = bridge.native_fault }
            end
            local ok, result = bridge:start_all_invasions()
            equal(ok, false)
            equal(calls, 1)
            equal(result.attempted, 1)
            equal(result.allTargetsAttempted, false)
            equal(result.requests[2].status, "dispatch_skipped_native_fault")
            equal(bridge:continue_invasion_dispatch(), false)
            equal(calls, 1)
        end)
    end)

    test("admin requests supersede starting or active tracking only after new target validation", function()
        for _, active in ipairs({ false, true }) do
            local director, control, admin = director_fixture()
            director:handle_chat(admin, "!siege start native 0")
            if active then truthy(director:on_invasion_start("base-b", "old-group")) end
            local previous = director.state.event
            local previous_board = director.scoreboard
            local key = previous.schedulerOccurrenceKey
            director:handle_chat(admin, "!siege start native 0")
            equal(control.calls, 2)
            truthy(director.state.event.id ~= previous.id)
            truthy(director.scoreboard ~= previous_board)
            equal(director.state.lastSupersededEvent.id, previous.id)
            equal(director.state.lastSupersededEvent.abortReason, "superseded_by_admin")
            equal(director.state.lastSupersededEvent.finalRankings, nil)
            equal(director.scheduler.state.occurrences[key].status, "cancelled")
            equal(director.scheduler.state.occurrences[key].supersededByRequest, 2)
            equal(control.clears[1], true)
            equal(director.state.event.bases["base-b"].groupId, nil)
            equal(director.state.event.fanoutDispatched, true)
            local journaled
            for _, record in ipairs(control.writes) do if record.kind == "event_superseded" then journaled = record.state end end
            truthy(journaled)
            equal(journaled.director.status, "aborted")
            equal(journaled.scoreboard, nil)
            equal(journaled.scheduler.occurrences[key].status, "cancelled")
            equal(#director.rewards:to_state().order, 0)
        end
    end)

    test("supersession preserves the old event on invalid targets or failed durable replacement", function()
        for _, failure in ipairs({ "target", "persistence" }) do
            local director, control, admin = director_fixture()
            director:handle_chat(admin, "!siege start native 0")
            truthy(director:on_invasion_start("base-b", "old-group"))
            local previous, board = director.state.event, director.scoreboard
            local key = previous.schedulerOccurrenceKey
            if failure == "target" then control.reject_prepare = true
            else control.fail_kind = "event_superseded" end
            director:handle_chat(admin, "!siege start native 0")
            equal(control.calls, 1)
            equal(director.state.event, previous)
            equal(director.state.status, "active")
            equal(director.scoreboard, board)
            equal(director.state.lastSupersededEvent, nil)
            equal(director.scheduler.state.occurrences[key].status, "started")
            equal(#control.clears, 0)
        end
    end)

    test("ordinary users cannot supersede tracking and admins cannot replay recovery", function()
        local director, control, admin = director_fixture()
        director:handle_chat(admin, "!siege start native 0")
        local old = director.state.event
        director:handle_chat({ uid = "ordinary", palworldAdmin = false, palworldAdminReadable = true }, "!siege start native 0")
        equal(control.calls, 1)
        equal(director.state.event, old)
        director.state.status = "recovery_required"
        old.status = "recovery_required"
        director:handle_chat(admin, "!siege start native 0")
        equal(control.calls, 1)
        equal(director.state.event, old)
        equal(director.state.status, "recovery_required")
    end)

    test("an admin countdown does not supersede active tracking until its requested deadline", function()
        local director, control, admin = director_fixture()
        director:handle_chat(admin, "!siege start native 0")
        truthy(director:on_invasion_start("base-b", "old-group"))
        local previous = director.state.event
        director:handle_chat(admin, "!siege start native 1")
        equal(control.calls, 1)
        equal(director.state.event, previous)
        control.now = 1060
        director:tick()
        equal(control.calls, 2)
        truthy(director.state.event.id ~= previous.id)
        equal(director.state.lastSupersededEvent.id, previous.id)
    end)

    test("mixed native results remain per-target and never trigger duplicate admin fanout", function()
        local director, control, admin = director_fixture()
        director:handle_chat(admin, "!siege start native 0")
        equal(director.state.status, "starting")
        equal(director.state.event.bases["base-a"].dispatchNative.boolean, false)
        equal(director.state.event.bases["base-a"].status, "dispatch_call_failed")
        equal(director.state.event.bases["base-b"].dispatchStatus, "fanout_call_returned")
        truthy(director:on_invasion_start("base-b", "new-group"))
        director:tick()
        equal(control.calls, 1)
        equal(director.state.status, "active")
    end)

    test("returned admin fanout targets time out as missing starts rather than unsubmitted work", function()
        local director, control, admin = director_fixture()
        director:handle_chat(admin, "!siege start native 0")
        control.now = 1061
        director:tick()
        equal(director.state.status, "aborted")
        equal(director.state.event.bases["base-b"].status, "native_start_missing")
        equal(director.state.event.finalRankings, nil)
        equal(control.calls, 1)
    end)

    test("bridge tracking replacement preserves new pending targets and drops old native ownership", function()
        fixture({}, function(bridge, manager, _, stats)
            bridge.owned_groups["old-group"] = "old-base"
            bridge.pending_expected_bases = { ["new-base"] = true }
            bridge.pending_native_base_ids = { ["new-base"] = "new-guid" }
            bridge.pending_base_guilds = { ["new-base"] = "new-guild" }
            bridge.pending_roster = { { uid = "fixture" } }
            bridge.pending_manager, bridge.pending_world, bridge.pending_admin_override = manager, stats.world, true
            bridge.pending_native_control = { requestNumber = 4 }
            bridge:end_event_tracking(true)
            equal(bridge.owned_groups["old-group"], nil)
            local targets = bridge:begin_event_discovery("native", "new-occurrence")
            equal(#targets, 1)
            equal(targets[1].id, "new-base")
            equal(bridge.event_manager, manager)
            equal(bridge.event_admin_override, true)
            equal(bridge.event_native_control.requestNumber, 4)
        end)
    end)

    test("pre-existing or ambiguous incidents cannot reserve bounty groups or change native members", function()
        for _, mode in ipairs({ "known-group", "broadcast-group", "known-address", "incomplete" }) do
            fixture({}, function(bridge, manager, base, stats)
                local previous_fname = _G.FName
                local old_incident = { IsValid = function() return true end, GetAddress = function() return 1234 end,
                    GroupGuid = "old-group", BroadcastGroupGuid = "old-broadcast", InvaderType = 1,
                    GetTargetCampModel = function() return base end }
                manager.Incidents = { ForEach = function(_, callback)
                    callback("fixture-base", mode == "incomplete" and {} or old_incident)
                end }
                manager.RequestIncidentInvaderEnemy = function() stats.dispatches = stats.dispatches + 1; return true end
                bridge.event_admin_override, bridge.event_nearest_test, bridge.profile_id = true, nil, "all-bounty"
                bridge.bounty_selector = bounties.new_selector("all-bounty", "fixture")
                local compositions, mutations = 0, 0
                bridge.director = { state = { event = { bases = { ["fixture-base"] = { status = "pending" } } } },
                    on_composition_result = function() compositions = compositions + 1 end }
                local dispatch = bridge:_dispatch_selected_base("fixture-base", "probe")
                equal(dispatch.status, "probe_call_returned")
                local incident = { IsValid = function() return true end, GetAddress = function()
                    return mode == "known-address" and 1234 or 5678
                end, InvaderType = 1, GetTargetCampModel = function() return base end,
                    GroupGuid = mode == "known-group" and "old-group" or "different-group",
                    BroadcastGroupGuid = mode == "broadcast-group" and "old-broadcast" or "different-broadcast" }
                local member = { CharacterID = "NativeMember", Level = 20, Otomo = "NativeCompanion" }
                local members = { GetArrayNum = function() return 1 end, ForEach = function(_, callback)
                    callback(1, { get = function() return member end, set = function(_, value) member = value; mutations = mutations + 1 end })
                end }
                _G.FName = function(value) return value end
                local ok, failure = pcall(function() bridge:_on_select_invaders(incident, members) end)
                _G.FName = previous_fname
                truthy(ok, failure)
                equal(member.CharacterID, "NativeMember")
                equal(mutations, 0)
                equal(compositions, 0)
                equal(next(bridge.owned_groups), nil)
                equal(bridge.selected_groups["fixture-base"], nil)
                equal(stats.dispatches, 1)
            end)
        end
    end)

    test("existing owned-group entries cannot bypass the baseline at the native start hook", function()
        fixture({}, function(bridge, manager, base)
            local old_console, old_loop = _G.RegisterConsoleCommandGlobalHandler, _G.LoopInGameThreadWithDelay
            local callbacks, confirmations = {}, 0
            _G.RegisterHook = function(path, _, post) callbacks[path] = post; return 1, 2 end
            _G.RegisterConsoleCommandGlobalHandler = function() end
            _G.LoopInGameThreadWithDelay = function() return 1 end
            local ok, failure = pcall(function()
                bridge.registered, bridge.periodic_active = false, false
                bridge.preflight_environment = function() return true end
                bridge.logger.warn = function() end
                bridge.config.capabilities.observeInvasions = true
                truthy(bridge:register())
                bridge.event_open = true
                bridge.director = { state = { event = { bases = { ["fixture-base"] = {} } } },
                    on_invasion_start = function() confirmations = confirmations + 1; return true end }
                bridge.request_windows["fixture-base"] = { expiresAt = math.huge, status = "probe_call_returned",
                    baseline = { complete = true, groups = { ["old-group"] = true }, incidents = {} } }
                bridge.profile_id = "all-bounty"
                bridge.owned_groups["old-group"] = "fixture-base"
                local callback = callbacks["/Script/Pal.PalInvaderManager:BroadcastInvaderStart"]
                callback(manager, { TargetBaseCamp = base, GroupGuid = "old-group", InvaderType = 1 })
                equal(confirmations, 0)
                bridge.owned_groups["fresh-group"] = "fixture-base"
                callback(manager, { TargetBaseCamp = base, GroupGuid = "fresh-group", InvaderType = 1 })
                equal(confirmations, 1)
            end)
            _G.RegisterConsoleCommandGlobalHandler, _G.LoopInGameThreadWithDelay = old_console, old_loop
            truthy(ok, failure)
        end)
    end)

    test("a native false return still captures post-call state without repeating the request", function()
        fixture({}, function(bridge, manager, _, stats)
            bridge.event_admin_override, bridge.event_nearest_test = true, nil
            manager.RequestIncidentInvaderEnemy = function()
                stats.dispatches = stats.dispatches + 1
                manager.PathFinder = { IsValid = function() return true end }
                return false
            end
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(stats.dispatches, 1)
            equal(result.native.boolean, false)
            equal(result.status, "dispatch_call_failed")
            equal(result.before.managerPathFinder, false)
            equal(result.after.managerPathFinder, true)
            equal(bridge.native_fault, nil)
            local state_log
            for _, entry in ipairs(stats.logs) do
                if type(entry) == "table" and entry.phase == "probe-after" then state_log = entry end
            end
            truthy(state_log)
            equal(state_log.target_modelValid, true)
            equal(state_log.targetValidation, nil)
        end)
    end)

    test("target validation distinguishes the invalid object and mismatching identity without printing IDs", function()
        local cases = {
            { code = "manager-unavailable", change = function(_, manager) manager.IsValid = function() return false end end },
            { code = "observer-map-unavailable", change = function(_, manager) manager.Observers = nil end },
            { code = "base-not-registered", change = function(_, manager) manager.Observers = { ForEach = function() end } end },
            { code = "observer-invalid", change = function(_, manager) manager.Observers = { ForEach = function(_, callback) callback("fixture-base", {}) end } end },
            { code = "base-model-invalid", change = function(_, _, base) base.IsValid = function() return false end end },
            { code = "model-id-call-failed", change = function(_, _, base) base.GetId = function() error("PRIVATE_PAYLOAD", 0) end end },
            { code = "model-id-unreadable", change = function(_, _, base) base.GetId = function() return nil end end },
            { code = "model-id-mismatch", change = function(_, _, base) base.GetId = function() return "PRIVATE_DIFFERENT_ID" end end },
            { code = "observer-id-unreadable", change = function(_, manager)
                manager.Observers:ForEach(function(_, observer) observer.TargetBaseCampID = nil end)
            end },
            { code = "observer-id-mismatch", change = function(_, manager)
                manager.Observers:ForEach(function(_, observer) observer.TargetBaseCampID = "PRIVATE_DIFFERENT_ID" end)
            end },
        }
        for _, case in ipairs(cases) do
            fixture({}, function(bridge, manager, base)
                case.change(bridge, manager, base)
                local target, reason, validation = bridge:_resolve_dispatch_target(manager, "fixture-base")
                equal(target, nil)
                equal(validation.code, case.code)
                equal(reason:find("PRIVATE", 1, true), nil)
                equal(json.encode(validation):find("PRIVATE", 1, true), nil)
            end)
        end
    end)

    test("per-target chat distinguishes native rejection from PED validation and reports observed transitions", function()
        local director, control = director_fixture()
        director.state.event = { requestNumber = 12, requesterUid = "PRIVATE_RECIPIENT" }
        director:_report_native_results({ requests = {
            { baseId = "PRIVATE_BASE", status = "dispatch_call_failed", targetIndex = 2, targetCount = 10,
                native = { method = "RequestIncidentInvaderEnemy", returned = true, boolean = false },
                before = { guidSourcesMatch = true, incidentForBase = false, managerPathFinder = false },
                after = { guidSourcesMatch = true, incidentForBase = false, managerPathFinder = true } },
            { baseId = "PRIVATE_BASE_2", status = "dispatch_call_failed", failureCode = "base-model-invalid",
                error = "PRIVATE_RAW_ERROR", targetIndex = 3, targetCount = 10 },
        } })
        local messages = table.concat(control.messages, "\n")
        truthy(messages:find("1 native false rejection(s); 1 PED pre-call error(s)", 1, true))
        truthy(messages:find("target 2/10", 1, true))
        truthy(messages:find("Palworld supplied no rejection reason", 1, true))
        truthy(messages:find("not a PED invalid-target veto", 1, true))
        truthy(messages:find("managerPathfinder=no->yes", 1, true))
        truthy(messages:find("base-model-invalid", 1, true))
        truthy(messages:find("TargetBaseCamp model is missing or no longer valid", 1, true))
        equal(messages:find("PRIVATE", 1, true), nil)
        for _, message in ipairs(control.messages) do truthy(#message <= director.config.limits.maxAnnouncementLength) end
    end)

    test("per-target chat is bounded and unknown raw errors are never echoed", function()
        local director, control = director_fixture()
        director.state.event = { requestNumber = 7, requesterUid = "PRIVATE_RECIPIENT" }
        local requests = {}
        for index = 1, 17 do
            requests[index] = { status = "dispatch_call_failed", error = "PRIVATE_RAW_ERROR", baseId = "PRIVATE_BASE_" .. index }
        end
        director:_report_native_results({ requests = requests })
        equal(#control.messages, 18)
        truthy(control.messages[#control.messages]:find("first 16 target reports", 1, true))
        equal(table.concat(control.messages, "\n"):find("PRIVATE", 1, true), nil)
    end)

    test("a rejected call and its failed post-call inspection remain distinct reported outcomes", function()
        local director, control = director_fixture()
        director.state.event = { requestNumber = 9, requesterUid = "PRIVATE_RECIPIENT" }
        director:_report_native_results({ requests = {
            { status = "dispatch_call_failed", native = { method = "RequestIncidentInvaderEnemy", returned = true, boolean = false },
                inspectionError = "PRIVATE_NATIVE_ERROR", error = "PRIVATE_NATIVE_ERROR" },
        } })
        local messages = table.concat(control.messages, "\n")
        truthy(messages:find("1 native false rejection(s)", 1, true))
        truthy(messages:find("1 call/inspection error(s)", 1, true))
        truthy(messages:find("Post-call inspection failed", 1, true))
        equal(messages:find("PRIVATE", 1, true), nil)
    end)
end
