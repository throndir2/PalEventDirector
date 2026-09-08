local json = require("ped.json")
local path = require("ped.path")
local util = require("ped.util")
local filesystem = require("ped.filesystem")
local Store = require("ped.store")
local Diagnostic = require("ped.preflight_diagnostic")

local Test = {}
Test.__index = Test

local CASES = { ["spawn-cleanup"] = 1, movement = 1, ["two-base-movement"] = 2 }
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
    if state.cleanupComplete and state.mutationStarted then
        assert((state.status == "passed" or state.status == "blocked") and state.cleaned == state.spawned,
            "Startup test cleanup outcome is inconsistent")
    end
    return state
end

function Test.read_state(directory, run_id, logger, fs)
    local store = Store.new(directory, logger, fs)
    local last = store.records[#store.records]
    if not last or not last.state then return nil end
    return Test.validate_state(last.state, run_id)
end

function Test.new(options)
    local plan = assert(options.plan)
    assert(plan.schemaVersion == 1 and CASES[plan.case], "Startup test plan is invalid")
    assert(type(plan.runId) == "string" and plan.runId:match("^[a-z0-9%-]+$") and #plan.runId <= 80, "Startup test run identity is invalid")
    assert(type(plan.sourceRevision) == "string" and #plan.sourceRevision == 40 and plan.sourceRevision:match("^%x+$"), "Startup test source is invalid")
    assert(type(plan.artifactSha256) == "string" and #plan.artifactSha256 == 64 and plan.artifactSha256:match("^%x+$"), "Startup test artifact is invalid")
    local self = setmetatable({
        engine = assert(options.engine), store = assert(options.store), logger = assert(options.logger),
        clock = options.clock or util.now_seconds, runtime = {}, cursor = 1,
        state = { schemaVersion = 1, runId = plan.runId, case = plan.case, sourceRevision = plan.sourceRevision,
            artifactSha256 = plan.artifactSha256,
            status = "running", stage = "world", startedAt = (options.clock or util.now_seconds)(),
            mutationStarted = false, cleanupComplete = false, members = {},
            spawned = 0, initialized = 0, moved = 0, cleaned = 0, simultaneous = false },
    }, Test)
    assert(self.store.sequence == 0, "Startup test was already consumed; it cannot be replayed")
    self:_save("startup_test_started")
    return self
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
        self.scopes = result.scopes
        assert(type(self.scopes) == "table" and #self.scopes == CASES[self.state.case], "Startup test returned an invalid base count")
        self.state.availableBases = result.availableBases
        for index, scope in ipairs(self.scopes) do
            self.state.members[index] = { index = index, baseId = scope.baseId,
                groupId = "startup:" .. self.state.runId, slot = 1, characterId = "BOSS_Hunter_Rifle",
                level = 30, phase = "planned" }
        end
        return self:_stage("spawn")
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
    elseif stage == "initialize" or stage == "movement" then
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
            member.waitingOn = observation.waitingOn
            if observation.phase == "alive" then
                ready = ready + 1
                if not member.initialized then
                    member.initialized, member.healthBudget = true, observation.healthBudget
                    member.targetId = observation.targetId
                    runtime.initialLocation = util.shallow_copy(observation.location)
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
            if arrived == #self.state.members then return self:_stage("cleanup") end
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
                end
                break
            end
        end
        if self.state.cleaned == #self.state.members then
            return self:_finish(self.state.failure and "blocked" or "passed", self.state.failure or "complete")
        end
        if now >= self.state.stageStartedAt + 60 then return self:halt("Custom assault despawn did not complete") end
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
        assert(not ((previous.status == "failed" or previous.status == "running") and previous.artifactSha256 == plan.artifactSha256),
            "Failed startup tests cannot repeat on the same artifact")
    end
    local store = Store.new(directory, bridge.logger, fs)
    bridge.startup_test = Test.new({ plan = plan, store = store, engine = bridge:_custom_engine(), logger = bridge.logger, clock = bridge.clock })
end

return Test
