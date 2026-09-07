return function(test, equal, truthy)
    local separator = package.config:sub(1, 1)
    local fixture = dofile("tests" .. separator .. "native-probe-diagnostics.lua")(function() end, equal, truthy)
    local Experiments = require("ped.native_experiments")
    local Director = require("ped.director")
    local json = require("ped.json")

    local function name(value) return { ToString = function() return value end } end
    local function metadata(fields, struct_name)
        return {
            IsValid = function() return true end,
            GetFName = function() return name(struct_name) end,
            ForEachProperty = function(_, visitor)
                for _, value in ipairs(fields) do
                    local result = visitor({
                        IsValid = function() return true end,
                        GetFName = function() return name(value[1]) end,
                        GetClass = function() return { GetFName = function() return name(value[2]) end } end,
                        GetOffset_Internal = function() return value[3] end,
                        GetStruct = function() return value[4] end,
                    })
                    truthy(result == nil or result == true, "iterator returned false")
                    if result == true then break end
                end
            end,
        }
    end
    local function bind(owner, method, fields, handler)
        local fn = metadata(fields)
        fn.type = function() return "UFunction" end
        fn.GetFunctionFlags = function() return 0x2400 end
        owner[method] = setmetatable(fn, { __call = function(_, receiver, ...)
            equal(receiver, owner)
            return handler(...)
        end })
    end

    local function raid_fixture(options, callback)
        options = options or {}
        fixture({}, function(bridge, manager, base, stats)
            local state = { spawns = 0, finishes = 0, progress = {}, confirmations = 0, map = {}, system = {} }
            local function array(entries)
                entries.ForEach = function(_, visitor)
                    for index, entry in ipairs(entries) do
                        local result = visitor(index, entry)
                        truthy(result == nil or result == true)
                        if result == true then break end
                    end
                end
                return entries
            end
            bridge.utility.GetIncidentSystem = function()
                return { IsValid = function() return true end, GetWorld = function() return stats.world end,
                    WaitingIncidents = array({}), ExecuteIncidents = array(state.system), ResidentIncidents = array({}) }
            end
            manager.Incidents = {
                ForEach = function(_, visitor) for id, incident in pairs(state.map) do visitor(id, incident) end end,
                Contains = function(_, key) return state.map[key] ~= nil end,
                Find = function(_, key) truthy(state.map[key]); return state.map[key] end,
                Add = function() error("PED fabricated an incident-map entry") end,
            }
            local info = { IsValid = function() return not state.destroyed end, GetAddress = function() return 850 end,
                IsA = function(_, path) return path == "/Script/Pal.PalInvaderInfo" end,
                GetWorld = function()
                    return options.foreign_world and { IsValid = function() return true end, GetAddress = function() return 999 end } or stats.world
                end,
                bIsFirstWaveStarted = false,
                GetRemainInvadeStartRealTimeSeconds = function() return options.bad_clock and 10 or -1 end }
            local incident = { IsValid = function() return true end, GetAddress = function() return 851 end,
                IsA = function() return true end, GetWorld = function() return stats.world end,
                GetTargetCampModel = function() return base end, InvaderType = 1,
                GroupGuid = "new-native-group", BroadcastGroupGuid = "new-native-group",
                IsExecuting = function() return not state.completed end, GetAliveInvaderNum = function() return state.completed and 0 or 5 end }
            local vector = metadata({ { "X", "DoubleProperty", 0 }, { "Y", "DoubleProperty", 8 }, { "Z", "DoubleProperty", 16 } }, "Vector")
            local quat = metadata({ { "X", "DoubleProperty", 0 }, { "Y", "DoubleProperty", 8 },
                { "Z", "DoubleProperty", 16 }, { "W", "DoubleProperty", 24 } }, "Quat")
            local transform = metadata({ { "Rotation", "StructProperty", 0, quat },
                { "Translation", "StructProperty", 32, vector }, { "Scale3D", "StructProperty", 64, vector } }, "Transform")
            local library = { IsValid = function() return true end }
            local class = { IsValid = function() return true end, type = function() return "UClass" end,
                GetFName = function() return name("PalInvaderInfo") end }
            bridge.utility.CalcRealTimeDifferenceToNow = function() error("Bootstrap marshaled an opaque DateTime") end
            local remaining = metadata({ { "ReturnValue", "FloatProperty", 0 } })
            remaining.type = function() return "UFunction" end
            remaining.GetFunctionFlags = function() return 0x400 end
            bind(library, "BeginDeferredActorSpawnFromClass", {
                { "WorldContextObject", "ObjectProperty", 0 }, { "actorClass", "ClassProperty", 8 },
                { "SpawnTransform", "StructProperty", 16, transform },
                { "collisionHandlingOverride", options.old_enum_shape and "ByteProperty" or "EnumProperty", 112 },
                { "Owner", "ObjectProperty", 120 }, { "ReturnValue", "ObjectProperty", options.bad_signature and 640 or 128 },
            }, function(...)
                equal(select("#", ...), 5, "the trailing nil Owner argument was dropped")
                local world, actual_class, placement, collision, owner = ...
                equal(world, stats.world); equal(actual_class, class); equal(owner, nil); equal(collision, 0)
                equal(placement.Rotation.W, 1); equal(placement.Scale3D.X, 1); equal(placement.Translation.Z, 0)
                state.spawns = state.spawns + 1
                if options.invalid_spawn then return nil end
                return info
            end)
            bind(library, "FinishSpawningActor", {
                { "Actor", "ObjectProperty", 0 }, { "SpawnTransform", "StructProperty", 16, transform },
                { "ReturnValue", "ObjectProperty", 112 },
            }, function(actor)
                equal(actor, info)
                equal(info.StartRealTime, nil, "Bootstrap rewrote an opaque DateTime")
                equal(info.BaseCampId, "fixture-base")
                equal(info.InvadeGrade, 1)
                state.finishes = state.finishes + 1
                if not options.unregistered then manager.InvaderInfo = actor end
                return actor
            end)
            bridge._static_find = function(_, path)
                if path == "/Script/Engine.Default__GameplayStatics" then return library end
                if path == "/Script/Pal.PalInvaderInfo:GetRemainInvadeStartRealTimeSeconds" then return remaining end
                equal(path, "/Script/Pal.PalInvaderInfo")
                return class
            end
            manager.RequestIncidentInvaderEnemy_BP = function() error("PED bypassed native initialization with a direct Blueprint call") end
            manager.RequestIncidentInvaderEnemy = function() error("Bootstrap invoked private admission") end
            manager.StartInvaderMarchForBaseCamp = function() error("Bootstrap retried through public march") end
            manager.StartInvaderMarchAll = function() error("Bootstrap widened the target set") end
            if options.occupied then manager.InvaderInfo = { IsValid = function() return true end } end
            if options.unreadable_state then
                manager.InvaderInfo = { IsValid = function() error("PRIVATE_UNREADABLE_STATE", 0) end }
            end
            bridge.event_admin_override, bridge.discovery_open, bridge.profile_id = true, true, "native"
            bridge.event_nearest_test = { route = "blueprint", controller = {}, world = stats.world, baseId = "fixture-base" }
            bridge._nearest_test_base = function() return "fixture-base" end
            bridge.director = { state = { status = "starting", event = { bases = { ["fixture-base"] = { status = "pending" } } } },
                on_native_start_progress = function(_, progress) state.progress[#state.progress + 1] = progress end,
                on_invasion_start = function(_, id, group)
                    equal(id, "fixture-base"); equal(group, "new-native-group")
                    state.confirmations = state.confirmations + 1
                    bridge.director.state.event.bases[id].status = "active"
                    return true
                end }
            state.native_tick = function()
                equal(manager.InvaderInfo, info)
                info.BroadcastGroupId, info.bIsFirstWaveStarted = "new-native-group", true
                state.map["fixture-base"], state.system[1] = incident, incident
            end
            state.native_finish = function()
                equal(manager.InvaderInfo, info, "native teardown would receive a null raid-state actor")
                state.completed, state.destroyed = true, true
                state.map["fixture-base"], state.system[1], manager.InvaderInfo = nil, nil, nil
            end
            callback(bridge, state, info, incident)
        end)
    end

    test("initialized native raid setup leaves incident creation and cleanup to the game", function()
        raid_fixture({}, function(bridge, state, info)
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "probe_call_returned")
            equal(result.native.raidStateInitialized, true)
            equal(result.native.method, "FinishSpawningActor")
            equal(state.spawns, 1); equal(state.finishes, 1); equal(state.confirmations, 0)
            equal(bridge.request_windows["fixture-base"].raidInfo, info)
            equal(next(state.map), nil)
            equal(json.encode(result):find("Ticks", 1, true), nil)
            state.native_tick()
            truthy(bridge:poll_invasion_progress())
            equal(state.progress[1].phase, "enemy-alive")
            equal(state.confirmations, 1)
            state.native_finish()
            equal(state.destroyed, true)
            equal(state.spawns, 1)
        end)
    end)

    test("bootstrap ABI and state-read errors stop before creating native actors", function()
        for _, options in ipairs({ { bad_signature = true }, { old_enum_shape = true }, { unreadable_state = true } }) do
            raid_fixture(options, function(bridge, state)
                equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "dispatch_call_failed")
                equal(state.spawns, 0); equal(state.finishes, 0)
                truthy(bridge.native_fault)
                equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "dispatch_quarantined")
            end)
        end
    end)

    test("a pre-existing raid-state actor cannot be overwritten by an admin bootstrap", function()
        raid_fixture({ occupied = true }, function(bridge, state)
            local existing = bridge.event_manager.InvaderInfo
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.failureCode, "raid-state-already-exists")
            equal(state.spawns, 0); equal(bridge.event_manager.InvaderInfo, existing)
            equal(bridge.native_fault, nil)
        end)
    end)

    test("failed native actor creation or registration cannot be retried or reported as a raid", function()
        for _, options in ipairs({ { invalid_spawn = true }, { unregistered = true }, { foreign_world = true }, { bad_clock = true } }) do
            raid_fixture(options, function(bridge, state)
                equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "dispatch_call_failed")
                equal(state.spawns, 1); equal(state.confirmations, 0)
                if options.foreign_world or options.invalid_spawn or options.bad_clock then equal(state.finishes, 0) end
                truthy(bridge.native_fault)
                equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "dispatch_quarantined")
                equal(state.spawns, 1)
            end)
        end
    end)

    test("bootstrap confirmation needs both live enemies and its own correlated raid-state actor", function()
        raid_fixture({}, function(bridge, state, info, incident)
            equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "probe_call_returned")
            state.native_tick()
            equal(bridge:_confirm_native_start("fixture-base", "new-native-group", 1, "callback"), false)
            info.BroadcastGroupId = "unrelated-group"
            equal(bridge:_confirm_native_start("fixture-base", "new-native-group", 1, "live-enemy-state", incident), false)
            info.BroadcastGroupId = "new-native-group"
            truthy(bridge:poll_invasion_progress())
            equal(state.confirmations, 1)
        end)
    end)

    test("initialized raid control remains explicit, one-base, and truthfully described", function()
        truthy(Experiments.validate_context({ nearestNativeTest = true, nativeTestRoute = "blueprint" }))
        equal(Experiments.validate_context({ nativeTestRoute = "blueprint" }), false)
        local chats = {}
        Director._report_native_results({
            state = { event = { requestNumber = 15, requesterUid = "PRIVATE_ADMIN" } },
            logger = { info = function() end }, _chat = function(_, text) chats[#chats + 1] = text end,
        }, { requests = { { status = "probe_call_returned",
            native = { method = "FinishSpawningActor", returned = true, raidStateInitialized = true, grade = 1 } } } })
        truthy(chats[2]:find("Palworld now owns incident creation and waves", 1, true))
        equal(table.concat(chats):find("PRIVATE_ADMIN", 1, true), nil)
    end)
end
