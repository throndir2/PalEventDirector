local util = require("ped.util")

local Scoreboard = {}
Scoreboard.__index = Scoreboard

local MICRO = 1000000
local MAX_HEALTH_BUDGET = 2000000000

local function mul_div_floor(left, right, divisor)
    if left < 0 or right < 0 or divisor <= 0 or right > divisor then
        error("invalid bounded multiplication")
    end
    local quotient = math.floor(left / divisor)
    local remainder = left % divisor
    return quotient * right + math.floor((remainder * right) / divisor)
end

local function new_state(options)
    return {
        schemaVersion = 1,
        occurrenceId = assert(options.occurrence_id),
        targetPointMicro = assert(options.target_points) * MICRO,
        seed = options.seed or util.hash32(options.occurrence_id),
        targets = {},
        players = {},
        lastRecordSequence = 0,
        damageRecordCount = 0,
        rejectedRecordCount = 0,
    }
end

function Scoreboard.new(options, restored_state)
    options = options or {}
    local state = restored_state or new_state(options)
    return setmetatable({
        state = state,
        max_targets = options.max_targets or 512,
        max_players = options.max_players or 128,
        max_damage_records = options.max_damage_records or 100000,
        qualification_percent = options.qualification_percent or 5,
        require_enrollment = options.require_enrollment == true,
    }, Scoreboard)
end

function Scoreboard:to_state()
    return self.state
end

function Scoreboard:_reject(reason)
    self.state.rejectedRecordCount = self.state.rejectedRecordCount + 1
    return false, reason
end

function Scoreboard:_ensure_target(input)
    local target = self.state.targets[input.target_id]
    if target then
        if target.baseId ~= input.base_id or target.healthBudget ~= input.health_budget then
            target.ranked = false
            target.unrankedReason = "target_identity_or_health_mismatch"
            return target, false, target.unrankedReason
        end
        return target, false
    end
    if util.count(self.state.targets) >= self.max_targets then
        return nil, false, "target_limit"
    end
    if not util.is_integer(input.health_budget) or input.health_budget < 1 or input.health_budget > MAX_HEALTH_BUDGET then
        return nil, false, "invalid_health_budget"
    end
    target = {
        id = input.target_id,
        baseId = input.base_id,
        healthBudget = input.health_budget,
        pointMicro = input.point_micro or self.state.targetPointMicro,
        consumedDamage = 0,
        uncreditedDamage = 0,
        contributors = {},
        ranked = true,
        closed = false,
        finalHitPlayerUid = nil,
    }
    self.state.targets[input.target_id] = target
    return target, true
end

function Scoreboard:_ensure_player(uid, display_name)
    local player = self.state.players[uid]
    if player then
        if display_name and display_name ~= "" then
            player.displayName = display_name
        end
        return player
    end
    if util.count(self.state.players) >= self.max_players then
        return nil, "player_limit"
    end
    player = {
        uid = uid,
        displayName = display_name or util.mask_uid(uid),
        acceptedDamage = 0,
        directDamage = 0,
        palDamage = 0,
        finalHits = 0,
        bases = {},
    }
    self.state.players[uid] = player
    return player
end

function Scoreboard:enroll_player(uid, display_name, joined_at)
    if type(uid) ~= "string" or uid == "" then
        return false, "invalid_player_uid"
    end
    local player, player_error = self:_ensure_player(uid, display_name)
    if not player then
        return false, player_error
    end
    player.enrolledAt = player.enrolledAt or joined_at
    player.lastSeenAt = joined_at or player.lastSeenAt
    return true, player
end

local function source_is_eligible(input)
    return input.source_kind == "direct_player" or input.source_kind == "active_pal" or input.source_kind == "base_worker"
end

function Scoreboard:record_damage(input)
    if type(input) ~= "table" or not util.is_integer(input.record_sequence) or input.record_sequence < 1 then
        return self:_reject("invalid_record_sequence")
    end
    if input.record_sequence <= self.state.lastRecordSequence then
        return false, "duplicate"
    end
    if self.state.damageRecordCount >= self.max_damage_records then
        return self:_reject("damage_record_limit")
    end
    if type(input.target_id) ~= "string" or input.target_id == "" or type(input.base_id) ~= "string" or input.base_id == "" then
        return self:_reject("invalid_target")
    end
    if not util.is_integer(input.actual_damage) or input.actual_damage < 0 then
        return self:_reject("invalid_damage")
    end

    self.state.lastRecordSequence = input.record_sequence
    self.state.damageRecordCount = self.state.damageRecordCount + 1
    local target, _, target_error = self:_ensure_target(input)
    if not target then
        return self:_reject(target_error)
    end
    if target.closed then
        return self:_reject("target_closed")
    end

    local remaining = math.max(0, target.healthBudget - target.consumedDamage)
    local consumed = math.min(input.actual_damage, remaining)
    target.consumedDamage = target.consumedDamage + consumed
    if consumed == 0 then
        return true, { consumed = 0, credited = 0 }
    end

    local eligible = source_is_eligible(input) and type(input.player_uid) == "string" and input.player_uid ~= ""
    if not eligible then
        target.uncreditedDamage = target.uncreditedDamage + consumed
        return true, { consumed = consumed, credited = 0 }
    end

    local player = self.state.players[input.player_uid]
    local player_error
    if not player and self.require_enrollment then
        target.uncreditedDamage = target.uncreditedDamage + consumed
        return true, { consumed = consumed, credited = 0, reason = "player_not_enrolled" }
    end
    player, player_error = self:_ensure_player(input.player_uid, input.player_name)
    if not player then
        target.uncreditedDamage = target.uncreditedDamage + consumed
        return self:_reject(player_error)
    end
    local contributor = target.contributors[input.player_uid]
    if not contributor then
        contributor = { damage = 0, directDamage = 0, palDamage = 0 }
        target.contributors[input.player_uid] = contributor
    end
    contributor.damage = contributor.damage + consumed
    player.acceptedDamage = player.acceptedDamage + consumed
    player.bases[input.base_id] = true
    if input.source_kind == "direct_player" then
        contributor.directDamage = contributor.directDamage + consumed
        player.directDamage = player.directDamage + consumed
    else
        contributor.palDamage = contributor.palDamage + consumed
        player.palDamage = player.palDamage + consumed
    end
    return true, { consumed = consumed, credited = consumed }
