local Rewards = require("ped.rewards")
local Scoreboard = require("ped.scoreboard")
local util = require("ped.util")

local Director = {}
Director.__index = Director

local MICRO = 1000000

local function new_state()
    return {
        schemaVersion = 1,
        status = "idle",
        nonce = 0,
        event = nil,
        lastEvent = nil,
    }
end

function Director.new(options)
    local self = setmetatable({
        config = assert(options.config),
        store = assert(options.store),
        bridge = assert(options.bridge),
        logger = assert(options.logger),
        clock = options.clock or util.now_seconds,
        state = new_state(),
        scoreboard = nil,
        dirty = false,
        last_checkpoint = 0,
        next_reward_retry = 0,
        command_times = {},
        last_public_command = 0,
    }, Director)

    local restored, _, restore_error = self.store:load_snapshot()
    if restore_error then
        error(restore_error)
    end
    if restored then
        self.state = restored.director or new_state()
    end
    self.rewards = Rewards.new({
        logger = self.logger,
        persist = function(kind, data, journal_only)
            if journal_only then
                return self:_journal(kind, data)
            end
            return self:_persist(kind, data)
        end,
    }, restored and restored.rewards or nil)
    if restored and restored.scoreboard and self.state.event then
        self.scoreboard = Scoreboard.new(self:_scoreboard_options(self.state.event.id), restored.scoreboard)
    end
    if self.state.status == "starting" or self.state.status == "active" or self.state.status == "resolving" then
        self.state.event.interruptedStatus = self.state.status
        self.state.status = "recovery_required"
        self.logger:warn("Interrupted Siege League requires operator resolution before another start", { occurrence = self.state.event.id })
        self:_persist("recovery_required", { occurrenceId = self.state.event.id })
    end
    return self
end

function Director:_scoreboard_options(occurrence_id)
    return {
        occurrence_id = occurrence_id,
        target_points = self.config.siegeLeague.targetPoints,
        max_targets = self.config.limits.maxTargets,
        max_players = self.config.limits.maxPlayers,
        max_damage_records = self.config.limits.maxDamageRecords,
    }
end

function Director:_snapshot()
    return {
        schemaVersion = 1,
        director = self.state,
        rewards = self.rewards and self.rewards:to_state() or { schemaVersion = 1, obligations = {}, order = {} },
        scoreboard = self.scoreboard and self.scoreboard:to_state() or nil,
    }
end

function Director:_persist(kind, data)
    local appended, append_error = self:_journal(kind, data)
    if not appended then
        return false, append_error
    end
    return self:_checkpoint(kind)
end

function Director:_journal(kind, data)
    local appended, append_error = self.store:append(kind, data)
    if not appended then
        self.logger:error("Journal write failed", { error = append_error, kind = kind })
        return false, append_error
    end
    return true
end

function Director:_checkpoint(kind)
    local saved, save_error = self.store:save_snapshot(self:_snapshot())
    if not saved then
        self.logger:error("Snapshot write failed", { error = save_error, kind = kind })
        return false, save_error
    end
    self.dirty = false
    self.last_checkpoint = self.clock()
    return true
end

function Director:_mark_dirty()
    self.dirty = true
end

function Director:_announce(message)
    self.bridge:announce(util.sanitize_text(message, self.config.limits.maxAnnouncementLength))
end

function Director:_active_event()
    if self.state.status == "starting" or self.state.status == "active" then
        return self.state.event
    end
    return nil
end

