local util = require("ped.util")
local json = require("ped.json")

local Rewards = {}
Rewards.__index = Rewards

local function new_state()
    return {
        schemaVersion = 1,
        obligations = {},
        order = json.array(),
    }
end

function Rewards.new(options, restored_state)
    options = options or {}
    local self = setmetatable({
        state = restored_state or new_state(),
        persist = options.persist or function() return true end,
        logger = options.logger,
    }, Rewards)
    for _, obligation in pairs(self.state.obligations) do
        if obligation.status == "granting" then
            obligation.status = "operator_review"
            obligation.lastError = "server restarted after grant intent but before verified result"
        end
    end
    return self
end

function Rewards:to_state()
    return self.state
end

function Rewards.make_key(spec)
    local identity = table.concat({
        tostring(spec.occurrence_id),
        tostring(spec.definition_id),
        tostring(spec.player_uid),
        tostring(spec.base_id or "global"),
        tostring(spec.rank or "none"),
        tostring(spec.reward_index or 1),
    }, "|")
    return "reward-" .. util.hash32(identity) .. "-" .. util.hash32(identity:reverse())
end

function Rewards:create(spec)
    assert(type(spec) == "table", "reward specification is required")
    assert(type(spec.occurrence_id) == "string", "occurrence_id is required")
    assert(type(spec.definition_id) == "string", "definition_id is required")
    assert(type(spec.player_uid) == "string", "player_uid is required")
    assert(type(spec.item_id) == "string", "item_id is required")
    assert(util.is_integer(spec.count) and spec.count > 0, "positive reward count is required")
    local key = Rewards.make_key(spec)
    if self.state.obligations[key] then
        return self.state.obligations[key], false
    end
    local obligation = {
        key = key,
        occurrenceId = spec.occurrence_id,
        definitionId = spec.definition_id,
        playerUid = spec.player_uid,
        baseId = spec.base_id,
        rank = spec.rank,
        rewardIndex = spec.reward_index or 1,
        itemId = spec.item_id,
        count = spec.count,
        status = "pending",
        attempts = 0,
        createdAtUtc = util.utc_now(),
    }
    self.state.obligations[key] = obligation
    self.state.order[#self.state.order + 1] = key
    local persisted, persist_error = self.persist("reward_obligation", obligation, true)
    if not persisted then
        self.state.obligations[key] = nil
        self.state.order[#self.state.order] = nil
        return nil, false, persist_error
    end
    return obligation, true
end

function Rewards:process(adapter, maximum, checkpoint)
    maximum = maximum or 8
    local processed = 0
    for _, key in ipairs(self.state.order) do
        if processed >= maximum then
            break
        end
        local obligation = self.state.obligations[key]
        if obligation and obligation.status == "pending" then
            local previous_attempts = obligation.attempts
            obligation.status = "granting"
            obligation.attempts = obligation.attempts + 1
            obligation.lastAttemptAtUtc = util.utc_now()
            local persisted, persist_error = self.persist("reward_grant_intent", obligation, true)
            if not persisted then
                obligation.status = "pending"
                obligation.attempts = previous_attempts
                obligation.lastAttemptAtUtc = nil
                obligation.lastError = "unable to persist grant intent: " .. tostring(persist_error)
                return processed, obligation.lastError
            end
            if checkpoint then
                local saved, save_error = checkpoint()
                if not saved then
                    obligation.status = "operator_review"
                    obligation.lastError = "grant intent journaled but granting checkpoint failed: " .. tostring(save_error)
                    return processed, obligation.lastError
                end
            end
            local ok, result = pcall(adapter.grant_item, adapter, obligation)
            if not ok then
                obligation.status = "operator_review"
                obligation.lastError = tostring(result)
            elseif result and result.status == "delivered" then
                obligation.status = "delivered"
                obligation.deliveredAtUtc = util.utc_now()
                obligation.beforeCount = result.before_count
                obligation.afterCount = result.after_count
                obligation.lastError = nil
            elseif result and result.status == "pending" then
                obligation.status = "pending"
                obligation.lastError = result.reason
            else
                obligation.status = "operator_review"
                obligation.lastError = result and result.reason or "unverified grant result"
            end
            local result_persisted, result_error = self.persist("reward_grant_result", obligation, true)
            if not result_persisted then
                obligation.status = "operator_review"
                obligation.lastError = "grant may have occurred but result was not journaled: " .. tostring(result_error)
                return processed, obligation.lastError
            end
            if checkpoint then
                local saved, save_error = checkpoint()
                if not saved then
                    obligation.status = "operator_review"
                    obligation.lastError = "grant result journaled but checkpoint failed: " .. tostring(save_error)
                    return processed, obligation.lastError
                end
            end
            processed = processed + 1
        end
    end
    return processed
end

function Rewards:summary()
    local summary = { pending = 0, granting = 0, delivered = 0, operator_review = 0 }
    for _, obligation in pairs(self.state.obligations) do
        summary[obligation.status] = (summary[obligation.status] or 0) + 1
    end
    return summary
end

return Rewards