end

function Scoreboard:mark_unranked(target_id, reason)
    local target = self.state.targets[target_id]
    if not target then
        return false, "target_not_found"
    end
    target.ranked = false
    target.unrankedReason = reason or "adapter_rejected"
    return true
end

function Scoreboard:unrank_base(base_id, reason)
    local changed = 0
    for _, target in pairs(self.state.targets) do
        if target.baseId == base_id and target.ranked then
            target.ranked = false
            target.unrankedReason = reason or "base_unranked"
            changed = changed + 1
        end
    end
    return changed
end

function Scoreboard:close_target(input)
    local target = self.state.targets[input.target_id]
    if not target then
        return false, "target_not_found"
    end
    if target.closed then
        return false, "already_closed"
    end
    target.closed = true
    target.closedReason = input.reason or "defeated"
    if target.ranked and source_is_eligible(input) and input.player_uid and target.contributors[input.player_uid] then
        target.finalHitPlayerUid = input.player_uid
        local player = self.state.players[input.player_uid]
        if player then
            player.finalHits = player.finalHits + 1
        end
    end
    return true
end

function Scoreboard:_player_result(uid, player)
    local result = {
        uid = uid,
        displayName = player.displayName,
        scoreMicro = 0,
        acceptedDamage = player.acceptedDamage,
        directDamage = player.directDamage,
        palDamage = player.palDamage,
        finalHits = 0,
        qualifiedTargets = 0,
        basesDefended = util.count(player.bases),
        baseScoreMicro = {},
        tieValue = tonumber(util.hash32(self.state.seed .. ":" .. uid), 16),
    }
    for _, target in pairs(self.state.targets) do
        if target.ranked then
            if target.finalHitPlayerUid == uid then
                result.finalHits = result.finalHits + 1
            end
            local contributor = target.contributors[uid]
            if contributor then
                local points = mul_div_floor(target.pointMicro, contributor.damage, target.healthBudget)
                result.scoreMicro = result.scoreMicro + points
                result.baseScoreMicro[target.baseId] = (result.baseScoreMicro[target.baseId] or 0) + points
                if contributor.damage * 100 >= target.healthBudget * self.qualification_percent then
                    result.qualifiedTargets = result.qualifiedTargets + 1
                end
            end
        end
    end
    result.score = result.scoreMicro / MICRO
    return result
end

function Scoreboard:rankings(limit)
    local results = {}
    for uid, player in pairs(self.state.players) do
        results[#results + 1] = self:_player_result(uid, player)
    end
    table.sort(results, function(left, right)
        if left.scoreMicro ~= right.scoreMicro then
            return left.scoreMicro > right.scoreMicro
        end
        if left.finalHits ~= right.finalHits then
            return left.finalHits > right.finalHits
        end
        if left.qualifiedTargets ~= right.qualifiedTargets then
            return left.qualifiedTargets > right.qualifiedTargets
        end
        if left.tieValue ~= right.tieValue then
            return left.tieValue < right.tieValue
        end
        return left.uid < right.uid
    end)
    for index, result in ipairs(results) do
        result.rank = index
    end
    if limit and #results > limit then
        local limited = {}
        for index = 1, limit do
            limited[index] = results[index]
        end
        return limited
    end
    return results
end

function Scoreboard:player_result(uid)
    local player = self.state.players[uid]
    if not player then
        return nil
    end
    return self:_player_result(uid, player)
end

function Scoreboard:stats()
    local open_targets = 0
    local ranked_targets = 0
    for _, target in pairs(self.state.targets) do
        if not target.closed then
            open_targets = open_targets + 1
        end
        if target.ranked then
            ranked_targets = ranked_targets + 1
        end
    end
    return {
        players = util.count(self.state.players),
        targets = util.count(self.state.targets),
        rankedTargets = ranked_targets,
        openTargets = open_targets,
        damageRecords = self.state.damageRecordCount,
        rejectedRecords = self.state.rejectedRecordCount,
    }
end

return Scoreboard