function Director:start(source)
    if self.state.status ~= "idle" and self.state.status ~= "completed" and self.state.status ~= "aborted" then
        return false, "director is " .. self.state.status
    end
    if not self.config.capabilities.startAllInvasions then
        return false, "capabilities.startAllInvasions is disabled"
    end
    local healthy, health_error = self.bridge:preflight_start()
    if not healthy then
        return false, health_error
    end

    self.state.nonce = (self.state.nonce or 0) + 1
    local now = self.clock()
    local occurrence_id = util.new_occurrence_id(now, self.state.nonce)
    self.state.event = {
        id = occurrence_id,
        name = self.config.siegeLeague.name,
        status = "starting",
        source = source or "operator",
        startedAt = now,
        startedAtUtc = util.utc_now(),
        lastLifecycleAt = now,
        bases = {},
        timeoutBases = {},
    }
    self.state.status = "starting"
    self.scoreboard = Scoreboard.new(self:_scoreboard_options(occurrence_id))
    local durable, durable_error = self:_persist("event_start_intent", {
        occurrenceId = occurrence_id,
        source = source or "operator",
        allowCrossBaseRoaming = true,
    })
    if not durable then
        self.state.status = "recovery_required"
        return false, durable_error
    end

    if self.bridge.begin_event_discovery then self.bridge:begin_event_discovery() end
    local started, start_error = self.bridge:start_all_invasions()
    if not started then
        if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
        self.state.status = "aborted"
        self.state.event.status = "aborted"
        self.state.event.abortReason = start_error
        self:_persist("event_start_failed", { occurrenceId = occurrence_id, reason = start_error })
        return false, start_error
    end
    self:_announce("SIEGE LEAGUE: Every base is under threat. Move between bases, protect everything, and rack up contribution and final hits!")
    self.logger:info("Requested all-base Siege League", { occurrence = occurrence_id })
    return true, occurrence_id
end

function Director:on_invasion_start(base_id, group_id)
    local event = self:_active_event()
    if not event or type(base_id) ~= "string" or base_id == "" then
        return false
    end
    if not event.bases[base_id] then
        if util.count(event.bases) >= self.config.limits.maxBases then
            self.logger:error("Base limit reached; refusing additional event base", { base = util.mask_uid(base_id) })
            return false
        end
        event.bases[base_id] = {
            id = base_id,
            groupId = group_id,
            status = "active",
            startedAt = self.clock(),
        }
    else
        if event.bases[base_id].groupId ~= group_id then
            return false
        end
        event.bases[base_id].status = "active"
    end
    event.lastLifecycleAt = self.clock()
    event.status = "active"
    self.state.status = "active"
    self:_mark_dirty()
    self.logger:info("Invasion joined Siege League", { base = util.mask_uid(base_id), occurrence = event.id })
    return true
end

function Director:on_invasion_timeout(base_id, group_id)
    local event = self:_active_event()
    if not event then
        return false
    end
    if not event.bases[base_id] or event.bases[base_id].groupId ~= group_id then return false end
    event.timeoutBases[base_id] = true
    event.lastLifecycleAt = self.clock()
    self:_mark_dirty()
    return true
end

function Director:on_invasion_end(base_id, group_id)
    local event = self:_active_event()
    if not event then
        return false
    end
    local base = event.bases[base_id]
    if not base or base.groupId ~= group_id then
        return false
    end
    base.status = event.timeoutBases[base_id] and "timeout" or "completed"
    base.endedAt = self.clock()
    event.lastLifecycleAt = self.clock()
    self:_mark_dirty()
    return true
end

function Director:on_invasion_cancel()
    local event = self:_active_event()
    if not event then
        return false
    end
    for _, base in pairs(event.bases) do
        if base.status == "active" then
            base.status = "cancelled"
            base.endedAt = self.clock()
        end
    end
    event.lastLifecycleAt = self.clock()
    self:_mark_dirty()
    return true
end

function Director:on_damage(record)
    local event = self:_active_event()
    if not event or not self.config.capabilities.observeCombat then
        return false, "inactive"
    end
    if not event.bases[record.base_id] then
        return false, "base_not_tracked"
    end
    if record.source_kind == "direct_player" and not self.config.siegeLeague.creditDirectPlayer then
        record.source_kind = "uncredited"
        record.player_uid = nil
    elseif record.source_kind == "active_pal" and not self.config.siegeLeague.creditActivePal then
        record.source_kind = "uncredited"
        record.player_uid = nil
    elseif record.source_kind == "base_worker" and not self.config.siegeLeague.creditBaseWorkers then
        record.source_kind = "uncredited"
        record.player_uid = nil
    end
    local accepted, result = self.scoreboard:record_damage(record)
    if accepted then
        self:_mark_dirty()
    elseif result ~= "duplicate" and result ~= "target_closed" then
        self.logger:warn("Damage record rejected", { reason = result })
    end
    return accepted, result
