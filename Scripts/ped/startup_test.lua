local json = require("ped.json")
local path = require("ped.path")
local util = require("ped.util")
local filesystem = require("ped.filesystem")
local Store = require("ped.store")
local Diagnostic = require("ped.preflight_diagnostic")

local Test = {}
Test.__index = Test

local CASES = { ["spawn-cleanup"] = 1, movement = 1, ["two-base-movement"] = 2, prewarm = 1, engagement = 1 }
local TERMINAL = { passed = true, failed = true, blocked = true }

function Test.validate_state(state, run_id)
    assert(type(state) == "table" and state.schemaVersion == 1 and state.runId == run_id and CASES[state.case]
        and (state.status == "running" or TERMINAL[state.status])
        and type(state.mutationStarted) == "boolean" and type(state.cleanupComplete) == "boolean"
        and type(state.artifactSha256) == "string" and #state.artifactSha256 == 64 and state.artifactSha256:match("^%x+$"),
        "Startup test outcome is invalid")
    for _, field in ipairs({ "spawned", "initialized", "cleaned", "moved" }) do
        assert(util.is_integer(state[field]) and state[field] >= 0 and state[field] <= CASES[state.case], "Startup test counts are invalid")
    end
    assert(state.cleaned <= state.spawned and state.initialized <= state.spawned
        and (state.mutationStarted or state.spawned == 0), "Startup test ownership counts are inconsistent")
    assert(util.is_integer(state.npcsFinalized or 0) and (state.npcsFinalized or 0) >= 0
        and state.cleaned + (state.npcsFinalized or 0) <= state.spawned, "Startup NPC finalization counts are invalid")
    if state.cleanupComplete and state.mutationStarted then
        assert((state.status == "passed" or state.status == "blocked") and state.cleaned + (state.npcsFinalized or 0) == state.spawned,
            "Startup test cleanup outcome is inconsistent")
        assert((state.helpersCreated or 0) == (state.helpersCleaned or 0) + (state.helpersFinalized or 0), "Startup support cleanup is incomplete")
    end
    return state
end

