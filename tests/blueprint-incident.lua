return function(test, equal, truthy)
    local separator = package.config:sub(1, 1)
    local fixture = dofile("tests" .. separator .. "native-probe-diagnostics.lua")(function() end, equal, truthy)
    local Experiments = require("ped.native_experiments")
    local Director = require("ped.director")
    local Config = require("ped.config")
    local json = require("ped.json")

    local function blueprint_fixture(options, callback)
        options = options or {}
        fixture({}, function(bridge, manager, base, stats)
            local old_construct = _G.StaticConstructObject
            local state = { calls = 0, constructions = 0, progress = {}, confirmations = 0 }
            local function name(value) return { ToString = function() return value end } end
            local owner = { IsValid = function() return true end, IsA = function() return true end }
            local class = { IsValid = function() return true end, type = function() return "UClass" end }
            local parameter = { IsValid = function() return true end,
                IsA = function(_, path) return path == "/Script/Pal.PalIncidentDynamicParameterInvader" end,
                GetOuter = function() return manager end }
            local incident = { IsValid = function() return true end, GetAddress = function() return 812 end,
                IsA = function(_, path) return path == "/Script/Pal.PalInvaderIncidentBase" end,
                GetWorld = function() return options.foreign_world and {
                    IsValid = function() return true end, GetAddress = function() return 999 end,
                } or stats.world end,
                GetTargetCampModel = function() return base end,
                InvaderType = 1, GroupGuid = "new-blueprint-group", BroadcastGroupGuid = "new-blueprint-group",
                IsExecuting = function() return true end, GetAliveInvaderNum = function() return 4 end }
            local function incident_array(entries)
                entries.ForEach = function(_, visitor)
                    for index, value in ipairs(entries) do
                        local result = visitor(index, value)
                        truthy(result == nil or result == true)
                        if result == true then break end
                    end
                end
                return entries
            end
            state.system_incidents = options.preexisting and { incident } or {}
            bridge.utility.GetIncidentSystem = function()
                local system = { IsValid = function() return true end, GetWorld = function() return stats.world end,
                    WaitingIncidents = incident_array({}),
                    ExecuteIncidents = incident_array(state.system_incidents),
                    ResidentIncidents = incident_array({}) }
                if options.incomplete_baseline then system.ResidentIncidents = nil end
                return system
            end
            manager.RequestIncidentInvaderEnemy_BP = setmetatable({
                IsValid = function() return true end, type = function() return "UFunction" end,
                GetOuter = function() return owner end,
                ForEachProperty = function(_, visitor)
                    for index, field_name in ipairs({ "OccuredBaseCamp", "Parameter", "ReturnValue", "CallFunc_RequestIncident_ReturnValue" }) do
                        local result = visitor({
                            IsValid = function() return true end,
                            GetFName = function() return name(field_name) end,
                            GetOffset_Internal = function() return options.bad_signature and 80 or (index - 1) * 8 end,
                            GetClass = function() return { GetFName = function() return name("ObjectProperty") end } end,
                        })
                        truthy(result == nil or result == true, "signature iterator returned false")
                        if result == true then break end
                    end
                end,
            }, { __call = function(_, caller, actual_base, actual_parameter)
                state.calls = state.calls + 1
                equal(caller, manager)
                equal(actual_base, base)
                equal(actual_parameter, parameter)
                equal(actual_parameter.TargetBaseCampID, "fixture-base")
                if options.no_incident then return nil end
                if #state.system_incidents == 0 then state.system_incidents[1] = incident end
                return incident
            end })
            manager.RequestIncidentInvaderEnemy = function() error("Blueprint experiment invoked the private native path") end
            manager.StartInvaderMarchForBaseCamp = function() error("Blueprint experiment retried through public march") end
            manager.StartInvaderMarchAll = function() error("Blueprint experiment broadened its scope") end
            manager.Incidents.Add = function() error("Blueprint experiment fabricated a manager incident entry") end
            bridge._static_find = function(_, path)
                equal(path, "/Script/Pal.PalIncidentDynamicParameterInvader")
                return class
            end
            _G.StaticConstructObject = function(actual_class, outer)
                equal(actual_class, class)
                equal(outer, manager)
                state.constructions = state.constructions + 1
                return parameter
            end
            bridge.event_admin_override = true
            bridge.discovery_open, bridge.profile_id = true, "native"
            bridge.event_nearest_test = { route = "blueprint", controller = {}, world = stats.world, baseId = "fixture-base" }
            bridge._nearest_test_base = function() return "fixture-base" end
            bridge.director = { state = { status = "starting", event = {
                bases = { ["fixture-base"] = { status = "pending" } },
            } },
                on_native_start_progress = function(_, progress) state.progress[#state.progress + 1] = progress end,
                on_invasion_start = function(_, id, group)
                    equal(id, "fixture-base"); equal(group, "new-blueprint-group")
                    state.confirmations = state.confirmations + 1
                    bridge.director.state.event.bases[id].status = "active"
                    return true
                end }
            local ok, reason = pcall(callback, bridge, state, parameter, incident, stats)
            _G.StaticConstructObject = old_construct
            truthy(ok, reason)
        end)
    end

    test("Blueprint experiment constructs real per-base parameters and retains only private native handles", function()
        blueprint_fixture({}, function(bridge, state, parameter, incident)
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "probe_call_returned")
            equal(state.calls, 1)
            equal(state.constructions, 1)
            equal(result.native.method, "RequestIncidentInvaderEnemy_BP")
            equal(result.native.incidentReturned, true)
            equal(bridge.request_windows["fixture-base"].blueprintParameter, parameter)
            equal(bridge.request_windows["fixture-base"].blueprintIncident, incident)
            equal(json.encode(result):find("TargetBaseCampID", 1, true), nil)
            truthy(bridge:poll_invasion_progress())
            equal(state.confirmations, 1)
            equal(state.progress[1].phase, "enemy-alive")
            equal(state.calls, 1)
        end)
    end)

    test("Blueprint null returns are native no-incident outcomes rather than successful raids", function()
        blueprint_fixture({ no_incident = true }, function(bridge, state)
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "dispatch_call_failed")
            equal(result.native.returned, true)
            equal(result.native.incidentReturned, false)
            truthy(result.error:find("returned no incident", 1, true))
            equal(state.calls, 1)
            equal(state.confirmations, 0)
            equal(bridge.native_fault, nil)
        end)
    end)

    test("unexpected Blueprint layout stops before allocation or invocation and never retries", function()
        blueprint_fixture({ bad_signature = true }, function(bridge, state)
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "dispatch_call_failed")
            equal(state.constructions, 0)
            equal(state.calls, 0)
            truthy(bridge.native_fault)
            equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "dispatch_quarantined")
            equal(state.calls, 0)
        end)
    end)

    test("a Blueprint incident from another world never becomes a controlled raid", function()
        blueprint_fixture({ foreign_world = true }, function(bridge, state)
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "dispatch_call_failed")
            equal(state.calls, 1)
            truthy(bridge.native_fault)
            equal(state.confirmations, 0)
        end)
    end)

    test("an existing system-owned incident outside the manager map cannot satisfy a new Blueprint request", function()
        blueprint_fixture({ preexisting = true }, function(bridge, state)
            local result = bridge:_dispatch_selected_base("fixture-base", "probe")
            equal(result.status, "probe_call_returned")
            equal(state.calls, 1)
            truthy(bridge:poll_invasion_progress())
            equal(state.confirmations, 0)
            equal(state.progress[1].phase, "pre-existing")
        end)
    end)

    test("Blueprint confirmation requires the returned instance rather than an unrelated start callback", function()
        blueprint_fixture({}, function(bridge, state, _, incident)
            equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "probe_call_returned")
            equal(bridge:_confirm_native_start("fixture-base", "new-blueprint-group", 1, "callback"), false)
            equal(state.confirmations, 0)
            truthy(bridge:_confirm_native_start("fixture-base", "new-blueprint-group", 1, "live-enemy-state", incident))
            equal(state.confirmations, 1)
        end)
    end)

    test("incomplete system identity coverage does not veto the Blueprint call or fabricate attribution", function()
        blueprint_fixture({ incomplete_baseline = true }, function(bridge, state)
            equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "probe_call_returned")
            equal(state.calls, 1)
            equal(bridge.request_windows["fixture-base"].baseline.complete, false)
            truthy(bridge:poll_invasion_progress())
            equal(state.confirmations, 0)
            equal(bridge.native_fault, nil)
        end)
    end)

    test("later ordinary native routes cannot reclaim an earlier unmapped Blueprint incident", function()
        blueprint_fixture({}, function(bridge, state)
            equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "probe_call_returned")
            bridge.event_nearest_test.route = "march"
            bridge.event_manager.StartInvaderMarchForBaseCamp = function(_, id)
                equal(id, "fixture-base")
                state.marches = (state.marches or 0) + 1
            end
            equal(bridge:_dispatch_selected_base("fixture-base", "probe").status, "probe_call_returned")
            equal(state.marches, 1)
            equal(state.calls, 1)
            equal(bridge:_confirm_native_start("fixture-base", "new-blueprint-group", 1, "callback"), false)
            equal(state.confirmations, 0)
            bridge:end_event_tracking()
            equal(bridge.blueprint_used, true)
        end)
    end)

    test("Blueprint route remains a one-base explicit experiment with no arbitrary group", function()
        truthy(Experiments.validate_context({ nearestNativeTest = true, nativeTestRoute = "blueprint" }))
        equal(Experiments.validate_context({ nativeTestRoute = "blueprint" }), false)
        equal(Experiments.validate_context({ nearestNativeTest = true, nativeTestRoute = "blueprint", nativeTestGroup = "anything" }), false)
        equal(Experiments.route("blueprint").method, "RequestIncidentInvaderEnemy_BP")
        equal(Experiments.start_window_seconds(Config.defaults(), "blueprint"), 480)
    end)

    test("Blueprint replies distinguish native null returns, call errors, and not-yet-confirmed incidents", function()
        for _, returned_incident in ipairs({ false, true }) do
            local chats = {}
            Director._report_native_results({
                state = { event = { requestNumber = 14, requesterUid = "PRIVATE_ADMIN" } },
                logger = { info = function() end },
                _chat = function(_, text) chats[#chats + 1] = text end,
            }, { requests = { {
                status = returned_incident and "probe_call_returned" or "dispatch_call_failed",
                native = { method = "RequestIncidentInvaderEnemy_BP", returned = true, incidentReturned = returned_incident },
            } } })
            truthy(chats[1]:find("0 call/inspection error(s)", 1, true))
            truthy(chats[2]:find(returned_incident and "returned an incident object" or "returned no incident", 1, true))
            if not returned_incident then truthy(chats[1]:find("1 native no-incident return(s)", 1, true)) end
            equal(table.concat(chats):find("PRIVATE_ADMIN", 1, true), nil)
        end
    end)
end
