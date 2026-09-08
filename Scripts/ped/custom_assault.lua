local bounties = require("ped.bounties")
local util = require("ped.util")

local Assault = {}
Assault.__index = Assault

local DEFAULTS = {
    membersPerBase = 3,
    level = 30,
    spawnBatchSize = 8,
    pollBatchSize = 32,
    lifetimeSeconds = 900,
    initializationSeconds = 60,
    retargetSeconds = 5,
}
local PLAN_FIELDS = { "index", "baseId", "groupId", "slot", "characterId", "name", "level" }
local TERMINAL = { dead = true, captured = true, missing = true, despawned = true, cancelled = true }
local OBSERVED = {
    pending = true, alive = true, dead = true, capturing = true, captured = true, missing = true,
    escaped = true, despawning = true, inactive = true,
}

local function positive_integer(value)
    return type(value) == "number" and value > 0 and value < math.huge and util.is_integer(value)
end

local function copy_plan(member)
    local result = {}
    for _, key in ipairs(PLAN_FIELDS) do result[key] = member.plan[key] end
    return result
end

local function copy_guid(value, allow_zero)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local result, nonzero, count = {}, false, 0
    for key, part in pairs(value) do
        if key ~= "A" and key ~= "B" and key ~= "C" and key ~= "D" then return nil end
        if type(part) ~= "number" or not util.is_integer(part)
            or part < -2147483648 or part > 4294967295 then return nil end
        result[key], count = part, count + 1
        nonzero = nonzero or part ~= 0
    end
    if count ~= 4 or (not allow_zero and not nonzero) then return nil end
    return result
end

local function same_guid(left, right)
    return left.A == right.A and left.B == right.B and left.C == right.C and left.D == right.D
end

local function evidence(member)
    local result = copy_plan(member)
    result.targetId, result.healthBudget = member.targetId, member.healthBudget
    result.instanceGuid = member.instanceGuid and copy_guid(member.instanceGuid) or nil
    result.playerGuid = member.playerGuid and copy_guid(member.playerGuid, true) or nil
    return result
end

local function failure_text(label, detail)
    local text = "custom assault " .. label .. " failed"
    if type(detail) == "string" and detail ~= "" then
        text = text .. ": " .. util.sanitize_text(detail, 240)
    end
    return text
end

function Assault.new(options)
    options = options or {}
    local config = {}
    for key, default in pairs(DEFAULTS) do
        local value = options.config and options.config[key]
        if value == nil then value = default end
        assert(positive_integer(value), "custom assault " .. key .. " must be a positive integer")
        config[key] = value
    end
    assert(positive_integer(options.maxTargets), "custom assault maxTargets must be a positive integer")
    local engine, callbacks = assert(options.engine, "custom assault engine is required"),
        assert(options.callbacks, "custom assault callbacks are required")
    for _, name in ipairs({ "spawn", "inspect", "engage", "despawn", "actorKey", "sameActor" }) do
        assert(type(engine[name]) == "function", "custom assault engine." .. name .. " is required")
    end
    for _, name in ipairs({ "record", "composition", "started", "finished", "retired", "progress" }) do
        assert(type(callbacks[name]) == "function", "custom assault callbacks." .. name .. " is required")
    end
    return setmetatable({
        config = config, maxTargets = options.maxTargets, engine = engine, callbacks = callbacks,
        clock = options.clock or util.now_seconds, logger = options.logger,
        members = {}, bases = {}, requested = {}, targets = {}, spawnCursor = 1, pollCursor = 1, closed = false,
    }, Assault)
end

function Assault:_halt(reason)
    self.failure = self.failure or reason
    return false, self.failure
end

-- Latch before crossing the adapter/callback boundary, so an uncaught exception
-- also prevents a later tick from repeating an operation whose outcome is unknown.
function Assault:_invoke(label, callback, mode, allow_halted, ...)
    local previous = self.failure
    if previous and not allow_halted then return false, previous end
    self.failure = previous or ("custom assault interrupted during " .. label .. "; recovery required")
    local first, second = callback(...)
    if (mode == "required" and first ~= true) or (mode == "optional" and first == false) then
        local reason = failure_text(label, second)
        self.failure = previous and util.sanitize_text(reason .. "; previous: " .. previous, 512) or reason
        return false, self.failure
    end
    self.failure = previous
    return true, first, second
