return function(test, equal, truthy)
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

    test("admin eligibility ignores cooldown without changing timers or concurrency checks", function()
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
        equal(bridge:_eligible_online_guild_bases(manager, roster, true), nil)
        observer.bIsInvading = false
        observer.bIsInvaderPathSearching = true
        equal(bridge:_eligible_online_guild_bases(manager, roster, true), nil)
        observer.bIsInvaderPathSearching = false
        observer.bIsCoolTime = "unknown"
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
end
