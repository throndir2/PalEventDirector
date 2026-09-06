return function(test, equal, truthy)
    local Experiments = require("ped.native_experiments")
    local Logger = require("ped.logger")
    local json = require("ped.json")

    test("native experiment routes cannot become arbitrary calls or widen ordinary starts", function()
        equal(Experiments.route().method, "Debug_InvaderMarchForNearCamp")
        equal(Experiments.route("admission").method, "RequestIncidentInvaderEnemy")
        equal(Experiments.route("march").method, "StartInvaderMarchForBaseCamp")
        for _, route in ipairs({ false, {}, "StartInvaderMarchAll", "ForceStop", "unknown" }) do
            equal(Experiments.route(route), nil)
            equal(Experiments.validate_context({ nearestNativeTest = true, nativeTestRoute = route }), false)
        end
        equal(Experiments.validate_context({ nativeTestRoute = "admission" }), false)
        equal(Experiments.validate_context({ nearestNativeTest = "yes" }), false)
        equal(Experiments.validate_context({ nearestNativeTest = true, nativeTestRoute = "march", nativeTestGroup = "Invader_Group_Test" }), false)
        truthy(Experiments.validate_context({ nearestNativeTest = true, nativeTestRoute = "debug", nativeTestGroup = "Invader_Group_Test" }))
    end)

    test("native experiment records reject private fields opaque values and unsafe numeric data", function()
        local writes = {}
        local logger = Logger.new({ experiment_file_path = "fixture.ndjson", filesystem = {
            append = function(_, content) writes[#writes + 1] = content; return true end,
        } })
        local function record()
            return { schemaVersion = 1, kind = "state", run = 100, observation = 1, sequence = 1,
                timestamp = 1000, elapsed = 0, slots = 1, occupied = true }
        end
        truthy(logger:native_experiment(record()))
        equal(json.decode(writes[1]).occupied, true)
        for _, key in ipairs({ "playerUid", "baseId", "address", "X", "location", "settings" }) do
            local value = record()
            value[key] = "DO_NOT_EMIT"
            equal(logger:native_experiment(value), false)
        end
        for _, value in ipairs({ {}, math.huge, -math.huge, 0 / 0 }) do
            local candidate = record()
            candidate.slots = value
            equal(logger:native_experiment(candidate), false)
        end
        local candidate = record()
        candidate.kind, candidate.slots, candidate.occupied = "group", nil, nil
        candidate.group = "Invader_Group_" .. string.rep("a", 32)
        equal(logger:native_experiment(candidate), false)
        equal(#writes, 1)
    end)

    test("passive experiment sampling coalesces missed deadlines and never schedules native starts", function()
        local now, records = 1000, {}
        local experiments = Experiments.new({ clock = function() return now end, run = 100,
            emit = function(record) records[#records + 1] = record; return true end })
        local scope = experiments:open({ route = "admission", request = 4, base_id = "PRIVATE_BASE",
            recipient = "PRIVATE_PLAYER", manager = {}, world = {}, base = {} })
        truthy(scope)
        equal(experiments:next_sample(), nil)
        now = 1031
        local due_scope, offset, skipped = experiments:next_sample()
        equal(due_scope, scope)
        equal(offset, 30)
        equal(skipped, 3)
        equal(experiments:next_sample(), nil)
        now = 1600
        due_scope, offset, skipped = experiments:next_sample()
        equal(due_scope, scope)
        equal(offset, 600)
        equal(skipped, 3)
        equal(experiments:next_sample(), nil)
        truthy(experiments:close(scope, "complete"))
        equal(#experiments.scopes, 0)
        equal(#records, 2)
        equal(json.encode(records):find("PRIVATE", 1, true), nil)
        equal(records[2].sequence, records[1].sequence + 1)
    end)

    test("experiment retention is bounded and write failures are not reported as successful", function()
        local records, fail = {}, false
        local experiments = Experiments.new({ clock = function() return 1000 end, run = 100,
            emit = function(record)
                if fail then return false, "fixture disk error" end
                records[#records + 1] = record
                return true
            end })
        local first
        for index = 1, 9 do
            local scope = experiments:open({ route = "inspect" })
            truthy(scope)
            first = first or scope
        end
        equal(#experiments.scopes, 8)
        equal(first.closed, true)
        equal(records[9].code, "evicted")
        fail = true
        local scope, reason = experiments:open({ route = "debug" })
        equal(scope, nil)
        equal(reason, "fixture disk error")
        equal(#experiments.scopes, 8)
        experiments:clear()
        equal(#experiments.scopes, 0)
    end)

    test("unverified debug group input is withheld from logs when it resembles a private identifier", function()
        local records = {}
        local experiments = Experiments.new({ clock = function() return 1000 end, run = 100,
            emit = function(record) records[#records + 1] = record; return true end })
        local group = string.rep("a", 32)
        truthy(Experiments.validate_context({ nearestNativeTest = true, nativeTestRoute = "debug", nativeTestGroup = group }))
        local scope = experiments:open({ route = "debug", group = group })
        truthy(scope)
        equal(scope.group, group)
        equal(records[1].group, nil)
        equal(records[1].groupWithheld, true)
        equal(json.encode(records):find(group, 1, true), nil)
    end)
end