end

function Assault:_record(kind, data, allow_halted)
    return self:_invoke("journal " .. kind, self.callbacks.record, "required", allow_halted, kind, data)
end

function Assault:_callback(name, mode, allow_halted, ...)
    return self:_invoke("callback " .. name, self.callbacks[name], mode, allow_halted, ...)
end

function Assault:_engine(name, ...)
    local ok, first, second = self:_invoke(name, self.engine[name], "required", false, self.engine, ...)
    if not ok then return false, first end
    return true, second
end

function Assault:_identity(name, ...)
    local ok, value = self:_invoke(name, self.engine[name], "value", false, self.engine, ...)
    if not ok then return false, value end
    if name == "sameActor" and type(value) ~= "boolean" then
        return self:_halt("custom assault actor comparison returned invalid evidence")
    end
    if name == "actorKey" and value ~= nil and (type(value) ~= "string" or value == "") then
        return self:_halt("custom assault actor key returned invalid evidence")
    end
    return true, value
end

function Assault:_now()
    local ok, value = self:_invoke("clock", self.clock, "value", false)
    if not ok then return nil, value end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        self:_halt("custom assault clock returned an invalid time")
        return nil, self.failure
    end
    return value
end

function Assault:_engine_plan(member)
    local plan = evidence(member)
    plan.handle, plan.actor = member.handle, member.actor
    return plan
end

function Assault:_counts(base)
    local alive, pending = 0, 0
    for _, member in ipairs(base.members) do
        if member.phase == "alive" then alive = alive + 1
        elseif not TERMINAL[member.phase] then pending = pending + 1 end
    end
    return alive, pending
end

function Assault:_progress(base, allow_halted)
    local alive, pending = self:_counts(base)
    local phase = base.failed and "failed" or (base.started and "active" or "spawning")
    if alive + pending == 0 then phase = (base.failed or not base.started) and "failed" or "completed" end
    local signature = phase .. ":" .. alive .. ":" .. pending
    if base.progress == signature then return true end
    base.progress = signature
    return self:_callback("progress", "optional", allow_halted, base.id, phase, alive, pending)
end

function Assault:_unrank(base, reason, allow_halted)
    if base.failed then return true end
    base.failed, base.failureReason = true, reason
    return self:_callback("composition", "required", allow_halted,
        base.id, util.shallow_copy(base.assignments), reason)
end

function Assault:_fail_member(member, reason)
    self:_halt(reason)
    if self.planDurable then
        local ok = self:_unrank(member.base, self.failure, true)
        if ok then self:_progress(member.base, true) end
    end
    return false, self.failure
end

function Assault:_refresh(base)
    local alive, pending = self:_counts(base)
    if alive + pending == 0 and base.started and not base.finishAttempted then
        base.finishAttempted = true
        local outcome = base.endOutcome or (base.failed and "cancelled" or "completed")
        local ok, err = self:_callback("finished", "required", false, base.id, base.groupId, outcome)
        if not ok then return false, err end
        base.finished = true
    end
    return self:_progress(base)
end