function Test.read_state(directory, run_id, logger, fs)
    local store = Store.new(directory, logger, fs)
    local last = store.records[#store.records]
    if not last or not last.state then return nil end
    return Test.validate_state(last.state, run_id)
end

function Test.finalize_legacy_spawn(store, evidence)
    local last = store.records[#store.records]
    local previous = last and last.state
    assert(previous, "No startup test state is available for finalization")
    Test.validate_state(previous, previous.runId)
    assert(previous.sourceRevision == "f671c2200ba6a83ba879e19c2b7acbf92d2fcbc8"
        and previous.artifactSha256 == "de3f829239dda321796229d5b40274b9587a8fe7c17e764ab898b10a639d6643"
        and previous.case == "spawn-cleanup" and previous.status == "failed" and previous.stage == "spawn"
        and previous.code == "custom-assault-identity" and previous.spawned == 0
        and previous.initialized == 0 and previous.mutationStarted and not previous.cleanupComplete,
        "This startup failure is outside the audited legacy finalization scope")
    local member = previous.members and previous.members[1]
    assert(#previous.members == 1 and member.characterId == "BOSS_Hunter_Rifle" and member.level == 30
        and member.spawnRequested == true and not member.instanceGuid, "Legacy spawn parameters do not match")
    assert(type(evidence) == "table" and evidence.processExitVerified == true and evidence.runId == previous.runId
        and evidence.certificateSha256 == "47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f"
        and evidence.serverExecutableSha256 == "61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256 == "2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe",
        "Verified old-process teardown and the pinned native certificate are required")
    local state = util.deep_copy(previous)
    state.status, state.code, state.cleanupComplete = "blocked", "legacy-runtime-finalized", true
    state.failedArtifactSha256 = previous.artifactSha256
    state.finalization = util.deep_copy(evidence)
    state.finalization.disposition = "old-runtime-ended; ownership-transfers-preserved"
    state.finalizedRequests = 1
    local ok, reason = store:append("startup_legacy_runtime_finalized", { disposition = state.finalization.disposition }, state)
    if not ok then return false, reason end
    return store:save_snapshot(state)
end

function Test.finalize_support_only(store, evidence)
    local last = store.records[#store.records]
    local previous = last and last.state
    assert(previous, "No startup support state is available")
    Test.validate_state(previous, previous.runId)
    assert(previous.sourceRevision == "122eea9932ff9bd8286277a2525d9d78828de601"
        and previous.artifactSha256 == "c60075ba179ef7d5d01f493b8cf9b13fa191ceb4aad967a0f8e3865d8c57f30f"
        and previous.case == "two-base-movement" and previous.status == "running" and previous.stage == "support-wait"
        and previous.spawned == 0 and previous.initialized == 0 and #previous.members == 0
        and previous.helpersCreated == 2 and previous.mutationStarted and not previous.cleanupComplete,
        "This failure is outside the audited support-only finalization scope")
    for _, record in ipairs(store.records) do assert(record.kind ~= "startup_spawn_intent", "NPC work prevents support-only finalization") end
    assert(type(evidence) == "table" and evidence.processExitVerified == true and evidence.runId == previous.runId
        and evidence.dumpSha256 == "d9e0840ab4d5d1f3e375daba5f47bb85eea46b49b28377b5ceeb184bd872985a"
        and evidence.serverExecutableSha256 == "61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256 == "2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe",
        "Verified crashed-world exit and pinned support-only evidence are required")
    local state = util.deep_copy(previous)
    state.status, state.code, state.cleanupComplete = "blocked", "support-runtime-finalized", true
    state.failedArtifactSha256 = previous.artifactSha256
    state.helpersFinalized = previous.helpersCreated - previous.helpersCleaned
    state.finalization = util.deep_copy(evidence)
    state.finalization.disposition = "noncharacter-support-world-ended"
    local ok, reason = store:append("startup_support_runtime_finalized", {disposition=state.finalization.disposition}, state)
    if not ok then return false, reason end
    return store:save_snapshot(state)
end

function Test.finalize_pending_cleanup(store, evidence)
    local last = store.records[#store.records]
    local previous = last and last.state
    assert(previous, "No pending cleanup state is available")
    Test.validate_state(previous, previous.runId)
    assert(previous.sourceRevision == "e4c8cc8dcc7ff3bbd8c5eff93168d5b756170cf3"
        and previous.artifactSha256 == "0f24085e4719a967e45ffcf665c0a8b55ca982c66673537e80ff85454a37640f"
        and previous.case == "two-base-movement" and previous.status == "failed" and previous.stage == "cleanup"
        and previous.code == "custom-assault-despawn" and previous.spawned == 2 and previous.initialized == 2
        and previous.moved == 2 and previous.helpersCreated == 2 and not previous.cleanupComplete,
        "This cleanup timeout is outside the audited finalization scope")
    assert(#previous.members == 2, "Pending cleanup member count differs")
    for _, member in ipairs(previous.members) do
        assert(member.characterId == "BOSS_Hunter_Rifle" and member.level == 30 and member.cleanupRequested == true
            and member.instanceGuid and member.playerGuid, "Pending cleanup lacks exact identity or intent")
        local nonzero = false
        for _, key in ipairs({"A","B","C","D"}) do
            assert(util.is_integer(member.instanceGuid[key]) and member.playerGuid[key] == 0, "Pending cleanup identity is invalid")
            nonzero = nonzero or member.instanceGuid[key] ~= 0
        end
        assert(nonzero, "Pending cleanup instance identity is empty")
    end
    assert(type(evidence) == "table" and evidence.processExitVerified == true and evidence.runId == previous.runId
        and evidence.certificateSha256 == "47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f"
        and evidence.serverExecutableSha256 == "61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256 == "2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe",
        "Verified process exit and pinned runtime-finalization evidence are required")
    local state = util.deep_copy(previous)
    state.status, state.code, state.cleanupComplete = "blocked", "pending-cleanup-runtime-finalized", true
    state.failedArtifactSha256 = previous.artifactSha256
    state.npcsFinalized = previous.spawned - previous.cleaned
    state.helpersFinalized = previous.helpersCreated - previous.helpersCleaned
    state.finalization = util.deep_copy(evidence)
    state.finalization.disposition = "pending-cleanup-world-ended; ownership-transfers-preserved"
    local ok, reason = store:append("startup_pending_cleanup_runtime_finalized", {disposition=state.finalization.disposition}, state)
    if not ok then return false, reason end
    return store:save_snapshot(state)
end

function Test.new(options)
    local plan = assert(options.plan)
    assert(plan.schemaVersion == 1 and CASES[plan.case], "Startup test plan is invalid")
    assert(type(plan.runId) == "string" and plan.runId:match("^[a-z0-9%-]+$") and #plan.runId <= 80, "Startup test run identity is invalid")
    assert(type(plan.sourceRevision) == "string" and #plan.sourceRevision == 40 and plan.sourceRevision:match("^%x+$"), "Startup test source is invalid")
    assert(type(plan.artifactSha256) == "string" and #plan.artifactSha256 == 64 and plan.artifactSha256:match("^%x+$"), "Startup test artifact is invalid")
    local self = setmetatable({
        engine = assert(options.engine), store = assert(options.store), logger = assert(options.logger),
        clock = options.clock or util.now_seconds, runtime = {}, cursor = 1, damageQueue = {},
        state = { schemaVersion = 1, runId = plan.runId, case = plan.case, sourceRevision = plan.sourceRevision,
            artifactSha256 = plan.artifactSha256,
            status = "running", stage = "world", startedAt = (options.clock or util.now_seconds)(),
            mutationStarted = false, cleanupComplete = false, members = {},
            spawned = 0, initialized = 0, moved = 0, cleaned = 0, simultaneous = false,
            helpers = {}, helpersCreated = 0, helpersCleaned = 0 },
    }, Test)
    assert(self.store.sequence == 0, "Startup test was already consumed; it cannot be replayed")
    self:_save("startup_test_started")
    return self
end

function Test:on_damage(attacker, defender, amount)
    if self.stopped or self.state.stage ~= "engagement" or not util.is_integer(amount) or amount <= 0 then return end
    if #self.damageQueue >= 64 then self.damageOverflow = true; return end
    self.damageQueue[#self.damageQueue + 1] = {attacker=attacker,defender=defender,amount=amount}
end

function Test:_damage_witness()
    local pending = self.damageQueue
    self.damageQueue = {}
    for _, event in ipairs(pending) do
        for index, runtime in ipairs(self.runtime) do
            local member = self.state.members[index]
            if runtime.actor and member.phase == "alive" and not member.cleanupRequested then
                if self.engine:sameActor(runtime.actor, event.attacker) then
                    local ok, allowed = self.engine:startup_damage_target(self.scopes[index],event.defender)
                    if not ok then return self:halt(allowed) end
                    if allowed then
                        self.state.dealtDamageEvents = (self.state.dealtDamageEvents or 0) + 1
                        self.state.dealtDamage = (self.state.dealtDamage or 0) + event.amount
                    end
                end
                if self.engine:sameActor(runtime.actor,event.defender) then
                    self.state.receivedDamageEvents = (self.state.receivedDamageEvents or 0) + 1
                end
            end
        end
    end
    if #pending > 0 then return self:_save("startup_damage_observed") end
    return true
end

function Test:_save(kind)
    local ok = self.store:append(kind, { stage = self.state.stage, status = self.state.status }, self.state)
    if not ok then
        self.state.status, self.state.code = "failed", "journal-write"
        self.stopped = true
        self.logger:error("Startup test journal failed; native work stopped")
        return false
    end
    local saved = self.store:save_snapshot(self.state)
    if not saved then
        self.state.status, self.state.code = "failed", "snapshot-write"
        self.stopped = true
        self.logger:error("Startup test snapshot failed; native work stopped")
        return false
    end
    return true
end

function Test:halt(reason)
    if self.stopped then return false end
    self.state.status = "failed"
    self.state.code = type(reason) == "string" and reason:match("%[([a-z0-9%-]+)%]") or nil
    self.state.code = self.state.code or Diagnostic.classify_error(reason)
    self.state.cleanupComplete = not self.state.mutationStarted
    self.state.finishedAt = self.clock()
    self:_save("startup_test_failed")
    self.stopped = true
    self.logger:error("Startup test stopped", { stage = self.state.stage, code = self.state.code,
        spawned = self.state.spawned, initialized = self.state.initialized, cleaned = self.state.cleaned })
    return false
end

function Test:_stage(stage)
    self.state.stage, self.state.stageStartedAt, self.cursor = stage, self.clock(), 1
    return self:_save("startup_test_stage")
end

function Test:_finish(status, code)
    self.state.status, self.state.code = status, code
    self.state.cleanupComplete, self.state.finishedAt = true, self.clock()
    self:_save("startup_test_finished")
    self.stopped = true
    self.logger:info("Startup test finished", { case = self.state.case, status = status, code = code,
        spawned = self.state.spawned, initialized = self.state.initialized,
        moved = self.state.moved, cleaned = self.state.cleaned, simultaneous = self.state.simultaneous })
end

function Test:_plan_members()
    for index, scope in ipairs(self.scopes) do
        self.state.members[index] = { index = index, baseId = scope.baseId,
            groupId = "startup:" .. self.state.runId, slot = 1, characterId = "BOSS_Hunter_Rifle",
            level = 30, phase = "planned", spawnLocation = scope.positions and util.shallow_copy(scope.positions[1]) or nil,
            baseOrigin = util.shallow_copy(scope.origin), leashRadius = scope.leashRadius }
    end
    return self:_stage("spawn")
end

function Test:_cleaned_npcs()
    if self.state.helpersCreated > self.state.helpersCleaned then return self:_stage("support-cleanup") end
    return self:_finish(self.state.failure and "blocked" or "passed", self.state.failure or "complete")
end

local function distance2(left, right)
    return (left.X - right.X) ^ 2 + (left.Y - right.Y) ^ 2
end

function Test:_tick()
    if self.stopped or TERMINAL[self.state.status] then return end
    local now = self.clock()
    local stage = self.state.stage
    if stage == "world" then
        local ok, result = self.engine:startup_prepare(CASES[self.state.case])
        if not ok then return self:halt(result) end
        if not result then
            if now >= self.state.startedAt + 120 then self:_finish("blocked", "world-or-bases-not-ready") end
            return
        end
        self.state.physical = result.physical
        self.state.availableBases = result.availableBases
        if result.blockedCode then
            self.scopes = result.candidates
            if type(self.scopes) ~= "table" or #self.scopes ~= CASES[self.state.case] then return self:_finish("blocked", result.blockedCode) end
            self.support = self.engine:startup_support(self.scopes)
            local prepared, available = self.support:prepare()
            if not prepared then return self:halt(available) end
            if not available then return self:_finish("blocked", "streaming-subsystem-unavailable") end
            return self:_stage("support-spawn")
        end
        self.scopes = result.scopes
        assert(type(self.scopes) == "table" and #self.scopes == CASES[self.state.case], "Startup test returned an invalid base count")
        if self.state.case == "prewarm" then return self:_finish("passed", "physical-ready-without-support") end
        return self:_plan_members()
    elseif stage == "support-spawn" then
        local index = self.cursor
        if index > #self.scopes then return self:_stage("support-configure") end
        self.state.mutationStarted = true
        self.state.helpers[index] = { phase = "requested" }
        if not self:_save("startup_support_intent") then return end
        local ok, identity = self.support:begin(index)
        if not ok then return self:halt(identity) end
        self.state.helpers[index] = { phase = "deferred", identity = identity }
        self.state.helpersCreated = self.state.helpersCreated + 1
        if not self:_save("startup_support_created") then return end
        self.cursor = index + 1
    elseif stage == "support-configure" then
        local index = self.cursor
        if index > self.state.helpersCreated then return self:_stage("support-wait") end
        if not self:_save("startup_support_configure_intent") then return end
        local ok, result = self.support:finish(index)
        if not ok then return self:halt(result) end
        self.state.helpers[index].phase = "configured"
        if not self:_save("startup_support_configured") then return end
        self.cursor = index + 1
    elseif stage == "support-wait" then
        local ready = 0
        for index, helper in ipairs(self.state.helpers) do
            local ok, observation = self.support:poll(index)
            if not ok then return self:halt(observation) end
            helper.observation = observation
            if observation.ready then ready = ready + 1 end
        end
        if ready == self.state.helpersCreated then
            self.state.physicalPrewarmPassed = true
            if self.state.case == "prewarm" then return self:_stage("support-cleanup") end
            return self:_plan_members()
        end
        if now >= self.state.stageStartedAt + 120 then
            self.state.failure = "physical-prewarm-timeout"
            return self:_stage("support-cleanup")
        end
        if now >= (self.nextSupportCheckpoint or 0) then
            self.nextSupportCheckpoint = now + 5
            return self:_save("startup_support_observation")
        end
    elseif stage == "support-cleanup" then
        for index, helper in ipairs(self.state.helpers) do
            if not helper.cleaned then
                if not helper.cleanupRequested then
                    helper.cleanupRequested = true
                    helper.cleanupRequestedAt = now
                    if not self:_save("startup_support_cleanup_intent") then return end
                end
                local ok, complete = self.support:close(index)
                if not ok then return self:halt(complete) end
                if complete then
                    helper.cleaned = true
                    self.state.helpersCleaned = self.state.helpersCleaned + 1
                    if not self:_save("startup_support_cleaned") then return end
                elseif now >= helper.cleanupRequestedAt + 60 then
                    return self:halt("Startup support cleanup did not complete")
                end
            end
        end
        if self.state.helpersCleaned == self.state.helpersCreated then return self:_cleaned_npcs() end
    elseif stage == "spawn" then
        local member = self.state.members[self.cursor]
        if not member then return self:_stage("initialize") end
        member.phase, member.spawnRequested = "requested", true
        self.state.mutationStarted = true
        if not self:_save("startup_spawn_intent") then return end
        local ok, handle = self.engine:spawn(self.scopes[self.cursor], member)
        if not ok then return self:halt(handle) end
        local identity = self.engine:startup_identity(member)
        member.instanceGuid, member.playerGuid = identity.instanceGuid, identity.playerGuid
        member.handleAddress = identity.handleAddress
        member.phase = "pending"
        self.runtime[self.cursor] = { handle = handle }
        self.state.spawned = self.state.spawned + 1
        if not self:_save("startup_spawn_returned") then return end
        self.cursor = self.cursor + 1
        return
    elseif stage == "initialize" or stage == "movement" or stage == "engagement" then
        local ready, arrived = 0, 0
        for index, member in ipairs(self.state.members) do
            local runtime = self.runtime[index]
            local plan = util.shallow_copy(member)
            plan.handle = runtime.handle
            local ok, observation = self.engine:inspect(runtime.handle, plan)
            if not ok then return self:halt(observation) end
            if not member.instanceGuid then
                local identity = self.engine:startup_identity(member)
                if identity.instanceGuid then
                    member.instanceGuid, member.playerGuid = identity.instanceGuid, identity.playerGuid
                    if not self:_save("startup_identity_assigned") then return end
                end
            end
            member.phase = observation.phase
            if observation.actor then runtime.actor = observation.actor end
            member.waitingOn = observation.waitingOn
            member.scopeReason = observation.scopeReason
            member.distanceFromBase, member.heightFromBase = observation.distanceFromBase, observation.heightFromBase
            if observation.location then member.lastLocation = util.shallow_copy(observation.location) end
            if observation.phase == "alive" then
                ready = ready + 1
                if not member.initialized then
                    member.initialized, member.healthBudget = true, observation.healthBudget
                    member.targetId = observation.targetId
                    runtime.initialLocation = util.shallow_copy(observation.location)
                    member.initialLocation = util.shallow_copy(observation.location)
                    self.state.initialized = self.state.initialized + 1
                    if not self:_save("startup_member_initialized") then return end
                end
                if stage == "movement" then
                    if not member.travelRequested then
                        member.travelRequested = true
                        if not self:_save("startup_movement_intent") then return end
                        local moved, reason = self.engine:startup_travel(self.scopes[index], plan)
                        if not moved then return self:halt(reason) end
                    end
                    local target = self.scopes[index].origin
                    if distance2(observation.location, runtime.initialLocation) >= 300 ^ 2
                        and distance2(observation.location, target) <= 1100 ^ 2 then
                        arrived = arrived + 1
                        if not member.arrived then
                            member.arrived = true
                            self.state.moved = self.state.moved + 1
                            if not self:_save("startup_movement_observed") then return end
                        end
                    end
                elseif stage == "engagement" and now >= (member.nextEngageAt or 0) then
                    member.nextEngageAt = now + 5
                    if not self:_save("startup_engagement_intent") then return end
                    local engaged, result = self.engine:engage(self.scopes[index],plan)
                    if not engaged then return self:halt(result) end
                    member.behavior = self.engine:startup_behavior(member)
                    if not self:_save("startup_engagement_returned") then return end
                    if result == "unavailable" then
                        self.state.failure = "engagement-unavailable"
                        return self:_stage("cleanup")
                    end
                end
            elseif observation.phase == "dead" or observation.phase == "captured" or observation.phase == "missing"
                or observation.phase == "escaped" then
                self.state.failure = "unexpected-member-" .. observation.phase
                return self:_stage("cleanup")
            end
        end
        if ready == #self.state.members then
            self.state.simultaneous = #self.state.members > 1
            if stage == "initialize" then return self:_stage(self.state.case == "spawn-cleanup" and "cleanup" or "movement") end
            if stage == "movement" and arrived == #self.state.members then
                return self:_stage(self.state.case == "engagement" and "engagement" or "cleanup")
            end
        end
        if stage == "engagement" then
            if self.damageOverflow then
                self.state.failure = "damage-observation-overflow"
                return self:_stage("cleanup")
            end
            if not self:_damage_witness() then return end
            if (self.state.dealtDamageEvents or 0) > 0 then return self:_stage("cleanup") end
        end
        if now >= self.state.stageStartedAt + 60 then
            self.state.failure = stage .. "-timeout"
            return self:_stage("cleanup")
        end
        return
    elseif stage == "cleanup" then
        for index, member in ipairs(self.state.members) do
            if not member.cleaned then
                local runtime = self.runtime[index]
                local plan = util.shallow_copy(member)
                plan.handle = runtime and runtime.handle
                local ok, outcome
                if member.cleanupRequested then
                    ok, outcome = self.engine:inspect(plan.handle, plan)
                    if ok then
                        outcome = outcome.phase
                        if outcome == "missing" then outcome = "despawned" end
                    end
                else
                    member.cleanupRequested = true
                    member.cleanupRequestedAt = now
                    if not self:_save("startup_cleanup_intent") then return end
                    ok, outcome = self.engine:despawn(self.scopes[index], plan)
                end
                if not ok then return self:halt(outcome) end
                if outcome == "despawned" or outcome == "captured" or outcome == "dead" or outcome == "missing" then
                    member.cleaned, member.phase = true, outcome
                    self.state.cleaned = self.state.cleaned + 1
                    if outcome ~= "despawned" then self.state.failure = self.state.failure or "cleanup-" .. outcome end
                    if not self:_save("startup_cleanup_completed") then return end
                elseif outcome ~= "pending" and outcome ~= "despawning" then
                    return self:halt("Startup test cleanup is unresolved")
                elseif now >= member.cleanupRequestedAt + 60 then
                    return self:halt("Custom assault despawn did not complete")
                end
            end
        end
        if self.state.cleaned == #self.state.members then
            return self:_cleaned_npcs()
        end
    else
        return self:halt("Startup test stage is invalid")
    end
end

function Test:tick()
    if self.stopped then return end
    local ok, reason = pcall(function() self:_tick() end)
    if not ok then self:halt(reason) end
end

function Test.attach(bridge, data_directory, options)
    options = options or {}
    local fs, getenv = options.filesystem or filesystem, options.getenv or os.getenv
    local run_id = getenv("PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN")
    local root = path.join(data_directory, "startup-tests")
    local pointer_path = path.join(root, "active.json")
    local active
    if fs.exists(pointer_path) then active = json.decode(assert(fs.read(pointer_path))) end
    if run_id == nil or run_id == "" then
        if active then
            assert(type(active.runId) == "string" and active.runId:match("^[a-z0-9%-]+$") and #active.runId <= 80,
                "Startup test pointer is invalid")
            local state = Test.read_state(path.join(root, active.runId), active.runId, bridge.logger, fs)
            if state then
                if state.mutationStarted and not state.cleanupComplete then
                    bridge.startup_quarantine = "An interrupted startup test retains uncertain owned entities; native starts are quarantined."
                end
            else
                bridge.startup_quarantine = "A startup test has no durable outcome; native starts are quarantined pending investigation."
            end
        end
        return
    end
    assert(getenv("COMPUTERNAME") == "IMOUTO" and bridge.delivery_profile == "laboratory-native-test"
        and bridge.config.mode == "laboratory" and bridge.config.capabilities.startAllInvasions == true,
        "Startup tests require the IMOUTO laboratory profile")
    assert(active and active.runId == run_id and run_id:match("^[a-z0-9%-]+$") and #run_id <= 80,
        "Startup test launch intent does not match")
    local directory = path.join(root, run_id)
    local plan = json.decode(assert(fs.read(path.join(directory, "plan.json"))))
    assert(plan.runId == run_id and plan.sourceRevision == getenv("PAL_EVENT_DIRECTOR_SOURCE_REVISION"),
        "Startup test plan provenance does not match the launcher")
    assert(plan.artifactSha256 == getenv("PAL_EVENT_DIRECTOR_ARTIFACT_SHA256"), "Startup test artifact does not match the launcher")
    if plan.previousRunId then
        assert(type(plan.previousRunId) == "string" and plan.previousRunId:match("^[a-z0-9%-]+$") and #plan.previousRunId <= 80,
            "Previous startup test identity is invalid")
        local previous = assert(Test.read_state(path.join(root, plan.previousRunId), plan.previousRunId, bridge.logger, fs),
            "Previous startup test has no durable outcome")
        assert(not previous.mutationStarted or previous.cleanupComplete, "Previous startup test retains uncertain entities")
        assert(previous.failedArtifactSha256 ~= plan.artifactSha256
            and not ((previous.status == "failed" or previous.status == "running") and previous.artifactSha256 == plan.artifactSha256),
            "Failed startup tests cannot repeat on the same artifact")
    end
    local store = Store.new(directory, bridge.logger, fs)
    bridge.startup_test = Test.new({ plan = plan, store = store, engine = bridge:_custom_engine(), logger = bridge.logger, clock = bridge.clock })
end

return Test
