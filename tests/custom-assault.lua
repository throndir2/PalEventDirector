return function(test, equal, truthy)
    local Assault = require("ped.custom_assault")
    local bounties = require("ped.bounties")
    local util = require("ped.util")

    local function scalar_record(value)
        if type(value) ~= "table" then
            truthy(type(value) == "string" or type(value) == "number" or type(value) == "boolean",
                "journal contains a non-scalar value")
            return
        end
        equal(getmetatable(value), nil, "journal contains an opaque object")
        for key, item in pairs(value) do
            truthy(key ~= "scope" and key ~= "actor" and key ~= "handle", "journal contains native evidence")
            scalar_record(item)
        end
    end

    local function fixture(options)
        options = options or {}
        local f = {
            now = 1000, records = {}, recordAttempts = {}, compositions = {}, starts = {}, finishes = {},
            retired = {}, progress = {}, calls = {}, trace = {}, handles = {}, plans = {}, states = {}, actors = {},
            targets = {}, counts = {}, callbackCounts = {}, recordCounts = {}, deleted = {},
            failEngine = {}, failRecords = {}, failCallbacks = {},
        }
        for ordinal = 1, options.bases or 2 do
            f.targets[ordinal] = { id = "private-base-" .. ordinal, scope = { ordinal = ordinal } }
        end
        local function opaque(values)
            return setmetatable(values, { __tostring = function() error("native evidence was stringified") end })
        end
        function f:alive(index, health)
            local actor = self.actors[index] or opaque({ key = "private-target-" .. index })
            self.actors[index] = actor
            self.states[index] = {
                phase = "alive", targetId = actor.key, characterId = self.plans[index].characterId,
                actor = actor, healthBudget = health or 1000 + index,
                instanceGuid = { A = index, B = 100, C = -1, D = 4294967295 },
                playerGuid = options.playerGuid and util.shallow_copy(options.playerGuid) or nil,
            }
            return actor
        end
        local function called(name, index)
            f.counts[name] = (f.counts[name] or 0) + 1
            f.calls[#f.calls + 1] = { name = name, index = index }
            f.trace[#f.trace + 1] = "engine:" .. name .. ":" .. tostring(index or "")
            if f.throwEngine == name then error("PRIVATE_NATIVE_EXCEPTION", 0) end
            return f.failEngine[name] == f.counts[name]
        end
        local engine = {}
        function engine:prepare_spawn(scope, plan)
            if called("prepare_spawn", plan.index) then return false, "bounded placement failure" end
            if scope.ordinal == f.pendingPlacement then return true,{ready=false,pending=true,reason="floor-unavailable"} end
            return true, {ready=scope.ordinal ~= f.unavailablePlacement,reason="floor-unavailable"}
        end
        function engine:spawn(scope, plan)
            local failed = called("spawn", plan.index)
            truthy(not f.handles[plan.index], "a member was spawned twice")
            equal(scope, f.targets[((plan.index - 1) % #f.targets) + 1].scope)
            equal(f.trace[#f.trace - 1], "record:custom_spawn_intent:" .. plan.index)
            f.plans[plan.index] = plan
            if failed then return false, "bounded spawn failure" end
            if f.noHandle then return true, nil end
            local handle = opaque({ index = plan.index })
            f.handles[plan.index] = handle
            f.states[plan.index] = { phase = "pending" }
            if options.immediate and scope.ordinal ~= options.pendingBase then f:alive(plan.index) end
            return true, handle
        end
        function engine:inspect(handle, plan)
            if called("inspect", plan.index) then return false, "bounded inspect failure" end
            f.lastInspectPlan = plan
            equal(handle, f.handles[plan.index])
            equal(plan.handle, handle)
            return true, f.states[plan.index]
        end
        function engine:engage(scope, plan, state)
            if called("engage", plan.index) then return false, "bounded engage failure" end
            f.lastEngagePlan = plan
            equal(f.trace[#f.trace - 1], "record:custom_engage_intent:" .. plan.index)
            equal(scope, f.targets[((plan.index - 1) % #f.targets) + 1].scope)
            equal(state.phase, "alive", "engagement was attempted without a living owned actor")
            equal(state.actor, f.actors[plan.index])
            equal(plan.targetId, state.targetId)
            equal(plan.actor, state.actor)
            equal(plan.handle, f.handles[plan.index])
            if state.playerGuid then
                for key, value in pairs(state.playerGuid) do equal(plan.playerGuid[key], value) end
            end
            return true
        end
        function engine:despawn(scope, plan)
            if called("despawn", plan.index) then return false, "bounded despawn failure" end
            f.lastCleanupPlan = plan
            equal(f.trace[#f.trace - 1], "record:custom_cleanup_intent:" .. plan.index)
            equal(scope, f.targets[((plan.index - 1) % #f.targets) + 1].scope)
            equal(plan.handle, f.handles[plan.index])
            local state = f.states[plan.index]
            truthy(state.phase ~= "capturing", "cleanup touched a capture-in-progress actor")
            if f.captureDuringCleanup then state.phase = "captured" end
            if f.cleanupTerminal then state.phase = f.cleanupTerminal end
            if state.phase == "captured" or state.phase == "dead" or state.phase == "missing" then
                return true, state.phase
            end
            if state.phase == "pending" and f.refusePending then
                return false, "pending handle ownership cannot be established"
            end
            if state.phase == "alive" or state.phase == "escaped" or state.phase == "inactive" then
                equal(plan.actor, state.actor, "cleanup attempted to claim a replacement actor")
                equal(plan.targetId, state.targetId)
                equal(plan.characterId, state.characterId)
                equal(plan.instanceGuid.A, state.instanceGuid.A)
                if state.playerGuid then
                    for key, value in pairs(state.playerGuid) do equal(plan.playerGuid[key], value) end
                end
            end
            if f.cleanupOutcome == "pending" then
                state.phase = f.pendingCleanupPhase or "despawning"
                return true, "pending"
            end
            f.deleted[#f.deleted + 1] = plan.index
            state.phase = "missing"
            return true, f.cleanupOutcome or "despawned"
        end
        function engine:actorKey(actor)
            called("actorKey")
            return type(actor) == "table" and actor.key or nil
        end
        function engine:sameActor(left, right)
            called("sameActor")
            return rawequal(left, right)
        end
        local function callback(name)
            f.callbackCounts[name] = (f.callbackCounts[name] or 0) + 1
            f.trace[#f.trace + 1] = "callback:" .. name
            if f.throwCallback == name then error("PRIVATE_CALLBACK_EXCEPTION", 0) end
            return f.failCallbacks[name] ~= f.callbackCounts[name]
        end
        local callbacks = {}
        function callbacks.record(kind, data)
            scalar_record(data)
            f.recordCounts[kind] = (f.recordCounts[kind] or 0) + 1
            f.recordAttempts[#f.recordAttempts + 1] = { kind = kind, data = data }
            f.trace[#f.trace + 1] = "record:" .. kind .. ":" .. tostring(data.index or "")
            if f.throwRecord == kind then error("PRIVATE_JOURNAL_EXCEPTION", 0) end
            if f.failRecords[kind] == f.recordCounts[kind] then return false, "journal unavailable" end
            f.records[#f.records + 1] = { kind = kind, data = data }
            return true
        end
        function callbacks.composition(id, assignments, err)
            f.compositions[#f.compositions + 1] = { id = id, assignments = assignments, error = err }
            return callback("composition"), "composition unavailable"
        end
        function callbacks.started(id, group)
            truthy((f.counts.engage or 0) > 0, "start preceded engagement")
            f.starts[#f.starts + 1] = { id = id, group = group }
            return callback("started"), "start unavailable"
        end
        function callbacks.finished(id, group, outcome)
            f.finishes[#f.finishes + 1] = { id = id, group = group, outcome = outcome }
            return callback("finished"), "finish unavailable"
        end
        function callbacks.retired(id, reason)
            f.retired[#f.retired + 1] = { id = id, reason = reason }
            if not callback("retired") then return false, "retirement unavailable" end
        end
        function callbacks.progress(id, phase, alive, pending)
            f.progress[#f.progress + 1] = { id = id, phase = phase, alive = alive, pending = pending }
            callback("progress")
        end
        f.assault = Assault.new({
            config = options.config, maxTargets = options.maxTargets or 100, engine = engine, callbacks = callbacks,
            clock = function() return f.now end,
            logger = { info = function() error("unexpected public log") end, warn = function() error("unexpected public log") end },
        })
        function f:start()
            return self.assault:start(self.targets, "all-bounty", "private-occurrence")
        end
        function f:count(name) return self.counts[name] or 0 end
        function f:record(kind)
            for _, record in ipairs(self.records) do if record.kind == kind then return record.data end end
        end
        function f:stopped()
            local calls = #self.calls
            equal(self.assault:poll(), false)
            equal(self.assault:target(self.actors[1]), nil)
            equal(self.assault:close("cancelled"), false)
            equal(self.assault:close("cancelled"), false)
            equal(#self.calls, calls, "adapter was called after a latched failure")
        end
        return f
    end

    test("custom assault durably plans complete compositions without treating handles as starts", function()
        local f = fixture()
        equal(#f.records, 0, "constructor replayed an event")
        local ok, result = f:start()
        truthy(ok)
        equal(result.status, "spawning"); equal(result.baseCount, 2); equal(result.memberCount, 6)
        equal(f:count("spawn"), 0); equal(#f.starts, 0)
        equal(f.records[1].kind, "custom_assault_plan")
        equal(#f.records[1].data.members, 6)
        equal(#f.compositions, 2)
        for _, composition in ipairs(f.compositions) do
            equal(#composition.assignments, 3); equal(composition.error, nil)
        end
        for index, plan in ipairs(f.records[1].data.members) do
            equal(plan.index, index); equal(plan.level, 30)
            equal(plan.slot, math.floor((index - 1) / 2) + 1)
            truthy(plan.characterId:match("^BOSS_"))
            equal(util.count(plan), 7)
        end
        truthy(f.assault:has_live_members(), "queued members disappeared from end/reset accounting")
        truthy(f.assault:poll())
        equal(f:count("spawn"), 6); equal(f:count("inspect"), 6)
        equal(#f.starts, 0); equal(f:count("engage"), 0)
        equal(f:record("custom_spawn_returned").status, "pending")
        for _, record in ipairs(f.records) do scalar_record(record.data) end
    end)

    test("custom assault round-robin batches do not gate other bases on the first base", function()
        local f = fixture({ bases = 3, immediate = true, pendingBase = 1,
            config = { spawnBatchSize = 4, pollBatchSize = 8 } })
        truthy(f:start())
        truthy(f.assault:poll())
        equal(f:count("spawn"), 4)
        equal(#f.starts, 2)
        equal(f.starts[1].id, "private-base-2"); equal(f.starts[2].id, "private-base-3")
        truthy(f.assault:poll()); equal(f:count("spawn"), 8)
        truthy(f.assault:poll()); equal(f:count("spawn"), 9)
        for index, plan in ipairs(f.plans) do
            equal(plan.baseId, "private-base-" .. (((index - 1) % 3) + 1))
            equal(plan.slot, math.floor((index - 1) / 3) + 1)
        end
        for index = 1, 9, 3 do f:alive(index) end
        truthy(f.assault:poll()); truthy(f.assault:poll())
        equal(#f.starts, 3); equal(f.starts[3].id, "private-base-1")
        equal(f.assault:start(f.targets, "all-bounty", "other-occurrence"), false)
        truthy(f.assault:poll())
        equal(f:count("spawn"), 9); equal(#f.starts, 3)
        local first_inspect, last_spawn
        for index, item in ipairs(f.trace) do
            if item:match("^engine:spawn:") then last_spawn = index end
            if item:match("^engine:inspect:") then first_inspect = index; break end
        end
        truthy(first_inspect > last_spawn, "inspection gated the first spawn batch")
    end)

    test("custom assault rotates the full bounty catalog globally and uses private per-base groups", function()
        local f = fixture({ bases = 12, maxTargets = 36 })
        truthy(f:start())
        local plans, seen, groups = f:record("custom_assault_plan").members, {}, {}
        local selector = bounties.new_selector("all-bounty", "private-occurrence")
        for index, plan in ipairs(plans) do
            equal(plan.characterId, bounties.next(selector).id)
            if index <= #bounties.roster() then truthy(not seen[plan.characterId]) end
            seen[plan.characterId] = true
            if index <= 12 then
                truthy(not groups[plan.groupId])
                groups[plan.groupId] = true
                truthy(plan.groupId:match("^ped%-custom:"))
                equal(type(plan.groupId), "string")
            else
                equal(plan.groupId, plans[((index - 1) % 12) + 1].groupId)
            end
        end
        equal(util.count(seen), 34); equal(plans[35].characterId, plans[1].characterId)
        local other = fixture({ bases = 12, maxTargets = 36 })
        truthy(other.assault:start(other.targets, "all-bounty", "another-occurrence"))
        truthy(other:record("custom_assault_plan").members[1].groupId ~= plans[1].groupId)
    end)

    test("custom assault enforces maxTargets and consumes rejected starts before any spawn", function()
        local f = fixture({ maxTargets = 5 })
        local ok, err = f:start()
        equal(ok, false); truthy(err:find("maxTargets", 1, true))
        equal(#f.records, 0); equal(#f.compositions, 0); equal(#f.calls, 0)
        equal(f.assault:start({ f.targets[1] }, "all-bounty", "retry"), false)
        equal(#f.calls, 0)
        local exact = fixture({ maxTargets = 6 })
        truthy(exact:start()); truthy(exact.assault:poll()); equal(exact:count("spawn"), 6)
    end)

    test("custom assault rejects duplicate, sparse, incomplete, or non-custom plans without native work", function()
        for _, variant in ipairs({ "duplicate", "sparse", "scope", "profile", "occurrence" }) do
            local f, profile, occurrence = fixture(), "all-bounty", "event"
            if variant == "duplicate" then f.targets[2].id = f.targets[1].id end
            if variant == "sparse" then f.targets[3], f.targets[2] = f.targets[2], nil end
            if variant == "scope" then f.targets[1].scope = nil end
            if variant == "profile" then profile = "native" end
            if variant == "occurrence" then occurrence = "" end
            equal(f.assault:start(f.targets, profile, occurrence), false, variant)
            equal(#f.calls, 0); equal(#f.records, 0)
        end
    end)

    test("custom assault skips unsupported physical placement without a spawn intent or first-base gate", function()
        local f = fixture({immediate=true})
        f.unavailablePlacement=1
        truthy(f:start())
        truthy(f.assault:poll())
        equal(f:count("spawn"),3)
        equal(#f.starts,1)
        equal(f.starts[1].id,"private-base-2")
        equal(f.assault.bases[1].failed,true)
        for _,record in ipairs(f.records) do
            if record.kind=="custom_spawn_intent" then equal(record.data.baseId,"private-base-2") end
        end
        truthy(f.assault:close("cancelled"))
        equal(f:count("despawn"),3)
        equal(f.assault:has_live_members(),false)
    end)

    test("pending surface searches rotate fairly and never hold another base's spawn", function()
        local f=fixture({immediate=true,config={membersPerBase=1,spawnBatchSize=1}})
        f.pendingPlacement=1
        truthy(f:start())
        truthy(f.assault:poll())
        equal(f:count("spawn"),0)
        truthy(f.assault:poll())
        equal(f:count("spawn"),1); equal(f.starts[1].id,"private-base-2")
        f.pendingPlacement=nil
        truthy(f.assault:poll())
        equal(f:count("spawn"),2); equal(f.starts[2].id,"private-base-1")
        truthy(f.assault:poll())
        equal(f:count("spawn"),2)
    end)

    test("custom assault waits for valid actor evidence and journals initialization before engagement", function()
        local f = fixture({ bases = 1, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        local actor = f:alive(1)
        f.states[1].actor = nil
        truthy(f.assault:poll())
        equal(#f.starts, 0); equal(f:record("custom_member_initialized"), nil)
        f.states[1].actor = { key = nil }
        truthy(f.assault:poll()); equal(#f.starts, 0)
        f.states[1].actor = actor
        truthy(f.assault:poll())
        equal(#f.starts, 1); equal(f:count("engage"), 1)
        equal(f:record("custom_member_initialized").healthBudget, 1001)
        local initialized, engagement, started
        for index, item in ipairs(f.trace) do
            if item == "record:custom_member_initialized:1" then initialized = index end
            if item == "engine:engage:1" then engagement = index end
            if item == "callback:started" then started = index end
        end
        truthy(initialized < engagement and engagement < started)
        truthy(f.assault:poll())
        equal(f:count("spawn"), 1); equal(f:count("engage"), 1); equal(#f.starts, 1)
    end)

    test("custom assault bounds polling with a rotating requested-handle cursor", function()
        local f = fixture({ bases = 3, config = { membersPerBase = 2, spawnBatchSize = 6, pollBatchSize = 2 } })
        truthy(f:start())
        for tick = 1, 4 do
            truthy(f.assault:poll())
            equal(f:count("inspect"), tick * 2)
        end
        local indices = {}
        for _, call in ipairs(f.calls) do if call.name == "inspect" then indices[#indices + 1] = call.index end end
        equal(table.concat(indices, ","), "1,2,3,4,5,6,1,2")
        equal(f:count("spawn"), 6)
        f.states[3], f.states[4] = { phase = "captured" }, { phase = "missing" }
        truthy(f.assault:poll()); equal(f:count("inspect"), 10)
        truthy(f.assault:poll()); equal(f:count("inspect"), 12)
        equal(f.calls[#f.calls].index, 6)
    end)

    test("custom assault retargets only currently owned living actors at the configured interval", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 2 } })
        truthy(f:start()); truthy(f.assault:poll()); equal(f:count("engage"), 2)
        for _, now in ipairs({ 1001, 1004 }) do f.now = now; truthy(f.assault:poll()) end
        equal(f:count("engage"), 2)
        f.now = 1005
        truthy(f.assault:poll()); equal(f:count("engage"), 4)
        f.states[1].phase, f.states[2].phase, f.now = "captured", "dead", 1010
        truthy(f.assault:poll()); equal(f:count("engage"), 4)
        equal(f.assault:has_live_members(), false)
        local calls = #f.calls
        f.now = 1015; truthy(f.assault:poll())
        equal(#f.calls, calls)
    end)

    test("custom assault target contexts are fresh scalar copies for the exact tracked actor only", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        local context = f.assault:target(f.actors[1])
        truthy(context)
        equal(util.count(context), 5)
        equal(context.target_id, "private-target-1"); equal(context.base_id, "private-base-1")
        equal(context.group_id, f.starts[1].group); equal(context.health_budget, 1001)
        equal(context.target_name, f.plans[1].name)
        scalar_record(context)
        context.health_budget, context.base_id, context.target_name = 1, "wrong", "wrong"
        local next_context = f.assault:target(f.actors[1])
        truthy(next_context ~= context)
        equal(next_context.health_budget, 1001); equal(next_context.base_id, "private-base-1")
        local inspected = f:count("inspect")
        equal(f.assault:target({ key = "unrelated-natural-target" }), nil)
        equal(f.assault:target({ key = f.actors[1].key }), nil)
        equal(f:count("inspect"), inspected, "an unrelated callback was inspected as an owned member")
        equal(f.assault.failure, nil)
    end)

    test("custom assault preserves the initial maximum HP and private GUID evidence immutably", function()
        local f = fixture({ bases = 1, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll()); f:alive(1, 4321)
        truthy(f.assault:poll())
        local initial = f:record("custom_member_initialized")
        for _, health in ipairs({ 9999, 10 }) do
            f.states[1].healthBudget = health
            equal(f.assault:target(f.actors[1]).health_budget, 4321)
        end
        equal(initial.healthBudget, 4321); equal(f.recordCounts.custom_member_initialized, 1)
        f.states[1].instanceGuid.A = 99
        equal(initial.instanceGuid.A, 1, "journal retained mutable adapter evidence")
        equal(f.assault:target(f.actors[1]), nil)
        truthy(f.assault.failure:find("identity", 1, true))
        f:stopped()
    end)

    test("custom assault excludes captured actors before credit and never cleans them up", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.states[1].phase = "captured"
        equal(f.assault:target(f.actors[1]), nil)
        equal(f.retired[1].reason, "captured")
        truthy(f.compositions[2].error)
        equal(f.assault:has_live_members(), false)
        truthy(f.assault:close("cancelled"))
        equal(f:count("despawn"), 0); equal(#f.deleted, 0)
        equal(f.assault:target(f.actors[1]), nil)
    end)

    test("custom assault inactive actors stay owned, resume alive, and permit qualified close or lifetime cleanup", function()
        for _, mode in ipairs({ "explicit", "lifetime" }) do
            local f = fixture({ bases = 1, immediate = true,
                config = { membersPerBase = 1, lifetimeSeconds = 20 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            local state = f.states[1]
            state.phase, f.now = "inactive", 1006
            local context, reason = f.assault:target(f.actors[1])
            equal(context, nil); truthy(reason:find("inactive", 1, true))
            truthy(f.assault:poll())
            equal(f.assault.members[1].phase, "inactive")
            equal(f.assault.members[1].handle, f.handles[1])
            equal(f.assault.members[1].actor, f.actors[1])
            equal(f.assault.members[1].playerGuid.A, 0)
            truthy(f.assault:has_live_members())
            equal(f:count("engage"), 1); equal(f:count("despawn"), 0)
            equal(#f.retired, 0); equal(#f.finishes, 0); equal(#f.compositions, 1)
            f.states[1], f.now = { phase = "inactive" }, 1007
            local inspected = f:count("inspect")
            truthy(f.assault:poll())
            equal(f:count("inspect"), inspected + 1)
            equal(f.assault.failure, nil, "inactivity was mistaken for lost ownership evidence")
            state.phase, f.states[1], f.now = "alive", state, 1008
            truthy(f.assault:poll())
            equal(f:count("engage"), 2); equal(#f.starts, 1); equal(f:count("spawn"), 1)
            equal(f.assault:target(f.actors[1]).health_budget, 1001)
            state.phase = "inactive"
            if mode == "lifetime" then f.now = 1020; truthy(f.assault:poll())
            else truthy(f.assault:close("cancelled")) end
            equal(f:count("despawn"), 1); equal(f:count("engage"), 2)
            equal(f:record("custom_cleanup_intent").phase, "inactive")
            equal(f:record("custom_cleanup_blocked"), nil)
            equal(f.finishes[1].outcome, mode == "lifetime" and "timeout" or "cancelled")
            equal(f.assault.closed, true); equal(f.assault:has_live_members(), false)
        end
    end)

    test("custom assault capture-in-progress pauses scoring and engagement then resumes without a new start", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 },
            playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
        truthy(f:start()); truthy(f.assault:poll())
        local state = f.states[1]
        state.phase, f.now = "capturing", 1001
        local context, reason = f.assault:target(f.actors[1])
        equal(context, nil); truthy(reason:find("capturing", 1, true))
        truthy(f.assault:poll())
        equal(f.assault.members[1].phase, "capturing")
        equal(f:count("engage"), 1); equal(f:count("despawn"), 0)
        equal(#f.retired, 0); equal(#f.finishes, 0); equal(#f.compositions, 1)
        truthy(f.assault:has_live_members())
        state.phase, f.now = "alive", 1002
        truthy(f.assault:poll())
        equal(f.assault.members[1].phase, "alive")
        equal(f:count("engage"), 1, "capture failure bypassed the retarget interval")
        truthy(f.assault:target(f.actors[1]))
        f.states[1], f.now = { phase = "capturing" }, 1065
        truthy(f.assault:poll())
        equal(f.assault:target(f.actors[1]), nil)
        equal(f.assault.failure, nil, "capture polling was confused with initialization timeout")
        equal(f.assault.members[1].handle, f.handles[1])
        equal(f.assault.members[1].actor, f.actors[1])
        equal(f.assault.members[1].playerGuid.A, 0)
        f.states[1], f.now = state, 1066
        truthy(f.assault:poll())
        equal(f:count("engage"), 2); equal(#f.starts, 1)
        equal(f:count("spawn"), 1); equal(#f.retired, 0)
        equal(f.assault:target(f.actors[1]).health_budget, 1001)
    end)

    test("custom assault completed capture revokes ownership without adopting the captured player identity", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 },
            playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.states[1] = { phase = "capturing" }
        truthy(f.assault:poll()); equal(#f.retired, 0)
        f.states[1] = { phase = "captured", playerGuid = { A = 55, B = 0, C = 0, D = 0 } }
        equal(f.assault:target(f.actors[1]), nil)
        equal(f.assault.failure, nil)
        equal(f.assault:has_live_members(), false)
        equal(f.retired[1].reason, "captured"); equal(#f.retired, 1)
        equal(f:record("custom_member_retired").playerGuid.A, 0)
        equal(f.assault.members[1].playerGuid.A, 0)
        truthy(f.compositions[2].error); equal(#f.finishes, 1)
        truthy(f.assault:poll()); truthy(f.assault:close("cancelled"))
        equal(f:count("despawn"), 0); equal(#f.deleted, 0)
        equal(f.assault:target(f.actors[1]), nil)
    end)

    test("custom assault capture before first engagement never fabricates a start or initialization", function()
        for _, full_evidence in ipairs({ false, true }) do
            local f = fixture({ bases = 1, config = { membersPerBase = 1 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll()); f:alive(1)
            local state = f.states[1]
            state.phase = "capturing"
            if not full_evidence then f.states[1] = { phase = "capturing" } end
            truthy(f.assault:poll())
            equal(#f.starts, 0); equal(f:count("engage"), 0); equal(#f.retired, 0)
            equal(f.assault:target(f.actors[1]), nil)
            equal(f.recordCounts.custom_member_initialized or 0, full_evidence and 1 or 0)
            truthy(f.assault:has_live_members())
            state.phase, f.states[1] = "alive", state
            truthy(f.assault:poll())
            equal(#f.starts, 1); equal(f:count("engage"), 1)
            equal(f.recordCounts.custom_member_initialized, 1)
        end
    end)

    test("custom assault explicit and lifetime cleanup retain capturing actors for recovery", function()
        for _, mode in ipairs({ "explicit", "lifetime", "journal" }) do
            local f = fixture({ bases = 1, immediate = true,
                config = { membersPerBase = 2, pollBatchSize = 2, lifetimeSeconds = 3 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.states[1] = { phase = "capturing" }
            if mode == "journal" then f.failRecords.custom_cleanup_blocked = 1 end
            local inspected, ok, err = f:count("inspect")
            if mode == "lifetime" then f.now = 1003; ok, err = f.assault:poll()
            else ok, err = f.assault:close("cancelled") end
            equal(ok, false, mode)
            truthy(err:find(mode == "journal" and "journal unavailable" or "recovery required", 1, true))
            equal(f:count("inspect"), inspected + 1)
            equal(f:count("despawn"), 0); equal(#f.deleted, 0)
            equal(#f.retired, 0); equal(#f.finishes, 0)
            truthy(f.assault:has_live_members())
            equal(f.assault.members[1].phase, "capturing")
            equal(f.assault.members[1].handle, f.handles[1])
            equal(f.assault.members[1].actor, f.actors[1])
            equal(f.assault.members[1].playerGuid.A, 0)
            equal(f.assault.members[2].phase, "alive")
            truthy(f:record("custom_assault_cleanup_intent"))
            if mode ~= "journal" then
                equal(f:record("custom_cleanup_blocked").error, "capture_in_progress")
                equal(f:record("custom_cleanup_blocked").phase, "capturing")
            end
            f:stopped()
        end
    end)

    test("custom assault escaped members receive bounded ownership-checked leash cleanup", function()
        local f = fixture({ bases = 2, immediate = true,
            config = { membersPerBase = 2, spawnBatchSize = 4, pollBatchSize = 2 },
            playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
        truthy(f:start()); truthy(f.assault:poll()); truthy(f.assault:poll())
        equal(f:count("engage"), 4)
        for index = 1, 4 do f.states[index].phase = "escaped" end
        local context, reason = f.assault:target(f.actors[1])
        equal(context, nil); truthy(reason:find("escaped", 1, true))
        equal(f:count("despawn"), 0); equal(#f.retired, 0)
        equal(f:record("custom_cleanup_intent"), nil, "target lookup performed leash cleanup")
        for batch = 1, 2 do
            local inspected = f:count("inspect")
            truthy(f.assault:poll())
            equal(f:count("inspect"), inspected + 2)
            equal(f:count("despawn"), batch * 2)
        end
        equal(table.concat(f.deleted, ","), "1,2,3,4")
        equal(f:count("engage"), 4); equal(f:count("spawn"), 4)
        equal(#f.starts, 2); equal(#f.finishes, 2)
        equal(f.assault:has_live_members(), false)
        equal(f.recordCounts.custom_cleanup_intent, 4)
        equal(f.recordCounts.custom_cleanup_returned, 4)
        for _, retired in ipairs(f.retired) do equal(retired.reason, "escaped") end
        for _, finished in ipairs(f.finishes) do equal(finished.outcome, "cancelled") end
        for _, record in ipairs(f.records) do
            scalar_record(record.data)
            if record.kind == "custom_cleanup_intent" then
                local plan = f.plans[record.data.index]
                equal(record.data.reason, "escaped"); equal(record.data.phase, "escaped")
                equal(record.data.baseId, plan.baseId); equal(record.data.groupId, plan.groupId)
                equal(record.data.healthBudget, 1000 + plan.index)
                equal(record.data.playerGuid.A, 0)
            end
        end
        local calls = #f.calls
        truthy(f.assault:poll()); truthy(f.assault:close("completed"))
        equal(#f.calls, calls, "leash cleanup was retried")
    end)

    test("custom assault remembers an observed escape without cleaning during a subsequent capture attempt", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.states[1].phase = "escaped"
        equal(f.assault:target(f.actors[1]), nil)
        f.states[1].phase = "capturing"
        truthy(f.assault:poll())
        equal(f:count("despawn"), 0); equal(#f.retired, 0)
        f.states[1].phase, f.now = "alive", 1001
        equal(f.assault:target(f.actors[1]), nil, "an escaped member regained score eligibility")
        truthy(f.assault:poll())
        equal(f:count("engage"), 1)
        equal(f:count("despawn"), 1); equal(f.retired[1].reason, "escaped")
        equal(f:record("custom_cleanup_intent").phase, "alive")
        equal(f:record("custom_cleanup_intent").reason, "escaped")
    end)

    test("custom assault explicit and lifetime cleanup also ownership-check escaped members", function()
        for _, mode in ipairs({ "explicit", "lifetime" }) do
            local f = fixture({ bases = 1, immediate = true,
                config = { membersPerBase = 1, pollBatchSize = 1, lifetimeSeconds = 3 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.states[1].phase = "escaped"
            if mode == "lifetime" then f.now = 1003; truthy(f.assault:poll())
            else truthy(f.assault:close("cancelled")) end
            equal(f:count("despawn"), 1); equal(f:count("engage"), 1)
            equal(f.retired[1].reason, "escaped")
            equal(f:record("custom_cleanup_intent").phase, "escaped")
            equal(f:record("custom_cleanup_intent").reason, "escaped")
            equal(f:record("custom_cleanup_returned").playerGuid.A, 0)
            equal(f.finishes[1].outcome, mode == "lifetime" and "timeout" or "cancelled")
            truthy(f.assault.closed)
        end
    end)

    test("custom assault leash cleanup failures retain evidence and stop later native operations", function()
        for _, boundary in ipairs({ "native", "custom_cleanup_intent", "custom_cleanup_returned", "custom_member_retired" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 2 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.states[1].phase = "escaped"
            if boundary == "native" then f.failEngine.despawn = 1
            else f.failRecords[boundary] = 1 end
            local inspected = f:count("inspect")
            equal(f.assault:poll(), false, boundary)
            equal(f:count("inspect"), inspected + 1)
            equal(f:count("despawn"), boundary == "custom_cleanup_intent" and 0 or 1)
            equal(f.assault.members[1].phase, "escaped")
            equal(f.assault.members[1].handle, f.handles[1])
            equal(f.assault.members[1].actor, f.actors[1])
            equal(f.assault.members[1].playerGuid.A, 0)
            equal(f.assault.members[2].phase, "alive")
            equal(#f.retired, 0); equal(#f.finishes, 0)
            truthy(f.compositions[#f.compositions].error)
            truthy(f.assault:has_live_members())
            f:stopped()
        end
    end)

    test("custom assault leash cleanup terminal races still unrank escaped targets without fabricating a kill", function()
        for _, outcome in ipairs({ "dead", "captured", "missing" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.states[1].phase, f.cleanupTerminal = "escaped", outcome
            truthy(f.assault:poll())
            equal(#f.deleted, 0)
            equal(f:record("custom_cleanup_returned").outcome, outcome)
            equal(f.retired[1].reason, "escaped")
            truthy(f.compositions[2].error)
            equal(f.assault:target(f.actors[1]), nil)
            equal(f.assault:has_live_members(), false)
        end
    end)

    test("custom assault escaped states require full actor evidence before any cleanup", function()
        local f = fixture({ bases = 1, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.states[1] = { phase = "escaped" }
        equal(f.assault:poll(), false)
        equal(f:count("despawn"), 0)
        equal(f:record("custom_member_initialized"), nil)
        truthy(f.assault:has_live_members())
        f:stopped()
    end)

    test("custom assault persists immutable optional player GUIDs including the all-zero native owner", function()
        for _, player_guid in ipairs({ { A = 0, B = 0, C = 0, D = 0 },
            { A = 7, B = -1, C = 4294967295, D = 10 } }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 }, playerGuid = player_guid })
            truthy(f:start()); truthy(f.assault:poll())
            local initial = f:record("custom_member_initialized")
            equal(util.count(initial.playerGuid), 4)
            equal(initial.playerGuid.A, player_guid.A)
            truthy(initial.playerGuid ~= f.states[1].playerGuid)
            truthy(initial.playerGuid ~= f.assault.members[1].playerGuid)
            equal(f.lastEngagePlan.playerGuid.A, player_guid.A)
            f.lastEngagePlan.playerGuid.A = 555
            local context = f.assault:target(f.actors[1])
            truthy(context); equal(context.playerGuid, nil)
            equal(util.count(context), 5)
            equal(f.lastInspectPlan.playerGuid.A, player_guid.A)
            f.lastInspectPlan.playerGuid.A = 66
            truthy(f.assault:target(f.actors[1]))
            equal(f.lastInspectPlan.playerGuid.A, player_guid.A)
            truthy(f.assault:close("cancelled"))
            equal(f.lastCleanupPlan.playerGuid.A, player_guid.A)
            equal(f:record("custom_assault_cleanup_intent").members[1].playerGuid.A, player_guid.A)
            equal(f:record("custom_cleanup_intent").playerGuid.A, player_guid.A)
            equal(initial.playerGuid.A, player_guid.A)
            for _, record in ipairs(f.records) do scalar_record(record.data) end
        end
    end)

    test("custom assault rejects changed or missing player identity for still-owned actors", function()
        for _, phase in ipairs({ "alive", "dead", "escaped", "capturing", "omitted" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            if phase == "omitted" then f.states[1].playerGuid = nil
            else f.states[1].phase, f.states[1].playerGuid.A = phase, 99 end
            equal(f.assault:target(f.actors[1]), nil, phase)
            truthy(f.assault.failure:find("player identity", 1, true))
            equal(f:record("custom_member_initialized").playerGuid.A, 0)
            equal(f.assault.members[1].playerGuid.A, 0)
            equal(f:count("despawn"), 0); equal(#f.retired, 0)
            f:stopped()
        end
    end)

    test("custom assault rejects malformed player GUIDs and still requires a nonzero instance GUID", function()
        for _, variant in ipairs({ "incomplete", "extra", "fraction", "opaque", "infinite", "zero-instance" }) do
            local f = fixture({ bases = 1, config = { membersPerBase = 1 } })
            truthy(f:start()); truthy(f.assault:poll()); f:alive(1)
            local guid = { A = 0, B = 0, C = 0, D = 0 }
            f.states[1].playerGuid = guid
            if variant == "incomplete" then guid.D = nil
            elseif variant == "extra" then guid.E = 1
            elseif variant == "fraction" then guid.A = 0.5
            elseif variant == "opaque" then setmetatable(guid, {})
            elseif variant == "infinite" then guid.B = math.huge
            else f.states[1].instanceGuid = { A = 0, B = 0, C = 0, D = 0 } end
            equal(f.assault:poll(), false, variant)
            equal(#f.starts, 0); equal(f:count("engage"), 0)
            equal(f:record("custom_member_initialized"), nil)
            f:stopped()
        end
    end)

    test("custom assault polling and cleanup reject a changed full owner identity before despawn", function()
        for _, operation in ipairs({ "poll", "close" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.states[1].phase, f.states[1].playerGuid.D = "escaped", 123
            if operation == "poll" then equal(f.assault:poll(), false)
            else equal(f.assault:close("cancelled"), false) end
            equal(f:count("despawn"), 0)
            equal(f:record("custom_cleanup_intent"), nil)
            equal(f.assault.members[1].playerGuid.D, 0)
            equal(f.assault.members[1].handle, f.handles[1])
            truthy(f.assault:has_live_members())
            f:stopped()
        end
    end)

    test("custom assault journals player identity first supplied after initialization before credit", function()
        for _, fails in ipairs({ false, true }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
            truthy(f:start()); truthy(f.assault:poll())
            equal(f:record("custom_member_initialized").playerGuid, nil)
            f.states[1].playerGuid = { A = 0, B = 0, C = 0, D = 0 }
            if fails then f.failRecords.custom_member_identity_completed = 1 end
            local context, reason = f.assault:target(f.actors[1])
            if fails then
                equal(context, nil); truthy(reason:find("journal unavailable", 1, true))
                f:stopped()
            else
                truthy(context)
                equal(f:record("custom_member_identity_completed").playerGuid.A, 0)
                equal(f:record("custom_member_identity_completed").instanceGuid.A, 1)
                equal(f:record("custom_member_identity_completed").healthBudget, 1001)
                truthy(f.assault:target(f.actors[1]))
                equal(f.recordCounts.custom_member_identity_completed, 1)
            end
            equal(f.assault.members[1].playerGuid.A, 0)
            equal(f.recordCounts.custom_member_initialized, 1)
        end
    end)

    test("custom assault halts on changed initialized identities without touching replacements", function()
        for _, changed in ipairs({ "actor", "targetId", "characterId", "instanceGuid" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 2 } })
            truthy(f:start()); truthy(f.assault:poll())
            if changed == "actor" then f.states[1].actor = { key = f.actors[1].key }
            elseif changed == "instanceGuid" then f.states[1].instanceGuid.B = 123
            else f.states[1][changed] = "unrelated-replacement" end
            local inspected = f:count("inspect")
            equal(f.assault:poll(), false, changed)
            equal(f:count("inspect"), inspected + 1)
            equal(f:count("despawn"), 0)
            equal(f.assault.members[1].handle, f.handles[1])
            truthy(f.assault:has_live_members())
            truthy(f.compositions[#f.compositions].error)
            f:stopped()
        end
    end)

    test("custom assault rejects reused actors and wrong requested characters before claiming a member", function()
        local f = fixture({ config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        f:alive(1); f:alive(2)
        f.states[2].actor, f.states[2].targetId = f.actors[1], f.actors[1].key
        equal(f.assault:poll(), false)
        equal(#f.starts, 1)
        truthy(f.assault.failure:find("reused", 1, true))
        f:stopped()
        local uninitialized = fixture({ bases = 1, config = { membersPerBase = 1 } })
        truthy(uninitialized:start()); truthy(uninitialized.assault:poll()); uninitialized:alive(1)
        uninitialized.states[1].characterId = "BOSS_Unrequested"
        equal(uninitialized.assault:poll(), false)
        equal(#uninitialized.starts, 0); equal(uninitialized:count("engage"), 0)
    end)

    test("custom assault polling death does not invent credit and retains evidence for a late actual callback", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.states[1].phase = "dead"
        truthy(f.assault:poll())
        equal(#f.retired, 1); equal(f.retired[1].reason, "dead")
        equal(util.count(f.retired[1]), 2, "polling fabricated killer or final-hit data")
        equal(#f.finishes, 1); equal(f.finishes[1].outcome, "completed")
        equal(#f.compositions, 1); equal(f.assault:has_live_members(), false)
        local context = f.assault:target(f.actors[1])
        truthy(context); equal(context.health_budget, 1001)
        equal(#f.retired, 1); equal(#f.finishes, 1)
        truthy(f.assault:close("completed"))
        equal(f:count("despawn"), 0)
        truthy(f.assault:target(f.actors[1]), "owned death evidence was dropped during close")
        f.states[1] = { phase = "missing" }
        equal(f.assault:target(f.actors[1]), nil)
        equal(#f.retired, 1); equal(#f.finishes, 1)
    end)

    test("custom assault actual death callbacks can arrive before terminal polling", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.states[1].phase = "dead"
        truthy(f.assault:target(f.actors[1]))
        equal(#f.retired, 0, "target lookup retired the score target before the actual death hook")
        equal(#f.finishes, 0, "target lookup finished the event before the actual death hook")
        truthy(f.assault:poll()); truthy(f.assault:poll())
        equal(#f.retired, 1); equal(#f.finishes, 1)
        equal(f:count("spawn"), 1); equal(f:count("engage"), 1)
    end)

    test("custom assault never reports a base as started when its members retire before engagement", function()
        for _, phase in ipairs({ "dead", "captured", "missing" }) do
            local f = fixture({ bases = 1, config = { membersPerBase = 1 } })
            truthy(f:start()); truthy(f.assault:poll()); f:alive(1)
            f.states[1].phase = phase
            truthy(f.assault:poll())
            equal(#f.starts, 0); equal(#f.finishes, 0); equal(f:count("engage"), 0)
            equal(f.assault:has_live_members(), false)
            truthy(f.compositions[2].error)
            equal(f.progress[#f.progress].phase, "failed")
        end
    end)

    test("custom assault terminal handles need no fabricated initialized actor evidence", function()
        for _, phase in ipairs({ "dead", "captured", "missing" }) do
            local f = fixture({ bases = 1, config = { membersPerBase = 1 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.states[1] = { phase = phase }
            truthy(f.assault:poll())
            equal(f.assault:has_live_members(), false)
            equal(#f.starts, 0); equal(#f.finishes, 0); equal(#f.retired, 0)
            equal(f:record("custom_member_initialized"), nil)
            equal(f:record("custom_member_retired").phase, phase)
            truthy(f.compositions[2].error)
            truthy(f.assault:close("cancelled"))
            equal(f:count("despawn"), 0)
        end
    end)

    test("custom assault engine false results permanently stop every later adapter operation", function()
        for _, operation in ipairs({ "spawn", "inspect", "engage", "despawn" }) do
            local f = fixture({ immediate = true, config = { membersPerBase = 1, spawnBatchSize = 1 } })
            truthy(f:start())
            f.failEngine[operation] = 1
            if operation == "despawn" then
                truthy(f.assault:poll())
                equal(f.assault:close("cancelled"), false)
            else
                equal(f.assault:poll(), false, operation)
            end
            truthy(f.assault.failure:find(operation, 1, true))
            truthy(f.compositions[#f.compositions].error)
            truthy(f.assault:has_live_members())
            f:stopped()
            equal(f:count("spawn"), 1, "a failed native operation was retried")
        end
    end)

    test("custom assault uncaught native and durable callback exceptions still latch the instance", function()
        for _, kind in ipairs({ "native", "journal", "callback" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
            truthy(f:start())
            if kind == "native" then f.throwEngine = "spawn"
            elseif kind == "journal" then f.throwRecord = "custom_spawn_returned"
            else f.throwCallback = "started" end
            local ok, err = pcall(function() return f.assault:poll() end)
            equal(ok, false); truthy(err:find("PRIVATE_", 1, true))
            truthy(f.assault.failure)
            f:stopped()
        end
    end)

    test("custom assault durable record failures halt at each spawn and initialization boundary", function()
        for _, kind in ipairs({ "custom_assault_plan", "custom_spawn_intent", "custom_spawn_returned",
            "custom_member_initialized", "custom_engage_intent" }) do
            local f = fixture({ immediate = true, config = { membersPerBase = 1, spawnBatchSize = 1 } })
            f.failRecords[kind] = 1
            local ok, err = f:start()
            if kind ~= "custom_assault_plan" then truthy(ok); ok, err = f.assault:poll() end
            equal(ok, false, kind); truthy(err:find("journal unavailable", 1, true))
            equal(f:count("engage"), 0)
            equal(f:count("spawn"), (kind == "custom_assault_plan" or kind == "custom_spawn_intent") and 0 or 1)
            if kind == "custom_spawn_returned" then
                equal(f.assault.members[1].handle, f.handles[1])
                equal(f:count("inspect"), 0)
            end
            f:stopped()
        end
    end)

    test("custom assault mandatory callback rejections stop later spawns and confirmations", function()
        for _, name in ipairs({ "composition", "started", "finished", "retired" }) do
            local f = fixture({ immediate = true, config = { membersPerBase = 1, spawnBatchSize = 1 } })
            f.failCallbacks[name] = 1
            if name == "composition" then
                equal(f:start(), false); equal(f:count("spawn"), 0)
            else
                truthy(f:start())
                if name == "started" then equal(f.assault:poll(), false)
                else
                    truthy(f.assault:poll())
                    f.states[1].phase = "dead"
                    equal(f.assault:poll(), false)
                end
            end
            truthy(f.assault.failure:find(name, 1, true))
            f:stopped()
        end
    end)

    test("custom assault initialization timeouts retain uncertainty and never retry or abandon handles", function()
        local f = fixture({ config = { membersPerBase = 1, spawnBatchSize = 1, initializationSeconds = 4 } })
        truthy(f:start()); truthy(f.assault:poll())
        local calls = #f.calls
        f.now = 1004
        local ok, err = f.assault:poll()
        equal(ok, false); truthy(err:find("retained", 1, true))
        equal(#f.calls, calls, "a deadline triggered more spawning or native inspection")
        equal(f:count("spawn"), 1)
        equal(f.assault.members[1].handle, f.handles[1])
        equal(f.assault.members[1].phase, "pending")
        truthy(f.assault:has_live_members())
        truthy(f:record("custom_member_initialization_timeout"))
        truthy(f.compositions[#f.compositions].error); equal(#f.finishes, 0)
        f:stopped()
        local intent = f:record("custom_assault_cleanup_intent")
        truthy(intent); equal(intent.members[1].spawnRequested, true)
        equal(intent.members[2].spawnRequested, false)
        equal(f.recordCounts.custom_assault_cleanup_intent, 1)
    end)

    test("custom assault lifetime closes owned members and queued work without spawning again", function()
        local f = fixture({ bases = 1, immediate = true,
            config = { membersPerBase = 2, spawnBatchSize = 1, lifetimeSeconds = 3 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.now = 1003
        truthy(f.assault:poll())
        equal(f:count("spawn"), 1); equal(f:count("despawn"), 1)
        equal(#f.finishes, 1); equal(f.finishes[1].outcome, "timeout")
        equal(f.assault:has_live_members(), false)
        local calls, records = #f.calls, #f.records
        truthy(f.assault:poll()); truthy(f.assault:close("cancelled"))
        equal(#f.calls, calls); equal(#f.records, records)
        equal(f.assault:target(f.actors[1]), nil)
    end)

    test("custom assault lifetime cleanup respects the polling inspection budget until fully closed", function()
        local f = fixture({ bases = 3, immediate = true,
            config = { membersPerBase = 2, spawnBatchSize = 6, pollBatchSize = 2, lifetimeSeconds = 3 } })
        truthy(f:start()); truthy(f.assault:poll())
        equal(f:count("spawn"), 6); equal(f:count("inspect"), 2)
        f.now = 1003
        for tick = 1, 3 do
            local inspected = f:count("inspect")
            truthy(f.assault:poll())
            equal(f:count("inspect"), inspected + 2)
            equal(f:count("despawn"), tick * 2)
            equal(f.assault:has_live_members(), tick ~= 3)
            equal(f:count("spawn"), 6)
        end
        truthy(f.assault.closed)
        equal(f.recordCounts.custom_assault_cleanup_intent, 1)
        equal(f.recordCounts.custom_assault_closed, 1)
        for _, finished in ipairs(f.finishes) do equal(finished.outcome, "timeout") end
    end)

    test("custom assault cleanup is bounded to requested owned members and skips captures and missing actors", function()
        local f = fixture({ bases = 1, immediate = true })
        truthy(f:start()); truthy(f.assault:poll())
        f.states[1].phase = "captured"
        f.states[2] = { phase = "missing" }
        truthy(f.assault:close("cancelled"))
        equal(f:count("despawn"), 1); equal(table.concat(f.deleted, ","), "3")
        equal(f.retired[1].reason, "captured"); equal(f.retired[2].reason, "missing")
        equal(f.retired[3].reason, "despawned")
        equal(f.assault:has_live_members(), false)
        truthy(f:record("custom_assault_cleanup_intent"))
        truthy(f:record("custom_assault_closed"))
        for _, record in ipairs(f.records) do scalar_record(record.data) end
        local calls = #f.calls
        truthy(f.assault:close("cancelled")); equal(#f.calls, calls)
    end)

    test("custom assault cleanup refuses changed ownership evidence before calling despawn", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 2 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.states[1].actor = { key = "unrelated-natural-target" }
        equal(f.assault:close("cancelled"), false)
        equal(f:count("despawn"), 0); equal(#f.deleted, 0)
        equal(f.assault.members[1].actor, f.actors[1])
        equal(f.assault.members[2].handle, f.handles[2])
        truthy(f.assault:has_live_members())
        f:stopped()
    end)

    test("custom assault cleanup honors adapter-qualified pending cancellation or explicit inability", function()
        for _, refuses in ipairs({ false, true }) do
            local f = fixture({ bases = 1, config = { membersPerBase = 1 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.refusePending = refuses
            local ok, err = f.assault:close("cancelled")
            equal(ok, not refuses)
            equal(#f.starts, 0); equal(#f.finishes, 0)
            if refuses then
                truthy(err:find("ownership", 1, true))
                truthy(f.assault:has_live_members())
                equal(f.assault.members[1].handle, f.handles[1])
                f:stopped()
            else
                equal(f.assault:has_live_members(), false); equal(f:count("despawn"), 1)
            end
        end
    end)

    test("custom assault adapter capture races never count as game-managed destruction or score credit", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.captureDuringCleanup = true
        truthy(f.assault:close("cancelled"))
        equal(#f.deleted, 0)
        equal(f.retired[1].reason, "captured")
        equal(f.assault:target(f.actors[1]), nil)
    end)

    test("custom assault close before dispatch cancels the durable queue without native operations", function()
        local f = fixture()
        truthy(f:start()); truthy(f.assault:close("cancelled"))
        equal(#f.calls, 0); equal(#f.starts, 0); equal(#f.finishes, 0)
        equal(f.assault:has_live_members(), false)
        truthy(f.assault:poll()); truthy(f.assault:close("cancelled"))
        equal(#f.calls, 0); equal(f.assault:start(f.targets, "all-bounty", "second"), false)
        equal(f.recordCounts.custom_assault_cleanup_intent, 1)
        equal(f.recordCounts.custom_member_retired, 6)
    end)

    test("custom assault explicit close acknowledges pending cleanup without claiming completion or reissuing despawn", function()
        local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 },
            playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
        truthy(f:start()); truthy(f.assault:poll())
        local owned_state = f.states[1]
        f.cleanupOutcome = "pending"
        truthy(f.assault:close("cancelled"))
        equal(f.assault.closed, false); truthy(f.assault:has_live_members())
        equal(f.assault.members[1].phase, "despawning")
        equal(f.assault.members[1].cleanupRequested, true)
        equal(f.assault.members[1].cleanupRequestedAt, 1000)
        equal(f.assault.members[1].handle, f.handles[1])
        equal(f.assault.members[1].actor, f.actors[1])
        equal(f.assault.members[1].playerGuid.A, 0)
        equal(f:record("custom_cleanup_returned").outcome, "pending")
        equal(f:record("custom_cleanup_completed"), nil)
        equal(f:record("custom_assault_closed"), nil)
        equal(#f.retired, 0); equal(#f.finishes, 0); equal(#f.deleted, 0)
        equal(f.assault:target(f.actors[1]), nil)
        f.states[1], f.now = { phase = "despawning" }, 1001
        truthy(f.assault:close("cancelled"))
        f.states[1], f.now = { phase = "pending" }, 1002
        truthy(f.assault:poll())
        owned_state.phase, f.states[1], f.now = "alive", owned_state, 1006
        truthy(f.assault:poll())
        equal(f:count("engage"), 1, "pending cleanup was retargeted after the attack interval")
        equal(f:count("despawn"), 1); equal(f:count("spawn"), 1)
        equal(f.assault.closed, false); truthy(f.assault:has_live_members())
        equal(f.recordCounts.custom_cleanup_intent, 1)
        equal(f.recordCounts.custom_cleanup_returned, 1)
        equal(f.assault.members[1].cleanupRequestedAt, 1000)
        f.states[1], f.now = { phase = "missing" }, 1007
        truthy(f.assault:poll())
        equal(f.assault.closed, true); equal(f.assault:has_live_members(), false)
        equal(f.assault.members[1].phase, "despawned")
        equal(f.retired[1].reason, "despawned")
        equal(f:record("custom_cleanup_completed").outcome, "despawned")
        equal(f:record("custom_cleanup_completed").observedPhase, "missing")
        equal(f:record("custom_cleanup_completed").cleanupRequestedAt, 1000)
        equal(f.recordCounts.custom_assault_closed, 1)
        equal(#f.finishes, 1); equal(f.finishes[1].outcome, "cancelled")
        local calls = #f.calls
        truthy(f.assault:poll()); truthy(f.assault:close("cancelled"))
        equal(#f.calls, calls); equal(f:count("despawn"), 1)
        for _, record in ipairs(f.records) do scalar_record(record.data) end
    end)

    test("custom assault escaped pending cleanup stays inside the rotating poll budget without new commands", function()
        local f = fixture({ bases = 2, immediate = true,
            config = { membersPerBase = 2, spawnBatchSize = 4, pollBatchSize = 2 },
            playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
        truthy(f:start()); truthy(f.assault:poll()); truthy(f.assault:poll())
        f.cleanupOutcome = "pending"
        for index = 1, 4 do f.states[index].phase = "escaped" end
        for batch = 1, 2 do
            f.now = 1000 + batch
            local inspected = f:count("inspect")
            truthy(f.assault:poll())
            equal(f:count("inspect"), inspected + 2)
            equal(f:count("despawn"), batch * 2)
        end
        f.states[1].phase, f.states[2].phase = "alive", "escaped"
        f.states[3], f.states[4], f.now = { phase = "pending" }, { phase = "despawning" }, 1006
        for _ = 1, 2 do
            local inspected = f:count("inspect")
            truthy(f.assault:poll())
            equal(f:count("inspect"), inspected + 2)
            equal(f:count("despawn"), 4)
        end
        equal(f:count("spawn"), 4); equal(f:count("engage"), 4)
        equal(#f.retired, 0); equal(#f.finishes, 0)
        truthy(f.assault:has_live_members()); equal(f.assault.closed, false)
        for index = 1, 4 do
            equal(f.assault.members[index].phase, "despawning")
            equal(f.assault:target(f.actors[index]), nil)
            f.states[index] = { phase = "missing" }
        end
        f.now = 1007
        for _ = 1, 2 do
            local inspected = f:count("inspect")
            truthy(f.assault:poll())
            equal(f:count("inspect"), inspected + 2)
        end
        equal(f:count("despawn"), 4)
        equal(f.recordCounts.custom_cleanup_intent, 4)
        equal(f.recordCounts.custom_cleanup_returned, 4)
        equal(f.recordCounts.custom_cleanup_completed, 4)
        equal(#f.finishes, 2)
        for _, retired in ipairs(f.retired) do equal(retired.reason, "escaped") end
        equal(f.assault:has_live_members(), false)
        truthy(f.assault:close("completed"))
        equal(f.assault.closed, true)
        truthy(f:record("custom_assault_cleanup_intent").members[1].cleanupRequested)
        equal(f:record("custom_assault_cleanup_intent").members[1].cleanupRequestedAt, 1001)
    end)

    test("custom assault lifetime cleanup revisits pending members fairly before recording a closed event", function()
        local f = fixture({ bases = 3, immediate = true,
            config = { membersPerBase = 1, spawnBatchSize = 3, pollBatchSize = 1, lifetimeSeconds = 3 },
            playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
        truthy(f:start())
        for _ = 1, 3 do truthy(f.assault:poll()) end
        f.cleanupOutcome, f.now = "pending", 1003
        local function bounded_poll()
            local inspected = f:count("inspect")
            truthy(f.assault:poll())
            equal(f:count("inspect"), inspected + 1)
        end
        for count = 1, 3 do
            bounded_poll()
            equal(f:count("despawn"), count)
            equal(f.assault.closed, false)
        end
        f.states[1], f.states[2], f.states[3] =
            { phase = "missing" }, { phase = "despawning" }, { phase = "captured" }
        for _ = 1, 3 do bounded_poll(); equal(f.assault.closed, false) end
        equal(f:record("custom_assault_closed"), nil)
        truthy(f.assault:has_live_members())
        bounded_poll()
        f.states[2] = { phase = "dead" }
        bounded_poll()
        equal(f.assault.closed, true); equal(f.assault:has_live_members(), false)
        equal(f:count("despawn"), 3); equal(f:count("engage"), 3)
        equal(f.recordCounts.custom_cleanup_completed, 3)
        equal(f.recordCounts.custom_assault_closed, 1)
        for _, finished in ipairs(f.finishes) do equal(finished.outcome, "timeout") end
    end)

    test("custom assault pending cleanup of an uninitialized handle waits without fabricating an actor or start", function()
        local f = fixture({ bases = 1, config = { membersPerBase = 1, initializationSeconds = 4 } })
        truthy(f:start()); truthy(f.assault:poll())
        f.cleanupOutcome, f.now = "pending", 1003
        truthy(f.assault:close("cancelled"))
        equal(f.assault.closed, false); truthy(f.assault:has_live_members())
        f.states[1], f.now = { phase = "pending" }, 1005
        truthy(f.assault:poll())
        equal(f.assault.failure, nil, "cleanup reused the expired spawn-initialization deadline")
        equal(f.assault.members[1].cleanupRequestedAt, 1003)
        f.states[1], f.now = { phase = "missing" }, 1006
        truthy(f.assault:poll())
        equal(f.assault.closed, true); equal(f.assault:has_live_members(), false)
        equal(#f.starts, 0); equal(#f.finishes, 0); equal(#f.retired, 0)
        equal(f:record("custom_member_initialized"), nil)
        equal(f:record("custom_member_retired").phase, "despawned")
        equal(f:count("despawn"), 1)
    end)

    test("custom assault pending cleanup accepts only qualified terminal completion and never credits cleanup deaths", function()
        for _, phase in ipairs({ "missing", "dead", "captured" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.cleanupOutcome = "pending"
            truthy(f.assault:close("cancelled"))
            f.states[1] = { phase = phase }
            if phase == "captured" then f.states[1].playerGuid = { A = 9, B = 8, C = 7, D = 6 } end
            truthy(f.assault:close("cancelled"))
            local outcome = phase == "missing" and "despawned" or phase
            equal(f:record("custom_cleanup_completed").outcome, outcome)
            equal(f.assault.members[1].phase, outcome)
            equal(f.assault.members[1].playerGuid.A, 0)
            equal(f.assault.closed, true); equal(f.assault:has_live_members(), false)
            equal(f:count("despawn"), 1); equal(#f.deleted, 0)
            equal(f.assault:target(f.actors[1]), nil)
            equal(#f.retired, 1); equal(util.count(f.retired[1]), 2)
        end
    end)

    test("custom assault capture discovered during pending cleanup blocks recovery without issuing another despawn", function()
        for _, source in ipairs({ "explicit", "escaped" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.cleanupOutcome = "pending"
            if source == "explicit" then truthy(f.assault:close("cancelled"))
            else f.states[1].phase = "escaped"; truthy(f.assault:poll()) end
            f.states[1] = { phase = "capturing" }
            local ok, err = f.assault:poll()
            equal(ok, false); truthy(err:find("recovery required", 1, true))
            equal(f:record("custom_cleanup_blocked").cleanupRequestedAt, 1000)
            equal(f:count("despawn"), 1)
            equal(f.assault.members[1].phase, "capturing")
            equal(f.assault.members[1].handle, f.handles[1])
            equal(f.assault.members[1].actor, f.actors[1])
            equal(f.assault.members[1].playerGuid.A, 0)
            equal(f.assault.closed, false); truthy(f.assault:has_live_members())
            equal(#f.retired, 0); equal(f:record("custom_cleanup_completed"), nil)
            f:stopped()
        end
    end)

    test("custom assault pending cleanup rejects replacement identities instead of claiming completion", function()
        for _, field in ipairs({ "actor", "targetId", "characterId", "instanceGuid", "playerGuid" }) do
            for _, operation in ipairs({ "poll", "close" }) do
                local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 },
                    playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
                truthy(f:start()); truthy(f.assault:poll())
                f.cleanupOutcome = "pending"
                truthy(f.assault:close("cancelled"))
                if field == "actor" then f.states[1].actor = { key = f.actors[1].key }
                elseif field == "instanceGuid" or field == "playerGuid" then f.states[1][field].A = 123
                else f.states[1][field] = "unrelated-replacement" end
                if operation == "poll" then equal(f.assault:poll(), false, field)
                else equal(f.assault:close("cancelled"), false, field) end
                equal(f:count("despawn"), 1)
                equal(f.assault.members[1].handle, f.handles[1])
                equal(f.assault.members[1].actor, f.actors[1])
                equal(f.assault.members[1].instanceGuid.A, 1)
                equal(f.assault.members[1].playerGuid.A, 0)
                equal(f.assault.closed, false); truthy(f.assault:has_live_members())
                equal(f:record("custom_cleanup_completed"), nil)
                equal(f:record("custom_assault_closed"), nil)
                f:stopped()
            end
        end
    end)

    test("custom assault pending cleanup has a fixed confirmation deadline and retains uncertainty on timeout", function()
        for _, source in ipairs({ "explicit", "escaped" }) do
            for _, operation in ipairs({ "poll", "close" }) do
                local f = fixture({ bases = 1, immediate = true,
                    config = { membersPerBase = 1, initializationSeconds = 4 },
                    playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
                truthy(f:start()); truthy(f.assault:poll())
                f.cleanupOutcome, f.now = "pending", 1002
                if source == "explicit" then truthy(f.assault:close("cancelled"))
                else f.states[1].phase = "escaped"; truthy(f.assault:poll()) end
                f.now = 1004; truthy(f.assault:poll())
                equal(f.assault.members[1].cleanupRequestedAt, 1002)
                local calls, ok, err = #f.calls
                f.now = 1006
                if operation == "poll" then ok, err = f.assault:poll()
                else ok, err = f.assault:close("cancelled") end
                equal(ok, false); truthy(err:find("cleanup confirmation timed out", 1, true))
                truthy(err:find("recovery required", 1, true))
                equal(#f.calls, calls, "cleanup timeout issued more native operations")
                equal(f:record("custom_cleanup_timeout").cleanupRequestedAt, 1002)
                equal(f.assault.members[1].phase, "despawning")
                equal(f.assault.members[1].handle, f.handles[1])
                equal(f.assault.members[1].playerGuid.A, 0)
                equal(f.assault.closed, false); truthy(f.assault:has_live_members())
                equal(#f.retired, 0); equal(f:count("despawn"), 1)
                f:stopped()
            end
        end
    end)

    test("custom assault pending cleanup journal failures never drop tracking or repeat destruction", function()
        for _, kind in ipairs({ "custom_cleanup_returned", "custom_cleanup_completed",
            "custom_member_retired", "custom_cleanup_timeout" }) do
            local f = fixture({ bases = 1, immediate = true,
                config = { membersPerBase = 1, initializationSeconds = 4 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.cleanupOutcome = "pending"
            local ok, err
            if kind == "custom_cleanup_returned" then
                f.failRecords[kind] = 1
                ok, err = f.assault:close("cancelled")
            else
                truthy(f.assault:close("cancelled"))
                f.failRecords[kind] = 1
                if kind == "custom_cleanup_timeout" then f.now = 1004
                else f.states[1] = { phase = "missing" } end
                ok, err = f.assault:poll()
            end
            equal(ok, false); truthy(err:find("journal unavailable", 1, true))
            equal(f.assault.members[1].handle, f.handles[1])
            equal(f.assault.members[1].cleanupRequested, true)
            equal(f.assault.members[1].cleanupRequestedAt, 1000)
            equal(f.assault.closed, false); truthy(f.assault:has_live_members())
            equal(f:count("despawn"), 1); equal(#f.retired, 0)
            f:stopped()
        end
    end)

    test("custom assault pending cleanup inspection failures stop the instance without another native request", function()
        for _, throws in ipairs({ false, true }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 1 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.cleanupOutcome = "pending"
            truthy(f.assault:close("cancelled"))
            if throws then
                f.throwEngine = "inspect"
                local ok, err = pcall(function() return f.assault:poll() end)
                equal(ok, false); truthy(err:find("PRIVATE_NATIVE_EXCEPTION", 1, true))
            else
                f.failEngine.inspect = f:count("inspect") + 1
                equal(f.assault:poll(), false)
            end
            equal(f.assault.closed, false); truthy(f.assault:has_live_members())
            equal(f:count("despawn"), 1)
            f:stopped()
        end
    end)

    test("custom assault retirement and cleanup journal failures preserve ownership and halt later cleanup", function()
        for _, kind in ipairs({ "custom_member_retired", "custom_assault_cleanup_intent",
            "custom_cleanup_intent", "custom_cleanup_returned", "custom_assault_closed" }) do
            local f = fixture({ bases = 1, immediate = true, config = { membersPerBase = 2 } })
            truthy(f:start()); truthy(f.assault:poll())
            f.failRecords[kind] = 1
            local ok, err
            if kind == "custom_member_retired" then
                f.states[1].phase = "dead"
                ok, err = f.assault:poll()
                equal(#f.retired, 0)
            else
                ok, err = f.assault:close("cancelled")
            end
            equal(ok, false, kind); truthy(err:find("journal unavailable", 1, true))
            equal(f.assault.members[1].handle, f.handles[1])
            if kind == "custom_cleanup_returned" then
                equal(f:count("despawn"), 1)
                equal(f.assault.members[1].phase, "alive", "undurable cleanup silently dropped ownership")
            elseif kind ~= "custom_assault_closed" then
                equal(f:count("despawn"), 0)
            end
            f:stopped()
        end
    end)

    test("custom assault rejects malformed handles, state, health, and cleanup outcomes without fallback", function()
        for _, variant in ipairs({ "handle", "phase", "health", "guid", "cleanup" }) do
            local f = fixture({ bases = 1, config = { membersPerBase = 1 } })
            truthy(f:start())
            if variant == "handle" then
                f.noHandle = true
                equal(f.assault:poll(), false)
            else
                truthy(f.assault:poll()); f:alive(1)
                if variant == "phase" then f.states[1].phase = "unknown"
                elseif variant == "health" then f.states[1].healthBudget = 0 / 0
                elseif variant == "guid" then f.states[1].instanceGuid.actor = f.actors[1] end
                if variant == "cleanup" then
                    truthy(f.assault:poll())
                    f.cleanupOutcome = "maybe"
                    equal(f.assault:close("cancelled"), false)
                else equal(f.assault:poll(), false) end
            end
            truthy(f.assault:has_live_members())
            f:stopped()
        end
    end)
end
