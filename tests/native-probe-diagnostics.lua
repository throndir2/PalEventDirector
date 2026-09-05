return function(test, equal, truthy)
    local Bridge = require("ped.palworld")
    local Config = require("ped.config")
    local Director = require("ped.director")
    local json = require("ped.json")
    local GROUP = "Invader_Group_NPC_Grade5_Hunter"

    local function name(value)
        return { type = function() return "FName" end, ToString = function() return value end }
    end

    local function object(address)
        return { IsValid = function() return true end, GetAddress = function() return address end }
    end

    local function with_fixture(options, callback)
        options = options or {}
        local old_register = _G.RegisterHook
        local stats = { records = {}, rows = 0, points = 0, navigation = 0, hooks = 0, dispatches = 0, logs = {} }
        local world, foreign = object(101), object(102)
        local owner, parent = object(201), object(202)
        local function_owner = options.inherited and parent or owner
        local path = "Function /Game/Fixture.BP_InvaderParent_C:RequestIncidentInvaderEnemy_BP"
        local fn = object(301)
        fn.GetFName = function() return name("RequestIncidentInvaderEnemy_BP") end
        fn.GetOuter = function() return function_owner end
        fn.GetFunctionFlags = function() return 0 end
        fn.GetFullName = function() return path end
        local function enumerate(class, receiver, visitor)
            equal(receiver, class)
            if class == function_owner then
                local result = visitor(fn)
                truthy(result == nil or result == true, "metadata iterator returned false")
            end
        end
        owner.ForEachFunction = function(receiver, visitor) enumerate(owner, receiver, visitor) end
        parent.ForEachFunction = function(receiver, visitor) enumerate(parent, receiver, visitor) end
        owner.GetSuperStruct = function() return options.inherited and parent or nil end
        parent.GetSuperStruct = function() return nil end
        owner.IsA = function() return not options.base_declaration end
        parent.IsA = owner.IsA
        _G.RegisterHook = function(actual_path, first, third)
            equal(actual_path, path, "concrete function path was reconstructed")
            equal(third, nil, "script hook used the native post slot")
            stats.hooks = stats.hooks + 1
            stats.callback = first
            return 77, 77
        end
        local rows = options.rows or {
            { key = "123", group = GROUP, biome = 1, minimum = 3, maximum = 5, weight = 10 },
            { key = "456", group = GROUP, biome = 4, minimum = 6, maximum = 9, weight = 0 },
            { key = GROUP, group = "OtherGroup", biome = 2, minimum = 0, maximum = 9, weight = 5 },
        }
        local length_reads = 0
        local data = setmetatable(object(401), { __len = function()
            length_reads = length_reads + 1
            return #rows + (options.changed_rows and length_reads > 1 and 1 or 0)
        end })
        data.type = function() return options.bad_table and "UObject" or "UDataTable" end
        data.GetRowStruct = function() return {
            IsValid = function() return true end, GetFName = function() return name("PalInvaderDatabaseRow") end,
        } end
        data.ForEachRow = function(receiver, visitor)
            equal(receiver, data)
            for index, entry in ipairs(rows) do
                stats.rows = stats.rows + 1
                local result = visitor(entry.key or tostring(index), {
                    GroupName = name(entry.group), BiomeID = entry.biome or 1,
                    InvadeGradeMin = entry.minimum or 0, InvadeGradeMax = entry.maximum or 9, Weight = entry.weight or 1,
                })
                truthy(result == nil or result == true, "row iterator returned false")
                if result == true then break end
            end
        end
        local point_data = options.points or {
            { x = 150, z = 0, biome = 1 }, { x = 150, z = 500, biome = 1, disabled = true },
            { x = 0, z = 150, biome = 4 }, { x = 400, z = 0, biome = 1 },
            { x = 150, z = 0, biome = 2, missing = true },
        }
        local points = setmetatable({}, { __len = function() return #point_data end })
        points.ForEach = function(receiver, visitor)
            equal(receiver, points)
            for index, entry in ipairs(point_data) do
                stats.points = stats.points + 1
                local actor = object(500 + index)
                local invoker = object(1000 + index)
                invoker.GetWorld = function() return entry.foreign and foreign or world end
                invoker.IsDisableInvorker = function()
                    stats.navigation = stats.navigation + 1
                    return entry.disabled == true
                end
                invoker.ActivateInvoker = function() error("diagnostic changed navigation") end
                invoker.SetDisableInvorkerFlag = invoker.ActivateInvoker
                invoker.bIsWaitWorldPartition = true
                actor.NavInvokerComponent = invoker
                local point = { Location = { X = entry.x, Y = 0, Z = entry.z or 0 }, BiomeType = entry.biome or 1,
                    SourceActor = not entry.missing and actor or nil }
                local result = visitor({ get = function() return "PRIVATE_POINT_KEY" end }, { get = function() return point end })
                truthy(result == nil or result == true, "map iterator returned false")
                if result == true then break end
            end
        end
        local base = object(601)
        base.Transform = { Translation = { X = 0, Y = 0, Z = 0 } }
        base.PlayerUIdsExistsInsideInServer = { "PRIVATE_PLAYER_UID", "ANOTHER_PRIVATE_PLAYER_UID" }
        base.BaseCampName = "PRIVATE_BASE_NAME"
        base.IsA = function(_, path) return path == "/Script/Pal.PalBaseCampModel" end
        base.GetId = function() return "fixture-base" end
        base.IsAvailable = function() return true end
        base.CurrentState, base.Level_InGuildProperty = 1, 10
        base.bTemporary, base.bIgnoreInvader = false, false
        local manager = object(602)
        manager.GetClass = function() return owner end
        manager.GetWorld = function() return world end
        manager.GetFullName = function() return "BP_PalInvaderManager_C /Game/Fixture" end
        manager.InvaderEnemyDataTable, manager.InvadeStartLocationList = data, points
        manager.Incidents = { ForEach = function() end }
        local observer = object(603)
        observer.TargetBaseCamp, observer.TargetBaseCampID = base, "fixture-base"
        observer.bIsInvading, observer.bIsInvaderPathSearching, observer.bIsCoolTime = false, false, false
        observer.PlayerHandlesCache, observer.PlayerInBaseCampTimer = {}, 15
        manager.Observers = { ForEach = function(_, visitor) visitor("fixture-base", observer) end }
        manager.StartInvaderMarchForBaseCamp = function()
            stats.dispatches = stats.dispatches + 1
            observer.bIsInvaderPathSearching = true
        end
        local settings = object(701)
        settings.InvadeStartPoint_BaseCampRadius_Min_cm = options.bad_radius and "PRIVATE_INVALID_VALUE" or 100
        settings.InvadeStartPoint_BaseCampRadius_Max_cm = 200
        settings.InvaderPathWaterContinuousDistanceThreshold = 3000
        settings.InvaderPathWaterTotalDistanceThreshold = 5000
        settings.InvadeOccurableBaseCampLevel = 6
        local utility = object(702)
        utility.GetGameSetting = function(_, context) equal(context, world); return settings end
        utility.GetOptionWorldSettings = function() error("unsafe getter invoked") end
        utility.GetOptionSubsystem = function() return {
            IsValid = function() return true end, GetWorld = function() return world end,
            OptionWorldSettings = { bEnableInvaderEnemy = true },
        } end
        local bridge = Bridge.new({ config = Config.defaults(), logger = {
            error = function(_, message) stats.logs[#stats.logs + 1] = message end,
            info = function(_, _, fields) stats.logs[#stats.logs + 1] = fields end,
            preflight_breadcrumb = function(_, step) stats.records[#stats.records + 1] = step; return true end,
        } })
        bridge.config.capabilities.startAllInvasions = true
        bridge.utility, bridge.event_manager, bridge.event_world = utility, manager, world
        bridge.event_manager_address, bridge.event_world_address = "602", "101"
        bridge.event_nearest_test = {}
        bridge.registered, bridge.periodic_active, bridge.event_open = true, true, true
        bridge.probe_base_id = "fixture-base"
        bridge.expected_bases = { ["fixture-base"] = true }
        local ok, failure = pcall(callback, bridge, manager, base, stats)
        _G.RegisterHook = old_register
        truthy(ok, failure)
    end

    test("probe diagnostics read group fields rather than row keys and compare both radius metrics", function()
        with_fixture({}, function(bridge, manager, base, stats)
            local ok, summary = bridge:_capture_probe_prerequisites(manager, base)
            truthy(ok, summary)
            equal(summary.invaderMatchingRows, 2)
            equal(summary.invaderMatchingWeightedRows, 1)
            equal(summary.invaderMatchingGradeMin, 3)
            equal(summary.invaderMatchingGradeMax, 9)
            equal(summary.probeGroupPresent, true)
            equal(summary.probeRadiusMatches2D, 3)
            equal(summary.probeRadiusMatches3D, 3)
            equal(summary.probeBiomeMatches2D, 2)
            equal(summary.probeBiomeMatches3D, 2)
            equal(summary.probeNavigationCandidates, 4)
            equal(summary.probeNavigationChecked, 3)
            equal(summary.probeNavigationNotDisabled, 2)
            equal(summary.probeNavigationDisabled, 1)
            equal(summary.probeNavigationUnavailable, 1)
            equal(summary.probePlayersInsideBase, 2)
            equal(summary.probeDataComplete, false)
            equal(stats.navigation, 3)
            local encoded = json.encode(summary)
            equal(encoded:find("PRIVATE", 1, true), nil)
            for _, value in pairs(summary) do truthy(type(value) ~= "table" and type(value) ~= "userdata") end
            equal(stats.dispatches, 0)
        end)
    end)

    test("probe inventory limits stop native callbacks and never label a partial scan as group absence", function()
        local rows, points = {}, {}
        for index = 1, 513 do rows[index] = { group = index == 513 and GROUP or "OtherGroup" } end
        for index = 1, 257 do points[index] = { x = 150, z = 0 } end
        with_fixture({ rows = rows, points = points }, function(bridge, manager, base, stats)
            local ok, summary = bridge:_capture_probe_prerequisites(manager, base)
            truthy(ok, summary)
            equal(stats.rows, 512)
            equal(stats.points, 256)
            equal(stats.navigation, 32)
            equal(summary.probeGroupPresent, nil)
            equal(summary.invaderRowsComplete, false)
            equal(summary.probeGeometryComplete, false)
            equal(summary.probeNavigationComplete, false)
            equal(summary.probeDataComplete, false)
        end)
    end)

    test("probe reads actual invoker disable state and does not inspect another world", function()
        with_fixture({ points = { { x = 100 }, { x = 200, disabled = true }, { x = 150, foreign = true } } },
            function(bridge, manager, base, stats)
                local ok, summary = bridge:_capture_probe_prerequisites(manager, base)
                truthy(ok, summary)
                equal(summary.probeRadiusMatches2D, 3)
                equal(summary.probeNavigationNotDisabled, 1)
                equal(summary.probeNavigationDisabled, 1)
                equal(summary.probeNavigationForeignWorld, 1)
                equal(stats.navigation, 2)
            end)
    end)

    test("probe observes the actual inherited Blueprint handoff with the script argument layout", function()
        with_fixture({ inherited = true }, function(bridge, manager, base, stats)
            truthy(bridge:_prepare_probe_handoff(manager))
            equal(stats.hooks, 1)
            equal(bridge.probe_handoff_metadata.handoffOwnerBlueprint, true)
            local parameter = object(801)
            parameter.TargetBaseCampID = "fixture-base"
            local wrap = function(value) return { get = function() return value end } end
            equal(stats.callback(wrap(manager), wrap(base), wrap(parameter)), nil)
            equal(bridge.probe_handoff_counts.calls, 1, "matching manager callback was not counted")
            equal(bridge.probe_handoff_counts.validParameters, 1, "script parameter was shifted like a native return value")
            equal(bridge.probe_handoff_counts.probeCalls, 1, "probe identity did not match")
            parameter.TargetBaseCampID = "other-base"
            equal(stats.callback(wrap(manager), wrap(nil), wrap(parameter)), nil)
            equal(bridge.probe_handoff_counts.probeCalls, 1)
            bridge:end_event_tracking()
            local count = #stats.records
            equal(stats.callback(wrap(manager), wrap(base), wrap(parameter)), nil)
            equal(#stats.records, count)
            truthy(bridge.hook_ids.probe_handoff)
        end)
    end)

    test("probe reports a base declaration as unobserved instead of pretending to hook a Blueprint override", function()
        with_fixture({ base_declaration = true }, function(bridge, manager, _, stats)
            truthy(bridge:_prepare_probe_handoff(manager))
            equal(bridge.probe_handoff_metadata.handoffResolution, "base-declaration")
            equal(bridge.probe_handoff_metadata.handoffHookRegistered, false)
            equal(stats.hooks, 0)
        end)
    end)

    test("probe faults preserve the first failing boundary and prohibit further native reads", function()
        for _, options in ipairs({ { bad_table = true }, { bad_radius = true }, { changed_rows = true } }) do
            with_fixture(options, function(bridge, manager, base, stats)
                local ok, failure = bridge:_native_step("outer-dispatch", function()
                    local captured, detail = bridge:_capture_probe_prerequisites(manager, base)
                    if not captured then error(detail, 0) end
                end)
                equal(ok, false)
                truthy(failure:find("at probe-", 1, true))
                equal(failure:find("PRIVATE", 1, true), nil)
                truthy(stats.records[#stats.records]:match("%.before$"))
                local count = #stats.records
                equal(bridge:_capture_probe_prerequisites(manager, base), false)
                equal(#stats.records, count)
                equal(stats.dispatches, 0)
            end)
        end
    end)

    test("ordinary probes record diagnostics without changing target scope or fabricating a raid", function()
        with_fixture({}, function(bridge, _, _, stats)
            bridge.event_nearest_test = nil
            local ok, result = bridge:start_all_invasions()
            truthy(ok, result)
            equal(stats.dispatches, 1)
            equal(#result.requests, 1)
            equal(result.requests[1].status, "probe_call_returned")
            equal(result.requests[1].before.nativeProbeRecorded, true)
            equal(result.requests[1].before.probeGroupSpecified, false)
            equal(result.requests[1].after.handoffHookRegistered, true)
            equal(bridge.probe_confirmed, false)
            local encoded = json.encode(stats.logs)
            equal(encoded:find("PRIVATE", 1, true), nil)
        end)
    end)

    test("probe chat carries request identity, partial coverage and scoped Blueprint observations", function()
        local config = Config.defaults()
        config.capabilities.startAllInvasions = true
        local now, messages = 1000, {}
        local diagnostic = { nativeProbeRecorded = true, probeDataComplete = false, probeGroupSpecified = true,
            invaderRowsScanned = 512, invaderTableRows = 513, probeRadiusMatches2D = 2, probeRadiusMatches3D = 1,
            probeNavigationNotDisabled = 1, probeNavigationChecked = 1, handoffHookRegistered = true }
        local bridge = {
            preflight_start = function() return true end, preflight_environment = function() return true end,
            begin_event_discovery = function() return { "base" }, {} end,
            start_all_invasions = function() return true, { requests = {
                { baseId = "base", phase = "probe", status = "probe_call_returned", before = diagnostic },
            } } end,
            capture_start_timeout = function() return true, { observerPathSearching = false, incidentForBase = false,
                observerInvading = false, handoffHookRegistered = true, handoffObservedCalls = 2, handoffProbeCalls = 1 } end,
            active_invasion_count = function() return 0 end,
            announce = function() return true end,
            send_chat = function(_, message, recipient)
                messages[#messages + 1] = { message = message, recipient = recipient }; return true
            end,
        }
        local director = Director.new({ config = config, bridge = bridge, clock = function() return now end,
            logger = { info = function() end, warn = function() end, error = function() end },
            store = { load_snapshot = function() return nil end, append = function() return true end, save_snapshot = function() return true end } })
        director:handle_chat({ uid = "PRIVATE_UID", palworldAdmin = true, palworldAdminReadable = true }, "!siege test-native")
        local found = false
        for _, reply in ipairs(messages) do
            if reply.message:find("diagnostics", 1, true) then
                found = true
                truthy(reply.message:find("request #1 diagnostics (partial)", 1, true))
                truthy(reply.message:find("group=unknown", 1, true))
                equal(reply.recipient, "PRIVATE_UID")
                equal(reply.message:find("PRIVATE_UID", 1, true), nil)
            end
        end
        truthy(found)
        now = 1061
        director:tick()
        local timeout = messages[#messages]
        truthy(timeout.message:find("request #1 timeout", 1, true))
        truthy(timeout.message:find("Blueprint callbacks=2 observed, 1 matched probe", 1, true))
        equal(timeout.recipient, "PRIVATE_UID")
        equal(director.state.status, "aborted")
    end)
end