end

function Director:on_death(record)
    local event = self:_active_event()
    if not event or not self.scoreboard then
        return false, "inactive"
    end
    if record.source_kind == "direct_player" and not self.config.siegeLeague.creditDirectPlayer then
        record.source_kind = "uncredited"
        record.player_uid = nil
    elseif record.source_kind == "active_pal" and not self.config.siegeLeague.creditActivePal then
        record.source_kind = "uncredited"
        record.player_uid = nil
    elseif record.source_kind == "base_worker" and not self.config.siegeLeague.creditBaseWorkers then
        record.source_kind = "uncredited"
        record.player_uid = nil
    end
    local closed, close_error = self.scoreboard:close_target(record)
    if closed then
        self:_mark_dirty()
    end
    return closed, close_error
end

function Director:on_target_unranked(target_id, reason)
    if not self.scoreboard then
        return false
    end
    local changed = self.scoreboard:mark_unranked(target_id, reason)
    if changed then
        self:_mark_dirty()
    end
    return changed
end

local function all_bases_closed(event)
    local found = false
    for _, base in pairs(event.bases) do
        found = true
        if base.status == "active" then
            return false
        end
    end
    return found
end

function Director:_create_rewards(rankings)
    local event = self.state.event
    local minimum_micro = self.config.siegeLeague.minimumParticipationPoints * MICRO
    local participation = self.config.rewards.participation
    local base_completion = self.config.rewards.baseCompletion
    for _, result in ipairs(rankings) do
        if participation.enabled and result.scoreMicro >= minimum_micro then
            local obligation, _, create_error = self.rewards:create({
                occurrence_id = event.id,
                definition_id = "personal-participation",
                player_uid = result.uid,
                item_id = participation.itemId,
                count = participation.count,
            })
            if not obligation then return false, create_error end
        end
        if base_completion.enabled then
            local rewarded = 0
            for _, base_id in ipairs(util.sorted_keys(result.baseScoreMicro)) do
                local base = event.bases[base_id]
                if rewarded >= base_completion.maxPerPlayer then
                    break
                end
                if base and base.status == "completed" and result.baseScoreMicro[base_id] >= minimum_micro then
                    local obligation, _, create_error = self.rewards:create({
                        occurrence_id = event.id,
                        definition_id = "successful-base-completion",
                        player_uid = result.uid,
                        base_id = base_id,
                        item_id = base_completion.itemId,
                        count = base_completion.count,
                    })
                    if not obligation then return false, create_error end
                    rewarded = rewarded + 1
                end
            end
        end
    end
    for _, reward in ipairs(self.config.rewards.podium) do
        local result = rankings[reward.rank]
        if reward.enabled ~= false and result and result.scoreMicro > 0 then
            local obligation, _, create_error = self.rewards:create({
                occurrence_id = event.id,
                definition_id = "podium-rank-" .. reward.rank,
                player_uid = result.uid,
                rank = reward.rank,
                item_id = reward.itemId,
                count = reward.count,
            })
            if not obligation then return false, create_error end
        end
    end
    return true
end

