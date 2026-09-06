return function(test, equal, truthy)
    local separator = package.config:sub(1, 1)
    local fixture = dofile("tests" .. separator .. "native-probe-diagnostics.lua")(function() end, equal, truthy)
    local Director = require("ped.director")
    local Config = require("ped.config")
    local Experiments = require("ped.native_experiments")

    local function setup(bridge, manager, base, stats, clock)
        local control = { phase = "empty", calls = 0, chats = {}, banners = {}, writes = {}, aliveCalls = 0 }
        bridge.event_open = false
        bridge.event_nearest_test = nil
        bridge.preflight_environment = function() return true end
        bridge.list_online_players = function() return {} end
        bridge._resolve_world_manager = function() return manager, stats.world end
        bridge._eligible_online_guild_bases = function()
            return { ["fixture-base"] = true }, { ["fixture-base"] = "fixture-base" },
                { ["fixture-base"] = "guild" }, {}
        end
        bridge._static_find = function(_, path)
            truthy(path == "/Script/Pal.PalInvaderManager:StartInvaderMarchForBaseCamp"
                or path == "/Script/Pal.PalInvaderIncidentBase:SelectInvaders")
            return { IsValid = function() return true end }
        end
        bridge.config.capabilities.observeCombat = true
        bridge.config.capabilities.observeInvasions = true
        bridge.config.capabilities.substituteBountyMembers = true
        bridge.logger.warn = function() end
        bridge.send_chat = function(_, text) control.chats[#control.chats + 1] = text; return true end
        bridge.announce = function(_, text) control.banners[#control.banners + 1] = text; return true end
        manager.RequestIncidentInvaderEnemy = function() error("normal start used the private admission helper") end
        manager.StartInvaderMarchAll = function() error("public march broadened scope") end
        manager.StartInvaderMarchRandom = manager.StartInvaderMarchAll
        local incident = {
            IsValid = function() return true end, GetAddress = function() return 800 end,
            GetWorld = function() return stats.world end, GetTargetCampModel = function() return base end,
            GroupGuid = "enemy-group", BroadcastGroupGuid = "enemy-group", InvaderType = 1,
            IsExecuting = function() return true end,
            GetAliveInvaderNum = function()
                control.aliveCalls = control.aliveCalls + 1
                if control.native_error then error("PRIVATE_NATIVE_FAILURE", 0) end
                return control.phase == "attack" and 5 or 0
            end,
        }
        manager.Incidents = {
            Contains = function(_, key)
                return key == "fixture-base" and (control.phase == "attack" or control.phase == "visitor" or control.phase == "existing")
            end,
            Find = function(self, key)
                truthy(self:Contains(key), "Find called without checking the key")
                return { get = function() return incident end }
            end,
            ForEach = function(_, callback)
                if control.phase == "attack" or control.phase == "visitor" or control.phase == "existing" then
                    callback("fixture-base", incident)
                end
            end,
        }
        local info = {
            IsValid = function() return true end, GetWorld = function() return stats.world end,
            BaseCampId = "fixture-base", BroadcastGroupId = "enemy-group", bIsFirstWaveStarted = false,
            GetRemainInvadeStartRealTimeSeconds = function() return math.max(0, 1300 - clock()) end,
        }
        manager.StartInvaderMarchForBaseCamp = function(_, id)
            equal(id, "fixture-base")
            control.calls = control.calls + 1
            if control.phase == "declare-on-call" then
                control.phase = "preparation"
                manager.InvaderInfo = info
            end
        end
        local director = Director.new({ config = bridge.config, bridge = bridge, logger = bridge.logger, clock = clock,
            store = { load_snapshot = function() return nil end,
                append = function(_, kind) control.writes[#control.writes + 1] = kind; return true end,
                save_snapshot = function() return true end } })
        bridge:attach_director(director)
        return director, control, incident, info
    end

    test("normal admin march waits through native preparation and confirms only live enemy state", function()
        local now = 1000
        fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
            local director, control, _, info = setup(bridge, manager, base, stats, function() return now end)
            control.phase = "declare-on-call"
            truthy(director:arm_start("test", "native", 0, true, { requesterUid = "private-admin" }))
            equal(control.calls, 1)
            equal(director.state.event.nativeRoute, "march")
            equal(director.state.event.startConfirmationDeadline, 1480)
            equal(bridge.request_windows["fixture-base"].expiresAt, 1480)
            equal(director.state.event.bases["fixture-base"].dispatchNative.method, "StartInvaderMarchForBaseCamp")
            now = 1061
            director:tick()
            equal(director.state.status, "starting")
            equal(director.state.event.bases["fixture-base"].nativeProgress.phase, "preparing")
            equal(director.state.event.bases["fixture-base"].nativeProgress.remainingSeconds, 239)
            equal(#control.banners, 0)
            now = 1100
            control.phase = "attack"
            director:tick()
            equal(director.state.status, "starting", "pre-spawned enemies bypassed the native preparation flag")
            equal(#control.banners, 0)
            now = 1301
            control.phase, info.bIsFirstWaveStarted = "attack", true
            director:tick()
            equal(director.state.status, "active")
            equal(director.state.event.confirmedBaseCount, 1)
            equal(director.state.event.bases["fixture-base"].groupId, "enemy-group")
            equal(control.banners[1], "SIEGE LEAGUE - RAID STARTED")
            now = 1306
            director:tick()
            equal(#control.banners, 1)
            equal(control.calls, 1)
            local text = table.concat(control.chats, "\n")
            truthy(text:find("native raid preparation is active", 1, true))
            truthy(text:find("new executing enemy attackers are present", 1, true))
            equal(text:find("private-admin", 1, true), nil)
        end)
    end)

    test("a lone visitor or pre-existing enemy never confirms the new public march request", function()
        for _, phase in ipairs({ "visitor", "existing" }) do
            local now = 1000
            fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
                local director, control, incident = setup(bridge, manager, base, stats, function() return now end)
                control.phase = phase
                incident.InvaderType = phase == "visitor" and 2 or 1
                truthy(director:arm_start("test", "native", 0, true))
                now = 1300
                director:tick()
                equal(director.state.status, "starting")
                equal(director.state.event.confirmedBaseCount, 0)
                equal(control.aliveCalls, 0)
                equal(#control.banners, 0)
                equal(control.calls, 1)
            end)
        end
    end)

    test("an empty public march expires at its bounded deadline without retry or fake results", function()
        local now = 1000
        fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
            local director, control = setup(bridge, manager, base, stats, function() return now end)
            truthy(director:arm_start("test", "native", 0, true))
            now = 1061
            director:tick()
            equal(director.state.status, "starting")
            now = 1480
            director:tick()
            equal(director.state.status, "aborted")
            equal(director.state.event.finalRankings, nil)
            equal(director.rewards:summary().pending, 0)
            equal(control.calls, 1)
        end)

    end)

    test("pre-existing native declaration cannot be claimed by a later march request", function()
        local now = 1000
        fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
            local director, control, _, info = setup(bridge, manager, base, stats, function() return now end)
            manager.InvaderInfo = info
            truthy(director:arm_start("test", "native", 0, true))
            control.phase, info.bIsFirstWaveStarted = "attack", true
            now = 1310
            director:tick()
            equal(director.state.status, "starting")
            equal(director.state.event.confirmedBaseCount, 0)
            equal(#control.banners, 0)
        end)
    end)

    test("a progress getter fault stops observation without repeating the native march", function()
        local now = 1000
        fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
            local director, control = setup(bridge, manager, base, stats, function() return now end)
            truthy(director:arm_start("test", "native", 0, true))
            control.phase, control.native_error = "attack", true
            now = 1005
            director:tick()
            truthy(bridge.native_fault)
            equal(director.state.event.confirmedBaseCount, 0)
            local records = #stats.records
            now = 1010
            director:tick()
            equal(#stats.records, records)
            equal(control.calls, 1)
        end)
    end)

    test("new native attackers without observed bounty substitution are reported unranked", function()
        local now = 1000
        fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
            local director, control = setup(bridge, manager, base, stats, function() return now end)
            truthy(director:arm_start("test", "all-bounty", 0, true, { requesterUid = "private-admin" }))
            control.phase = "attack"
            now = 1310
            director:tick()
            equal(director.state.status, "active")
            equal(director.state.event.bases["fixture-base"].ranked, false)
            truthy(table.concat(control.chats, "\n"):find("bounty substitution is unconfirmed", 1, true))
            equal(director.rewards:summary().pending, 0)
            local credited, reason = director:on_damage({ base_id = "fixture-base", group_id = "enemy-group" })
            equal(credited, false)
            equal(reason, "base_composition_unranked")
            director:on_composition_result("fixture-base", 5, 5, nil)
            equal(director.state.event.bases["fixture-base"].compositionUnverifiedAtStart, true)
            equal(director.state.event.bases["fixture-base"].ranked, false, "later selection retroactively ranked the unobserved first wave")
        end)
    end)

    test("preparation window is route-specific, configurable and bounded by maximum runtime", function()
        local config = Config.defaults()
        equal(Experiments.start_window_seconds(config, "march"), 480)
        equal(Experiments.start_window_seconds(config, "debug"), 60)
        equal(Experiments.start_window_seconds(config, "admission"), 60)
        config.siegeLeague.nativeMarchStartSeconds = 600
        equal(Experiments.start_window_seconds(config, "march"), 600)
        config.siegeLeague.maxRuntimeSeconds = 120
        equal(Experiments.start_window_seconds(config, "march"), 120)
        config.siegeLeague.nativeMarchStartSeconds = 0
        equal(Config.validate(config), false)
    end)

    test("progress work is bounded and rotates over requested bases without submitting more calls", function()
        local now = 1000
        fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
            local director, control = setup(bridge, manager, base, stats, function() return now end)
            truthy(director:arm_start("test", "native", 0, true))
            bridge.request_windows = {}
            local event = director.state.event
            event.bases = {}
            for index = 1, 5 do
                local id = "base-" .. index
                bridge.request_windows[id] = { status = "probe_call_returned", expiresAt = 1480, nativeId = id }
                event.bases[id] = { status = "pending" }
            end
            local observations = {}
            director.on_native_start_progress = function(_, progress) observations[#observations + 1] = progress.baseId end
            truthy(bridge:poll_invasion_progress())
            equal(#observations, 4)
            truthy(bridge:poll_invasion_progress())
            equal(#observations, 4)
            now = 1005
            truthy(bridge:poll_invasion_progress())
            equal(#observations, 5)
            equal(observations[5], "base-5")
            equal(control.calls, 1)
        end)
    end)

    test("enemy progress from a different world or mismatched base cannot confirm the assault", function()
        for _, wrong in ipairs({ "world", "base" }) do
            local now = 1000
            fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
                local director, control, incident = setup(bridge, manager, base, stats, function() return now end)
                truthy(director:arm_start("test", "native", 0, true))
                control.phase = "attack"
                if wrong == "world" then
                    incident.GetWorld = function() return {
                        IsValid = function() return true end, GetAddress = function() return 444 end,
                    } end
                else
                    incident.GetTargetCampModel = function() return {
                        IsValid = function() return true end, GetId = function() return "different-base" end,
                    } end
                end
                now = 1310
                director:tick()
                equal(director.state.status, "starting")
                equal(director.state.event.confirmedBaseCount, 0)
                equal(control.aliveCalls, 0)
                equal(control.calls, 1)
            end)
        end
    end)

    test("unrelated incident slots do not hide the requested enemy beyond a scan prefix", function()
        local now = 1000
        fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
            local director, control, incident = setup(bridge, manager, base, stats, function() return now end)
            bridge.config.limits.maxBases = 1
            manager.Incidents.ForEach = function(_, callback)
                if callback("unrelated-base", {}) == true then return end
                if control.phase == "attack" then callback("fixture-base", incident) end
            end
            truthy(director:arm_start("test", "native", 0, true))
            control.phase = "attack"
            now = 1310
            director:tick()
            equal(director.state.status, "active")
            equal(director.state.event.confirmedBaseCount, 1)
            equal(control.aliveCalls, 1)
            equal(control.calls, 1)
        end)
    end)

    test("unreadable native preparation never becomes permission to confirm pre-spawned attackers", function()
        local now = 1000
        fixture({ clock = function() return now end }, function(bridge, manager, base, stats)
            local director, control, _, info = setup(bridge, manager, base, stats, function() return now end)
            control.phase = "declare-on-call"
            truthy(director:arm_start("test", "native", 0, true))
            info.bIsFirstWaveStarted = nil
            setmetatable(info, { __index = function(_, key)
                if key == "bIsFirstWaveStarted" then error("PRIVATE_READ_FAILURE", 0) end
            end })
            control.phase = "attack"
            now = 1100
            director:tick()
            equal(director.state.status, "starting")
            equal(director.state.event.confirmedBaseCount, 0)
            truthy(bridge.native_fault)
            equal(bridge.native_fault:find("PRIVATE", 1, true), nil)
            equal(control.aliveCalls, 0)
        end)
    end)
end