function Assault:start(targets, profile_id, occurrence_id)
    if self.startAttempted or self.closing then return false, "custom assault start was already consumed" end
    self.startAttempted = true
    if bounties.normalize_profile_id(profile_id) ~= "all-bounty" then
        return false, "custom assault requires the all-bounty profile"
    end
    if type(occurrence_id) ~= "string" or occurrence_id == "" then
        return false, "custom assault requires an occurrence identity"
    end
    if type(targets) ~= "table" then return false, "custom assault targets must be an ordered array" end
    local count = 0
    for key in pairs(targets) do
        if not positive_integer(key) then return false, "custom assault targets must be an ordered array" end
        count = count + 1
    end
    if count == 0 then return false, "custom assault has no eligible bases" end
    if count > math.floor(self.maxTargets / self.config.membersPerBase) then
        return false, "custom assault exceeds maxTargets"
    end
    local seen = {}
    for ordinal = 1, count do
        local target = targets[ordinal]
        if type(target) ~= "table" or type(target.id) ~= "string" or target.id == "" or target.scope == nil then
            return false, "custom assault target is incomplete"
        end
        if seen[target.id] then return false, "custom assault targets contain a duplicate base" end
        seen[target.id] = true
    end
    local now, err = self:_now()
    if not now then return false, err end
    self.expiresAt = now + self.config.lifetimeSeconds
    local selector, plans = bounties.new_selector("all-bounty", occurrence_id), {}
    for ordinal = 1, count do
        local target = targets[ordinal]
        self.bases[ordinal] = {
            id = target.id, scope = target.scope, members = {}, assignments = {},
            groupId = "ped-custom:" .. #occurrence_id .. ":" .. occurrence_id .. ":" .. ordinal,
        }
    end
    for slot = 1, self.config.membersPerBase do
        for _, base in ipairs(self.bases) do
            local bounty = assert(bounties.next(selector), "custom assault bounty catalog is empty")
            local member = { base = base, phase = "queued", plan = {
                index = #self.members + 1, baseId = base.id, groupId = base.groupId, slot = slot,
                characterId = bounty.id, name = bounty.name, level = self.config.level,
            } }
            self.members[#self.members + 1], base.members[#base.members + 1] = member, member
            base.assignments[#base.assignments + 1] = bounty.id
            plans[#plans + 1] = copy_plan(member)
        end
    end
    local ok
    ok, err = self:_record("custom_assault_plan", { members = plans })
    if not ok then return false, err end
    self.planDurable = true
    for _, base in ipairs(self.bases) do
        ok, err = self:_callback("composition", "required", false,
            base.id, util.shallow_copy(base.assignments), nil)
        if not ok then return false, err end
    end
    for _, base in ipairs(self.bases) do
        ok, err = self:_progress(base)
        if not ok then return false, err end
    end
    return true, { status = "spawning", baseCount = count, memberCount = #self.members }
end

function Assault:_read_member(member)
    local ok, state = self:_engine("inspect", member.handle, self:_engine_plan(member))
    if not ok then return self:_fail_member(member, state) end
    if type(state) ~= "table" or not OBSERVED[state.phase] then
        return self:_fail_member(member, "custom assault inspection returned an invalid phase")
    end
    if state.phase == "despawning" and not member.cleanupRequested then
        return self:_fail_member(member, "custom assault observed despawning without a cleanup request; recovery required")
    end
    if state.characterId ~= nil and state.characterId ~= member.plan.characterId then
        return self:_fail_member(member, "custom assault member character identity changed")
    end
    local guid
    if state.instanceGuid ~= nil then
        guid = copy_guid(state.instanceGuid)
        if not guid then return self:_fail_member(member, "custom assault instance identity is invalid") end
    end
    if member.initialized then
        if (state.targetId ~= nil and state.targetId ~= member.targetId)
            or (guid and not same_guid(guid, member.instanceGuid)) then
            return self:_fail_member(member, "custom assault member instance identity changed")
        end
        if state.actor ~= nil then
            local same
            ok, same = self:_identity("sameActor", member.actor, state.actor)
            if not ok then return self:_fail_member(member, same) end
            if not same then return self:_fail_member(member, "custom assault member actor identity changed") end
        end
    end
    if state.phase == "captured" or state.phase == "missing" then return true, state.phase, state end
    local player_guid
    if state.playerGuid ~= nil then
        player_guid = copy_guid(state.playerGuid, true)
        if not player_guid then return self:_fail_member(member, "custom assault player identity is invalid") end
    end
    if member.playerGuid then
        if player_guid and not same_guid(player_guid, member.playerGuid) then
            return self:_fail_member(member, "custom assault member player identity changed")
        end
        if not player_guid and state.phase ~= "capturing" and state.phase ~= "inactive" and state.phase ~= "pending"
            and state.phase ~= "despawning" and not (member.cleanupRequested and state.phase == "dead") then
            return self:_fail_member(member, "custom assault initialized member lost player identity evidence")
        end
    end
    if member.initialized and state.phase == "dead" and state.targetId == member.targetId
        and state.characterId == member.plan.characterId and guid then
        return true, "dead", state
    end
    if member.cleanupRequested then
        if state.phase == "pending" or state.phase == "despawning" then return true, "despawning", state end
        if state.phase == "dead" then return true, state.phase, state end
    end
    if state.phase == "pending" or state.actor == nil or state.targetId == nil
        or state.characterId == nil or state.healthBudget == nil or guid == nil then
        if state.phase == "capturing" or state.phase == "inactive" then
            if not TERMINAL[member.phase] then member.phase = state.phase end
            return true, state.phase, state
        end
        if member.initialized or state.phase == "escaped" then
            return self:_fail_member(member, "custom assault initialized member lost ownership evidence")
        end
        return true, state.phase == "dead" and "dead" or "pending", state
    end
    if type(state.targetId) ~= "string" or state.targetId == "" or not positive_integer(state.healthBudget) then
        return self:_fail_member(member, "custom assault initialized member has invalid target or health evidence")
    end
    local key
    ok, key = self:_identity("actorKey", state.actor)
    if not ok then return self:_fail_member(member, key) end
    if key == nil and not member.initialized then
        if state.phase == "escaped" then
            return self:_fail_member(member, "custom assault escaped member lacks valid actor evidence")
        end
        if state.phase == "capturing" or state.phase == "inactive" then
            member.phase = state.phase
            return true, state.phase, state
        end
        return true, state.phase == "dead" and "dead" or "pending", state
    end
    if key ~= state.targetId then
        return self:_fail_member(member, "custom assault actor and target identities disagree")
    end
    if not member.initialized then
        if self.targets[key] then return self:_fail_member(member, "custom assault target identity was reused") end
        member.actor, member.targetId = state.actor, key
        member.healthBudget, member.instanceGuid = state.healthBudget, guid
        member.playerGuid = player_guid
        local initialized = evidence(member)
        ok, key = self:_record("custom_member_initialized", initialized)
        if not ok then return self:_fail_member(member, key) end
        member.initialized, self.targets[member.targetId] = true, member
    elseif player_guid and not member.playerGuid then
        member.playerGuid = player_guid
        ok, key = self:_record("custom_member_identity_completed", evidence(member))
        if not ok then return self:_fail_member(member, key) end
    end
    if not TERMINAL[member.phase] then
        if state.phase == "capturing" or state.phase == "inactive" then member.phase = state.phase
        elseif state.phase == "escaped" then member.phase, member.escaped = "escaped", true end
    end
    return true, state.phase, state
end

function Assault:_engage(member, state, now)
    if member.lastEngagedAt and now < member.lastEngagedAt + self.config.retargetSeconds then
        member.phase = "alive"
        return true
    end
    local intent = evidence(member)
    intent.reason = member.engaged and "retarget" or "initial"
    local ok, err = self:_record("custom_engage_intent", intent)
    if not ok then return self:_fail_member(member, err) end
    local outcome
    ok, outcome = self:_engine("engage", member.base.scope, self:_engine_plan(member), state)
    if not ok then return self:_fail_member(member, outcome) end
    if outcome == "unavailable" then
        intent.reason = "engagement_unavailable"
        ok, err = self:_record("custom_engage_unavailable", intent)
        if not ok then return self:_fail_member(member, err) end
        return self:_cleanup_member(member, "alive", "engagement_unavailable", now)
    end
    if outcome ~= nil and outcome ~= true then return self:_fail_member(member, "custom assault engagement returned an invalid outcome") end
    member.engaged, member.lastEngagedAt, member.phase = true, now, "alive"
    local base = member.base
    if not base.startAttempted then
        base.startAttempted = true
        ok, err = self:_callback("started", "required", false, base.id, base.groupId)
        if not ok then return self:_fail_member(member, err) end
        base.started = true
    end
    return true
end

function Assault:_retire(member, phase, reason)
    if TERMINAL[member.phase] then return true end
    local data = evidence(member)
    data.phase, data.reason, data.engaged = phase, reason, member.engaged == true
    local ok, err = self:_record("custom_member_retired", data)
    if not ok then return self:_fail_member(member, err) end
    member.phase = phase
    if member.targetId then
        ok, err = self:_callback("retired", "optional", false, member.targetId, reason)
        if not ok then return self:_fail_member(member, err) end
    end
    if phase ~= "dead" or not member.engaged or reason == "escaped" or member.cleanupRequested then
        ok, err = self:_unrank(member.base, "custom assault member retired: " .. reason)
        if not ok then return false, err end
    end
    return self:_refresh(member.base)
end

function Assault:_block_cleanup(member, reason)
    local data = evidence(member)
    data.phase, data.reason, data.error = "capturing", reason, "capture_in_progress"
    data.cleanupRequestedAt = member.cleanupRequestedAt
    local ok, err = self:_record("custom_cleanup_blocked", data)
    if not ok then return self:_fail_member(member, err) end
    return self:_fail_member(member,
        "custom assault capture is in progress; cleanup blocked and handle retained; recovery required")
end

function Assault:_check_cleanup_deadlines(now)
    for _, member in ipairs(self.requested) do
        if member.cleanupRequested and not TERMINAL[member.phase]
            and now >= member.cleanupRequestedAt + self.config.initializationSeconds then
            local data = evidence(member)
            data.phase, data.reason = member.phase, "cleanup_confirmation_timeout"
            data.cleanupReason, data.cleanupRequestedAt = member.cleanupReason, member.cleanupRequestedAt
            local ok, err = self:_record("custom_cleanup_timeout", data)
            if not ok then return self:_fail_member(member, err) end
            return self:_fail_member(member,
                "custom assault cleanup confirmation timed out; handle retained; recovery required")
        end
    end
    return true
end

function Assault:_observe_cleanup(member, phase)
    if phase == "capturing" then return self:_block_cleanup(member, member.cleanupReason) end
    if phase == "missing" or phase == "dead" or phase == "captured" then
        local outcome = phase == "missing" and "despawned" or phase
        local data = evidence(member)
        data.outcome, data.observedPhase, data.reason = outcome, phase, member.cleanupReason
        data.cleanupRequestedAt = member.cleanupRequestedAt
        local ok, err = self:_record("custom_cleanup_completed", data)
        if not ok then return self:_fail_member(member, err) end
        return self:_retire(member, outcome, member.escaped and "escaped" or outcome)
    end
    member.phase = "despawning"
    return self:_refresh(member.base)
end

function Assault:_cleanup_member(member, phase, reason, now)
    if member.cleanupRequested then return self:_observe_cleanup(member, phase) end
    if phase == "capturing" then return self:_block_cleanup(member, reason) end
    local data = evidence(member)
    data.phase, data.reason, data.cleanupRequestedAt = phase, reason, now
    local ok, err = self:_record("custom_cleanup_intent", data)
    if not ok then return self:_fail_member(member, err) end
    -- Consume dispatch before entering native code; pending cleanup is inspection-only.
    member.cleanupRequested, member.cleanupRequestedAt, member.cleanupReason = true, now, reason
    local outcome
    ok, outcome = self:_engine("despawn", member.base.scope, self:_engine_plan(member))
    if not ok then return self:_fail_member(member, outcome) end
    if outcome ~= "despawned" and outcome ~= "captured" and outcome ~= "dead" and outcome ~= "missing"
        and outcome ~= "pending" then
        return self:_fail_member(member, "custom assault cleanup returned an invalid outcome")
    end
    local returned = evidence(member)
    returned.outcome, returned.reason = outcome, reason
    returned.cleanupRequestedAt = now
    ok, err = self:_record("custom_cleanup_returned", returned)
    if not ok then return self:_fail_member(member, err) end
    if outcome == "pending" then
        member.phase = "despawning"
        return self:_refresh(member.base)
    end
    if outcome == "missing" then outcome = "despawned" end
    return self:_retire(member, outcome, member.escaped and "escaped" or outcome)
end

function Assault:_spawn(member, now)
    local ok, err = self:_record("custom_spawn_intent", copy_plan(member))
    if not ok then return self:_fail_member(member, err) end
    member.phase, member.requestedAt, member.spawnRequested = "pending", now, true
    self.requested[#self.requested + 1] = member
    local handle
    ok, handle = self:_engine("spawn", member.base.scope, self:_engine_plan(member))
    if not ok then return self:_fail_member(member, handle) end
    member.handle = handle
    if handle == nil or handle == false then
        return self:_fail_member(member, "custom assault spawn returned no handle; recovery required")
    end
    ok, err = self:_record("custom_spawn_returned", {
        index = member.plan.index, baseId = member.plan.baseId, status = "pending",
    })
    if not ok then return self:_fail_member(member, err) end
    return true
end

function Assault:poll()
    if self.failure then return false, self.failure end
    if self.closed then return true end
    if not self.planDurable then return false, "custom assault has no durable plan" end
    if self.closing then return self:_close(self.closeReason, self.config.pollBatchSize) end
    local now, err = self:_now()
    if not now then return false, err end
    if now >= self.expiresAt then return self:_close("timeout", self.config.pollBatchSize, now) end
    local valid
    valid, err = self:_check_cleanup_deadlines(now)
    if not valid then return false, err end
    for _, member in ipairs(self.requested) do
        if not TERMINAL[member.phase] and not member.initialized and not member.cleanupRequested
            and now >= member.requestedAt + self.config.initializationSeconds then
            local data = evidence(member)
            data.reason = "initialization_timeout"
            local ok
            ok, err = self:_record("custom_member_initialization_timeout", data)
            if not ok then return self:_fail_member(member, err) end
            return self:_fail_member(member, "custom assault initialization timed out; owned handle retained for recovery")
        end
    end
    local spawned = 0
    while self.spawnCursor <= #self.members and spawned < self.config.spawnBatchSize do
        local member = self.members[self.spawnCursor]
        self.spawnCursor, spawned = self.spawnCursor + 1, spawned + 1
        local ok
        ok, err = self:_spawn(member, now)
        if not ok then return false, err end
    end
    local checked, visited, count = 0, 0, #self.requested
    while visited < count and checked < self.config.pollBatchSize do
        local member = self.requested[self.pollCursor]
        self.pollCursor, visited = (self.pollCursor % count) + 1, visited + 1
        if not TERMINAL[member.phase] then
            checked = checked + 1
            local ok, phase, state = self:_read_member(member)
            if not ok then return false, phase end
            if member.cleanupRequested then
                ok, err = self:_observe_cleanup(member, phase)
            elseif phase == "capturing" then
                ok, err = self:_refresh(member.base)
            elseif phase == "escaped" or ((phase == "alive" or phase == "inactive") and member.escaped) then
                ok, err = self:_cleanup_member(member, phase, "escaped", now)
            elseif phase == "alive" then
                ok, err = self:_engage(member, state, now)
                if ok then ok, err = self:_refresh(member.base) end
            elseif phase == "pending" or phase == "inactive" then
                ok, err = self:_refresh(member.base)
            else
                ok, err = self:_retire(member, phase, member.escaped and "escaped" or phase)
            end
            if not ok then return false, err end
        end
    end
    return true
end

function Assault:target(actor)
    if self.failure then return nil, self.failure end
    if not self.planDurable then return nil, "custom assault has no durable plan" end
    local ok, key = self:_identity("actorKey", actor)
    if not ok then return nil, key end
    local member = key and self.targets[key]
    if not member then return nil, "actor is not a custom assault member" end
    if member.cleanupRequested or (TERMINAL[member.phase] and member.phase ~= "dead")
        or (self.closing and member.phase ~= "dead") then
        return nil, "custom assault member is no longer eligible"
    end
    local same
    ok, same = self:_identity("sameActor", member.actor, actor)
    if not ok then return nil, same end
    if not same then return nil, "actor is not the tracked custom assault actor" end
    local phase
    ok, phase = self:_read_member(member)
    if not ok then return nil, phase end
    if phase == "captured" or phase == "missing" then
        local retired, err = self:_retire(member, phase, member.escaped and "escaped" or phase)
        if not retired then return nil, err end
    end
    if phase == "capturing" then return nil, "custom assault member is capturing" end
    if phase == "escaped" or member.escaped then return nil, "custom assault member escaped its base envelope" end
    if phase ~= "alive" and phase ~= "dead" then return nil, "custom assault member is " .. phase end
    if member.phase == "dead" and phase ~= "dead" then return nil, "custom assault member was already retired" end
    -- The actual death hook must receive its context before polling can finish
    -- the base or retire the score target.
    return {
        target_id = member.targetId, base_id = member.plan.baseId, group_id = member.plan.groupId,
        health_budget = member.healthBudget, target_name = member.plan.name,
    }
end

function Assault:_close(reason, inspect_limit, now)
    if self.closed then return not self.failure, self.failure end
    self.closing = true
    if not self.cleanupIntentAttempted then
        self.cleanupIntentAttempted = true
        self.closeReason = type(reason) == "string" and util.sanitize_text(reason, 240) or "cancelled"
        local members = {}
        for _, member in ipairs(self.members) do
            local data = evidence(member)
            data.phase, data.spawnRequested = member.phase, member.spawnRequested == true
            data.cleanupRequested = member.cleanupRequested == true
            data.cleanupRequestedAt, data.cleanupReason = member.cleanupRequestedAt, member.cleanupReason
            members[#members + 1] = data
        end
        local ok, err = self:_record("custom_assault_cleanup_intent",
            { reason = self.closeReason, members = members }, true)
        if not ok then return false, err end
    end
    if self.failure then return false, self.failure end
    local err
    if now == nil then now, err = self:_now() end
    if not now then return false, err end
    local valid
    valid, err = self:_check_cleanup_deadlines(now)
    if not valid then return false, err end
    for _, base in ipairs(self.bases) do
        base.endOutcome = self.closeReason == "timeout" and "timeout" or "cancelled"
    end
    local inspected, visited, count = 0, 0, #self.members
    self.cleanupCursor = self.cleanupCursor or 1
    while visited < count do
        local member = self.members[self.cleanupCursor]
        if not TERMINAL[member.phase] and member.spawnRequested and inspected >= inspect_limit then break end
        self.cleanupCursor, visited = (self.cleanupCursor % count) + 1, visited + 1
        if not TERMINAL[member.phase] then
            local ok, err
            if not member.spawnRequested then
                ok, err = self:_retire(member, "cancelled", self.closeReason)
            else
                inspected = inspected + 1
                local phase
                ok, phase = self:_read_member(member)
                if not ok then return false, phase end
                if member.cleanupRequested then
                    ok, err = self:_observe_cleanup(member, phase)
                elseif TERMINAL[phase] then
                    ok, err = self:_retire(member, phase, member.escaped and "escaped" or phase)
                else
                    ok, err = self:_cleanup_member(member, phase, member.escaped and "escaped" or self.closeReason, now)
                end
            end
            if not ok then return false, err end
        end
    end
    if self:has_live_members() then return true end
    local ok
    ok, err = self:_record("custom_assault_closed", { reason = self.closeReason, memberCount = #self.members })
    if not ok then return false, err end
    self.closed = true
    return true
end

function Assault:close(reason)
    return self:_close(reason, self.maxTargets)
end

function Assault:has_live_members()
    for _, member in ipairs(self.members) do
        if not TERMINAL[member.phase] then return true end
    end
    return false
end

return Assault
