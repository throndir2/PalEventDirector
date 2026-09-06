return function(test, equal, truthy)
    local separator = package.config:sub(1, 1)
    local fixture = dofile("tests" .. separator .. "native-probe-diagnostics.lua")(function() end, equal, truthy)
    local json = require("ped.json")

    local function actor(address, world)
        return { IsValid = function() return true end, GetAddress = function() return address end,
            GetWorld = function() return world end }
    end

    local function prepare_readonly(bridge, manager, base, stats)
        bridge.native_observer.prepare = function() end
        bridge.preflight_environment = function() return true end
        local controller = actor(901, stats.world)
        bridge.list_online_players = function() return { { uid = "PRIVATE_ADMIN", controller = controller } } end
        bridge._resolve_world_manager = function() return manager, stats.world end
        bridge._nearest_test_base = function() return "fixture-base" end
        local incident = actor(902, stats.world)
        incident.InvaderType, incident.ExecState = 2, 1
        incident.IsInitialized = function() return true end
        incident.IsExecuting = function() return true end
        incident.IsCompleted, incident.IsCanceled = function() return false end, function() return false end
        incident.GetClass = function() return { GetFName = function() return { ToString = function() return "PalInvaderIncidentBase" end } end } end
        incident.GetTargetCampModel = function() return base end
        incident.IsA = function(_, class) return class == "/Script/Pal.PalInvaderIncidentBase" end
        manager.Incidents = setmetatable({ ForEach = function(_, callback) callback("fixture-base", incident) end },
            { __len = function() return 1 end })
        return incident, controller
    end

    test("read-only native inspection works with occupied slots and does not overwrite the active event", function()
        fixture({ experiments = true }, function(bridge, manager, base, stats)
            prepare_readonly(bridge, manager, base, stats)
            bridge.director = { state = { status = "active", event = { requestNumber = 20, bases = { private = {} } } } }
            local before = json.encode(bridge.director.state)
            local ok, result = bridge:inspect_native_control({ uid = "PRIVATE_ADMIN" })
            truthy(ok, result)
            equal(result.slots, 1)
            equal(result.occupied, true)
            equal(result.observation, 1)
            equal(stats.dispatches, 0)
            equal(json.encode(bridge.director.state), before)
            equal(bridge.experiment_current, nil)
            local kinds = {}
            for _, record in ipairs(stats.experiments) do kinds[record.kind] = true end
            truthy(kinds.group and kinds.candidate and kinds.worker and kinds.incident and kinds.state)
            equal(json.encode(stats.experiments):find("PRIVATE", 1, true), nil)
        end)
    end)

    test("passive native evidence continues after event tracking ends without replaying the request", function()
        local now = 1000
        fixture({ experiments = true, clock = function() return now end }, function(bridge, manager, base, stats)
            prepare_readonly(bridge, manager, base, stats)
            local ok = bridge:inspect_native_control({ uid = "PRIVATE_ADMIN" })
            truthy(ok)
            bridge:end_event_tracking()
            now = 1305
            bridge:poll_native_observations()
            local found = false
            for _, record in ipairs(stats.experiments) do
                if record.kind == "scope" and record.phase == "sample" then
                    equal(record.sampleDue, 300)
                    equal(record.elapsed, 305)
                    found = true
                end
            end
            truthy(found)
            equal(stats.dispatches, 0)
            equal(bridge.event_open, false)
            now = 1601
            bridge:poll_native_observations()
            equal(#bridge.experiments.scopes, 0)
            equal(stats.dispatches, 0)
        end)

        test("truncated incident inspection reports unknown occupancy rather than a falsely free base", function()
            fixture({ experiments = true }, function(bridge, manager, base, stats)
                prepare_readonly(bridge, manager, base, stats)
                local callbacks = 0
                manager.Incidents = setmetatable({ ForEach = function(_, callback)
                    for index = 1, 17 do
                        callbacks = callbacks + 1
                        local result = callback(index == 17 and "fixture-base" or ("other-" .. index), {})
                        if result == true then break end
                    end
                end }, { __len = function() return 17 end })
                local ok, result = bridge:inspect_native_control({ uid = "PRIVATE_ADMIN" })
                truthy(ok, result)
                equal(result.slots, 17)
                equal(result.occupied, nil)
                equal(callbacks, 16)
                local state = stats.experiments[#stats.experiments]
                equal(state.kind, "state")
                equal(state.complete, false)
                equal(state.occupied, nil)
            end)
        end)
    end)

    test("native hook evidence preserves false returns and late scope matching", function()
        local now = 1000
        fixture({ experiments = true, clock = function() return now end }, function(bridge, manager, base, stats)
            local incident = prepare_readonly(bridge, manager, base, stats)
            local scope = bridge.native_observer:open({ route = "admission", request = 4, manager = manager,
                world = stats.world, base = base, base_id = "fixture-base", deadline = 1060 })
            now = 1070
            local returned = { get = function() return false end }
            equal(bridge.native_observer:observe_hook({ name = "IsIncidentBeginAllowed", result = "boolean", system = true },
                true, manager, returned, incident), nil)
            local record = stats.experiments[#stats.experiments]
            equal(record.kind, "hook")
            equal(record.returnReadable, true)
            equal(record.returnedBoolean, false)
            equal(record.matchedBase, true)
            equal(record.late, true)
            equal(record.observation, scope.id)
        end)
    end)

    test("worker sampling uses bounded one-based reads and never extends the native slot array", function()
        fixture({ experiments = true }, function(bridge, manager, base, stats)
            local reads = 0
            local slot = actor(1001, stats.world)
            local handle = actor(1002, stats.world)
            local parameter = actor(1003, stats.world)
            parameter.GetLevel = function() return 80 end
            handle.TryGetIndividualParameter = function() return parameter end
            slot.Handle = handle
            local slots = setmetatable({}, {
                __len = function() return 40 end,
                __index = function(_, index)
                    truthy(index >= 1 and index <= 40, "out-of-bounds array read")
                    reads = reads + 1
                    return slot
                end,
                __newindex = function() error("worker array was changed") end,
            })
            local container, director = actor(1004, stats.world), actor(1005, stats.world)
            container.SlotArray, director.CharacterContainer, base.WorkerDirector = slots, container, director
            local scope = bridge.native_observer:open({ route = "inspect", manager = manager, world = stats.world,
                base = base, base_id = "fixture-base" })
            local summary = bridge.native_observer:workers(scope)
            equal(reads, 32)
            equal(summary.workerAvailable, 32)
            equal(summary.workerMinimum, 80)
            equal(summary.workerMaximum, 80)
            equal(stats.experiments[#stats.experiments].complete, false)
        end)
    end)

    local function navigation_fixture(bridge, stats, malformed)
        local function fname(value) return { ToString = function() return value end } end
        local function field(name, kind, offset, struct)
            return { IsValid = function() return true end, GetFName = function() return fname(name) end,
                GetClass = function() return { GetFName = function() return fname(kind) end } end,
                GetOffset_Internal = function() return offset end, GetStruct = function() return struct end }
        end
        local vector = { IsValid = function() return true end, GetFName = function() return fname("Vector") end,
            ForEachProperty = function(_, callback)
                callback(field("X", "DoubleProperty", 0))
                callback(field("Y", "DoubleProperty", 8))
                callback(field("Z", "DoubleProperty", 16))
            end }
        local cdo, filter = actor(1101, stats.world), actor(1102, stats.world)
        local nav_class = actor(1103, stats.world)
        nav_class.GetCDO = function() return cdo end
        local pawn, controller = actor(1104, stats.world), actor(1105, stats.world)
        controller.GetDefaultPlayerCharacter = function() return pawn end
        local functions, queries = {}, 0
        local function fn(name, owner, properties, implementation, static)
            local value = actor(1200 + #properties, stats.world)
            value.GetFunctionFlags = function() return static and 0x2400 or 0x400 end
            value.GetOuter = function() return { GetFName = function() return fname(owner) end } end
            value.ForEachProperty = function(_, callback)
                for _, property in ipairs(properties) do if callback(property) == true then break end end
            end
            functions["/Script/NavigationSystem." .. owner .. ":" .. name] = setmetatable(value, {
                __call = function(_, receiver, ...) return implementation(receiver, ...) end,
            })
        end
        fn("FindPathToLocationSynchronously", "NavigationSystemV1", {
            field("WorldContextObject", "ObjectProperty", 0), field("PathStart", "StructProperty", 8, vector),
            field("PathEnd", "StructProperty", 32, vector), field("PathfindingContext", "ObjectProperty", 56),
            field("FilterClass", "ClassProperty", 64), field("ReturnValue", "ObjectProperty", malformed and 600 or 72),
        }, function(receiver, ...)
            local values = table.pack(...)
            equal(receiver, cdo)
            equal(values.n, 5)
            equal(values[1], stats.world)
            truthy(type(rawget(values[2], "X")) == "number")
            truthy(type(rawget(values[3], "Z")) == "number")
            equal(values[4], pawn)
            equal(values[5], filter)
            queries = queries + 1
            local path = actor(1300 + queries, stats.world)
            path.query = queries
            path.PathPoints = { "PRIVATE_VECTOR", "PRIVATE_VECTOR" }
            path.IsA = function(_, class) return class == "/Script/NavigationSystem.NavigationPath" end
            return path
        end, true)
        for _, name in ipairs({ "IsNavigationBeingBuilt", "IsNavigationBeingBuiltOrLocked" }) do
            fn(name, "NavigationSystemV1", { field("WorldContextObject", "ObjectProperty", 0),
                field("ReturnValue", "BoolProperty", 8) }, function(receiver, world)
                    equal(receiver, cdo); equal(world, stats.world); return false
                end, true)
        end
        fn("IsValid", "NavigationPath", { field("ReturnValue", "BoolProperty", 0) }, function(path) return path.query ~= 1 end)
        fn("IsPartial", "NavigationPath", { field("ReturnValue", "BoolProperty", 0) }, function(path) return path.query == 2 end)
        fn("GetPathLength", "NavigationPath", { field("ReturnValue", "DoubleProperty", 0) }, function() return 1500 end)
        fn("GetPathCost", "NavigationPath", { field("ReturnValue", "DoubleProperty", 0) }, function() return math.huge end)
        bridge._static_find = function(_, path)
            if path == "/Script/NavigationSystem.NavigationSystemV1" then return nav_class end
            if path == "/Script/NavigationSystem.NavigationQueryFilter" then return filter end
            return functions[path]
        end
        bridge._nearest_test_base = function() return "fixture-base" end
        return controller, function() return queries end
    end

    test("navigation experiments validate the small live ABI and distinguish object validity from path validity", function()
        fixture({ experiments = true }, function(bridge, manager, base, stats)
            local controller, count = navigation_fixture(bridge, stats)
            local scope = bridge.native_observer:open({ route = "inspect", manager = manager,
                world = stats.world, base = base, base_id = "fixture-base" })
            scope.query_origin = { X = 0, Y = 0, Z = 0 }
            scope.query_points = { { X = 1, Y = 2, Z = 3 }, { X = 4, Y = 5, Z = 6 },
                { X = 7, Y = 8, Z = 9 }, { X = 10, Y = 11, Z = 12 } }
            local ok, result = bridge:_native_step("fixture-navigation", function()
                local queried, value = bridge.native_observer:path_queries(scope, controller)
                truthy(queried, value)
                return value
            end)
            truthy(ok, result)
            equal(count(), 3)
            equal(result.queries, 3)
            equal(result.complete, 1)
            local results = {}
            for _, record in ipairs(stats.experiments) do
                if record.kind == "path" and record.index then results[#results + 1] = record end
            end
            equal(results[1].objectValid, true)
            equal(results[1].pathValid, false)
            equal(results[2].partial, true)
            equal(results[3].costReadable, false)
            equal(results[3].lengthMeters, 15)
            equal(json.encode(stats.experiments):find("PRIVATE", 1, true), nil)
            equal(scope.query_points, nil)
        end)
    end)

    test("navigation ABI mismatch stops before any query and cannot be retried", function()
        fixture({ experiments = true }, function(bridge, manager, base, stats)
            local controller, count = navigation_fixture(bridge, stats, true)
            local scope = bridge.native_observer:open({ route = "inspect", manager = manager,
                world = stats.world, base = base, base_id = "fixture-base" })
            local ok, reason = bridge:_native_step("fixture-navigation", function()
                return bridge.native_observer:path_queries(scope, controller)
            end)
            equal(ok, false)
            truthy(reason:find("navigation-signature", 1, true))
            equal(count(), 0)
            local records = #stats.records
            equal(bridge:inspect_native_control({ uid = "PRIVATE_ADMIN" }, true), false)
            equal(#stats.records, records)
        end)
    end)
end