function Director:resolve(reason)
    if self.state.status ~= "active" and self.state.status ~= "starting" and self.state.status ~= "recovery_required" then
        return false, "nothing to resolve"
    end
    local event = self.state.event
    self.state.status = "resolving"
    event.status = "resolving"
    event.resolveReason = reason or "completed"
    if not self:_persist("event_resolve_intent", { occurrenceId = event.id, reason = event.resolveReason }) then
        self.state.status = "recovery_required"
        return false, "unable to persist resolve intent"
    end

    local rankings = self.scoreboard and self.scoreboard:rankings() or {}
    event.finalRankings = rankings
    event.scoreStats = self.scoreboard and self.scoreboard:stats() or {}
    local rewards_created, rewards_error = self:_create_rewards(rankings)
    if not rewards_created then
        self.state.status = "recovery_required"
        event.status = "recovery_required"
        event.recoveryReason = "reward obligation persistence failed: " .. tostring(rewards_error)
        self:_checkpoint("reward_obligation_failure")
        return false, event.recoveryReason
    end
    if not self:_checkpoint("reward_obligations") then
        self.state.status = "recovery_required"
        event.status = "recovery_required"
        return false, "unable to checkpoint reward obligations"
    end
    event.endedAt = self.clock()
    event.endedAtUtc = util.utc_now()
    event.status = "completed"
    self.state.status = "completed"
    self.state.lastEvent = {
        id = event.id,
        endedAtUtc = event.endedAtUtc,
        rankings = rankings,
        scoreStats = event.scoreStats,
    }
    local completed, completion_error = self:_persist("event_completed", { occurrenceId = event.id, reason = event.resolveReason, players = #rankings })
    if not completed then
        self.state.status = "recovery_required"
        event.status = "recovery_required"
        event.recoveryReason = "completion persistence failed: " .. tostring(completion_error)
        return false, event.recoveryReason
    end
    if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
    if self.config.capabilities.grantItems then
        self.rewards:process(self.bridge, 32, function() return self:_checkpoint("reward") end)
    end
    self:_announce(self:leaderboard_text(3))
    return true
end

function Director:abort(reason)
    if not self.state.event or self.state.status == "idle" then
        return false, "nothing to abort"
    end
    self.state.status = "aborted"
    self.state.event.status = "aborted"
    self.state.event.abortReason = reason or "operator"
    self.state.event.endedAt = self.clock()
    local persisted, persist_error = self:_persist("event_aborted", { occurrenceId = self.state.event.id, reason = self.state.event.abortReason })
    if not persisted then
        self.state.status = "recovery_required"
        self.state.event.status = "recovery_required"
        return false, "abort persistence failed: " .. tostring(persist_error)
    end
    if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
    self:_announce("Siege League scoring stopped. Native invasions were left to Palworld's normal lifecycle for safety.")
    return true
end

function Director:reset()
    if self.state.status ~= "completed" and self.state.status ~= "aborted" and self.state.status ~= "recovery_required" then
        return false, "reset is allowed only after completion, abort, or recovery-required state"
    end
    local active = self.bridge:active_invasion_count()
    if active > 0 then
        return false, "native invasion incidents are still active"
    end
    self.state.lastEvent = self.state.lastEvent or self.state.event
    self.state.event = nil
    self.state.status = "idle"
    self.scoreboard = nil
    self:_persist("director_reset", {})
    return true
end

function Director:status_text()
    local event = self.state.event
    local rewards = self.rewards:summary()
    if not event then
        return string.format("Pal Event Director: %s. Rewards pending=%d review=%d.", self.state.status, rewards.pending, rewards.operator_review)
    end
    local active_bases = 0
    local completed_bases = 0
    for _, base in pairs(event.bases) do
        if base.status == "active" then
            active_bases = active_bases + 1
        elseif base.status == "completed" then
            completed_bases = completed_bases + 1
        end
    end
    local stats = self.scoreboard and self.scoreboard:stats() or { players = 0, targets = 0 }
    return string.format("%s %s: bases active=%d completed=%d, players=%d, tracked invaders=%d.", event.name, self.state.status, active_bases, completed_bases, stats.players, stats.targets)
end

function Director:leaderboard_text(limit)
    local rankings
    if self.scoreboard then
        rankings = self.scoreboard:rankings(limit or self.config.siegeLeague.leaderboardSize)
    elseif self.state.lastEvent then
        rankings = self.state.lastEvent.rankings or {}
    else
        rankings = {}
    end
    if #rankings == 0 then
        return "Siege League standings: no qualifying contribution yet."
    end
    local parts = { "Siege League standings:" }
    for index, result in ipairs(rankings) do
        if index > (limit or self.config.siegeLeague.leaderboardSize) then
            break
        end
        parts[#parts + 1] = string.format("%d) %s %.3f pts, %d final hits, %d bases", index, result.displayName or util.mask_uid(result.uid), result.score or result.scoreMicro / MICRO, result.finalHits or 0, result.basesDefended or 0)
    end
    return table.concat(parts, " ")
end

function Director:player_text(uid)
    if not self.scoreboard then
        return "No active Siege League scoreboard."
    end
    local result = self.scoreboard:player_result(uid)
    if not result then
        return "No qualifying Siege League contribution recorded for " .. util.mask_uid(uid) .. "."
    end
    return string.format("Siege score for %s: %.3f points, %d final hits, %d bases defended (direct %d, Pal %d damage).", result.displayName, result.score, result.finalHits, result.basesDefended, result.directDamage, result.palDamage)
end

function Director:handle_chat(uid, message)
    message = util.trim(message)
    local lowered = message:lower()
    if not util.starts_with(lowered, "!") then
        return false
    end
    local now = self.clock()
    if self.command_times[uid] and now - self.command_times[uid] < 2 then
        return true
    end
    if now - self.last_public_command < 5 then
        return true
    end
    self.command_times[uid] = now
    self.last_public_command = now
    if lowered == "!event" then
        self:_announce(self:status_text())
        return true
    elseif lowered == "!score" then
        self:_announce(self:player_text(uid))
        return true
    elseif lowered == "!leaderboard" then
        self:_announce(self:leaderboard_text())
        return true
    elseif util.starts_with(lowered, "!ped ") and require("ped.config").is_operator(self.config, uid) then
        return self:handle_operator_command(message:sub(6), "chat:" .. util.mask_uid(uid))
    end
    return false
end

function Director:handle_operator_command(command, source)
    local words = util.split_words(command)
    local action = (words[1] or "status"):lower()
    local ok, result
    if action == "start" then
        ok, result = self:start(source or "console")
    elseif action == "status" then
        ok, result = true, self:status_text()
    elseif action == "leaderboard" then
        ok, result = true, self:leaderboard_text()
    elseif action == "resolve" then
        ok, result = self:resolve("operator")
    elseif action == "abort" then
        ok, result = self:abort("operator")
    elseif action == "reset" then
        ok, result = self:reset()
    elseif action == "rewards" then
        if not self.config.capabilities.grantItems then
            ok, result = false, "capabilities.grantItems is disabled"
        else
            local count = self.rewards:process(self.bridge, 32, function() return self:_checkpoint("reward") end)
            ok, result = true, "processed " .. count .. " pending reward obligations"
        end
    else
        ok, result = false, "unknown command; use start, status, leaderboard, resolve, abort, reset, or rewards"
    end
    if source and source:match("^chat:") then
        self:_announce((ok and "PED: " or "PED ERROR: ") .. tostring(result or "ok"))
    end
    return ok, result
end

function Director:tick()
    local now = self.clock()
    local event = self:_active_event()
    if event then
        if self.state.status == "starting" and now - event.startedAt >= self.config.siegeLeague.startDiscoverySeconds then
            if self.bridge.close_event_discovery then self.bridge:close_event_discovery() end
        end
        if self.state.status == "starting" and now - event.startedAt >= self.config.siegeLeague.startDiscoverySeconds and util.count(event.bases) == 0 then
            self:abort("no native invasion starts observed")
        elseif now - event.startedAt >= self.config.siegeLeague.maxRuntimeSeconds then
            self:resolve("maximum runtime")
        elseif all_bases_closed(event)
            and now - event.startedAt >= self.config.siegeLeague.startDiscoverySeconds
            and now - event.lastLifecycleAt >= self.config.siegeLeague.settleDelaySeconds then
            self:resolve("all observed bases resolved")
        end
    end
    if self.dirty and now - self.last_checkpoint >= self.config.runtime.checkpointIntervalSeconds then
        self:_persist("checkpoint", { status = self.state.status })
    end
    if self.config.capabilities.grantItems and now >= self.next_reward_retry then
        self.rewards:process(self.bridge, 4, function() return self:_checkpoint("reward") end)
        self.next_reward_retry = now + 30
    end
end

return Director
