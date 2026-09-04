local Rewards = require("ped.rewards")
local Scheduler = require("ped.scheduler")
local Scoreboard = require("ped.scoreboard")
local bounties = require("ped.bounties")
local config_module = require("ped.config")
local util = require("ped.util")
local version = require("ped.version")

local Director = {}
Director.__index = Director

local MICRO = 1000000

local function new_state()
    return {
        schemaVersion = 2,
        status = "idle",
        nonce = 0,
        lastUserStartAt = 0,
        event = nil,
        lastEvent = nil,
    }
end

local function validate_restored_state(restored)
    if type(restored) ~= "table" or restored.schemaVersion ~= version.state_schema then
        error("persistent state schema is unsupported; archive the laboratory state directory and restart with a clean schema-" .. version.state_schema .. " state")
    end
    if type(restored.director) ~= "table" or restored.director.schemaVersion ~= 2 then
        error("director state schema is unsupported")
    end
    local statuses = { idle = true, starting = true, active = true, resolving = true, completed = true, aborted = true, recovery_required = true }
    if not statuses[restored.director.status] or not util.is_integer(restored.director.nonce) then
        error("director state shape is invalid")
    end
    local event_required = restored.director.status == "starting" or restored.director.status == "active"
        or restored.director.status == "resolving" or restored.director.status == "recovery_required"
    if event_required and type(restored.director.event) ~= "table" then
        error("director state requires an event")
    end
    if type(restored.rewards) ~= "table" or restored.rewards.schemaVersion ~= 1 then
        error("reward state schema is unsupported")
    end
    if type(restored.scheduler) ~= "table" or restored.scheduler.schemaVersion ~= 2 then
        error("scheduler state schema is unsupported")
    end
    if type(restored.scheduler.occurrences) ~= "table" or not util.is_integer(restored.scheduler.manualNonce or 0) then
        error("scheduler state shape is invalid")
    end
    if restored.scoreboard ~= nil and (type(restored.scoreboard) ~= "table" or restored.scoreboard.schemaVersion ~= 1) then
        error("scoreboard state schema is unsupported")
    end
end

function Director.new(options)
    local scheduler_start_token = {}
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
        last_start_attempt = 0,
        scheduler_start_token = scheduler_start_token,
    }, Director)

    local restored, _, restore_error, recovered_from_journal = self.store:load_snapshot()
    if restore_error then
        error(restore_error)
    end
    if restored then
        validate_restored_state(restored)
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
    self.scheduler = Scheduler.new({
        schedules = self.config.schedules,
        clock = self.clock,
        persist = function(kind, data)
            return self:_persist(kind, data)
        end,
        announce = function(message) return self:_announce(message) end,
        start_event = function(source, profile, token, occurrence_key) return self:start(source, profile, token, occurrence_key) end,
        can_start = function()
            return self.state.status == "idle" or self.state.status == "completed" or self.state.status == "aborted",
                "another event or recovery state is active"
        end,
        start_token = scheduler_start_token,
            warning_grace_seconds = math.max(5, math.ceil(self.config.runtime.pollIntervalMs / 1000) * 2),
    }, restored and restored.scheduler or nil)
    if restored and restored.scoreboard and self.state.event then
        self.scoreboard = Scoreboard.new(self:_scoreboard_options(self.state.event.id), restored.scoreboard)
    end
    if self.state.status == "starting" or self.state.status == "active" or self.state.status == "resolving" then
        self.state.event.interruptedStatus = self.state.status
        self.state.status = "recovery_required"
        self.logger:warn("Interrupted Siege League requires operator resolution before another start", { occurrence = self.state.event.id })
        self:_persist("recovery_required", { occurrenceId = self.state.event.id })
    elseif recovered_from_journal then
        self:_checkpoint("journal_tail_recovered")
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
        require_enrollment = true,
    }
end

function Director:_snapshot()
    return {
        schemaVersion = version.state_schema,
        director = self.state,
        rewards = self.rewards and self.rewards:to_state() or { schemaVersion = 1, obligations = {}, order = {} },
        scoreboard = self.scoreboard and self.scoreboard:to_state() or nil,
        scheduler = self.scheduler and self.scheduler:to_state() or nil,
    }
end

function Director:_persist(kind, data)
    local appended, append_error = self:_journal(kind, data)
    if not appended then
        return false, append_error
    end
    local saved, save_error = self:_checkpoint(kind)
    if not saved then
        self:_mark_dirty()
        self.logger:warn("State remains recoverable in the journal; snapshot checkpoint was deferred", { error = save_error, kind = kind })
        return true, save_error
    end
    return true
end

function Director:_journal(kind, data)
    local appended, append_error = self.store:append(kind, data, self:_snapshot())
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
    return self.bridge:announce(util.sanitize_text(message, self.config.limits.maxAnnouncementLength))
end

function Director:_active_event()
    if self.state.status == "starting" or self.state.status == "active" then
        return self.state.event
    end
    return nil
end

function Director:_profile_allowed(profile_id)
    profile_id = bounties.normalize_profile_id(profile_id or self.config.siegeLeague.defaultProfile)
    if not profile_id then
        return nil, "unknown profile"
    end
    for _, allowed in ipairs(self.config.siegeLeague.allowedProfiles) do
        if allowed == profile_id then
            return profile_id
        end
    end
    return nil, "profile is not enabled: " .. profile_id
end

function Director:arm_start(source, requested_profile, countdown_minutes)
    if self.state.status ~= "idle" and self.state.status ~= "completed" and self.state.status ~= "aborted" then
        return false, "director is " .. self.state.status
    end
    if not self.config.capabilities.startAllInvasions then
        return false, "capabilities.startAllInvasions is disabled"
    end
    local profile_id, profile_error = self:_profile_allowed(requested_profile)
    if not profile_id then return false, profile_error end
    if profile_id ~= "native" and not self.config.capabilities.substituteBountyMembers then
        return false, "capabilities.substituteBountyMembers is disabled"
    end
    if countdown_minutes == nil or countdown_minutes == "" then
        countdown_minutes = self.config.siegeLeague.manualCountdownMinutes
    else
        countdown_minutes = tonumber(countdown_minutes)
        if countdown_minutes == nil then
            return false, "countdown must be an integer from 10 through 60 minutes"
        end
    end
    if not util.is_integer(countdown_minutes) or countdown_minutes < 10 or countdown_minutes > 60 then
        return false, "countdown must be an integer from 10 through 60 minutes"
    end
    local armed, result = self.scheduler:arm_manual(profile_id, source or "operator", countdown_minutes * 60, bounties.profile(profile_id).name)
    if not armed then return false, result end
    if not self:_checkpoint("manual_countdown") then
        self.scheduler:cancel_manual("checkpoint_failed")
        return false, "unable to checkpoint manual countdown"
    end
    return true, result.key
end

function Director:start(source, requested_profile, scheduler_token, scheduler_occurrence_key)
    if scheduler_token ~= self.scheduler_start_token or type(scheduler_occurrence_key) ~= "string" then
        return false, "direct invasion start denied; arm a warning countdown"
    end
    local scheduler_occurrence = self.scheduler and self.scheduler.state.occurrences[scheduler_occurrence_key] or nil
    if not scheduler_occurrence or scheduler_occurrence.status ~= "starting" or scheduler_occurrence.profileId ~= requested_profile then
        return false, "scheduler start authorization is invalid"
    end
    for _, seconds in ipairs({ 600, 300, 60 }) do
        if not scheduler_occurrence.warningsSent[tostring(seconds)] then
            return false, "scheduler start authorization lacks mandatory warnings"
        end
    end
    if self.state.status ~= "idle" and self.state.status ~= "completed" and self.state.status ~= "aborted" then
        return false, "director is " .. self.state.status
    end
    if not self.config.capabilities.startAllInvasions then
        return false, "capabilities.startAllInvasions is disabled"
    end
    local profile_id, profile_error = self:_profile_allowed(requested_profile)
    if not profile_id then
        return false, profile_error
    end
    if profile_id ~= "native" and not self.config.capabilities.substituteBountyMembers then
        return false, "capabilities.substituteBountyMembers is disabled"
    end
    local healthy, health_error = self.bridge:preflight_start(profile_id)
    if not healthy then
        return false, health_error
    end

    local previous_status = self.state.status
    self.state.nonce = (self.state.nonce or 0) + 1
    local now = self.clock()
    local occurrence_id = util.new_occurrence_id(now, self.state.nonce)
    self.state.event = {
        id = occurrence_id,
        name = self.config.siegeLeague.name,
        profileId = profile_id,
        profileName = bounties.profile(profile_id).name,
        status = "starting",
        source = source or "operator",
        startedAt = now,
        startedAtUtc = util.utc_now(),
        lastLifecycleAt = now,
        bases = {},
        compositions = {},
        timeoutBases = {},
        roster = {},
    }
    self.state.status = "starting"
    self.scoreboard = Scoreboard.new(self:_scoreboard_options(occurrence_id))
    local expected_bases, start_roster = {}, nil
    if self.bridge.begin_event_discovery then
        expected_bases, start_roster = self.bridge:begin_event_discovery(profile_id, occurrence_id)
    end
    expected_bases = expected_bases or {}
    if start_roster == nil then
        start_roster = self.bridge.list_online_players and self.bridge:list_online_players() or {}
    end
    if #start_roster > self.config.limits.maxPlayers then
        if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
        self.state.event = nil
        self.state.status = previous_status
        self.scoreboard = nil
        return false, string.format("online roster count %d exceeds configured maximum %d", #start_roster, self.config.limits.maxPlayers)
    end
    for _, player in ipairs(start_roster) do
        local enrolled, enrollment_error = self.scoreboard:enroll_player(player.uid, player.name, now)
        if not enrolled then
            if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
            self.state.event = nil
            self.state.status = previous_status
            self.scoreboard = nil
            return false, "unable to enroll complete start roster: " .. tostring(enrollment_error)
        end
        self.state.event.roster[player.uid] = { name = player.name, firstSeenAt = now, cohort = "start" }
    end
    for _, target in ipairs(expected_bases) do
        local base_id = type(target) == "table" and target.id or target
        self.state.event.bases[base_id] = {
            id = base_id,
            guildId = type(target) == "table" and target.guildId or nil,
            status = "pending",
            dispatchStatus = "not_requested",
            ranked = false,
        }
    end
    if util.count(self.state.event.bases) < 1 then
        if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
        self.state.event = nil
        self.state.status = previous_status
        self.scoreboard = nil
        return false, "preflight produced no eligible event bases"
    end
    local durable, durable_error = self:_persist("event_start_intent", {
        occurrenceId = occurrence_id,
        source = source or "operator",
        profileId = profile_id,
        allowCrossBaseRoaming = true,
        eligibleBases = util.count(self.state.event.bases),
        enrolledPlayers = util.count(self.state.event.roster),
    })
    if not durable then
        if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
        self.state.status = "recovery_required"
        return false, durable_error
    end

    local started, start_result = self.bridge:start_all_invasions(profile_id)
    if not started then
        if type(start_result) == "table" and type(start_result.requests) == "table" then
            for _, request in ipairs(start_result.requests) do
                local base = self.state.event.bases[request.baseId]
                if base then
                    base.dispatchStatus = request.status
                    base.dispatchError = request.error
                    base.status = "dispatch_call_failed"
                    base.endedAt = now
                end
            end
        end
        if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
        self.state.status = "aborted"
        self.state.event.status = "aborted"
        self.state.event.abortReason = type(start_result) == "table" and start_result.error or start_result
        self:_persist("event_start_failed", { occurrenceId = occurrence_id, result = start_result })
        return false, self.state.event.abortReason
    end
    if type(start_result) == "table" and type(start_result.requests) == "table" then
        for _, request in ipairs(start_result.requests) do
            local base = self.state.event.bases[request.baseId]
            if base then
                base.dispatchStatus = request.status
                base.dispatchError = request.error
                if request.status == "dispatch_call_failed" and base.status == "pending" then
                    base.status = "dispatch_call_failed"
                    base.endedAt = now
                end
            end
        end
    end
    local dispatch_persisted, dispatch_error = self:_persist("event_dispatch_results", {
        occurrenceId = occurrence_id,
        result = start_result,
    })
    if not dispatch_persisted then
        self.state.status = "recovery_required"
        self.state.event.status = "recovery_required"
        return false, "unable to persist selected-base dispatch results: " .. tostring(dispatch_error)
    end
    self:_announce("SIEGE LEAGUE - " .. bounties.profile(profile_id).name .. ": Every eligible online-guild base is under attack. Move between bases, protect everything, and rack up contribution and final hits!")
    self.logger:info("Requested filtered-base Siege League", { occurrence = occurrence_id, profile = profile_id })
    return true, occurrence_id
end

function Director:reconcile_online_players()
    local event = self:_active_event()
    if not event or not self.scoreboard or not self.bridge.list_online_players then
        return true
    end
    local now = self.clock()
    for _, player in ipairs(self.bridge:list_online_players()) do
        if not event.roster[player.uid] then
            local enrolled, enrollment_error = self.scoreboard:enroll_player(player.uid, player.name, now)
            if enrolled then
                event.roster[player.uid] = { name = player.name, firstSeenAt = now, cohort = "late" }
                self:_mark_dirty()
            else
                event.rosterRejected = event.rosterRejected or {}
                if not event.rosterRejected[player.uid] then
                    event.rosterRejected[player.uid] = tostring(enrollment_error)
                    event.rankingIntegrity = "degraded"
                    self.logger:error("Unable to enroll an online late joiner", { player = util.mask_uid(player.uid), reason = enrollment_error })
                    self:_mark_dirty()
                end
            end
        else
            self.scoreboard:enroll_player(player.uid, player.name, now)
        end
    end
    return event.rankingIntegrity ~= "degraded"
end

function Director:on_invasion_start(base_id, group_id)
    local event = self:_active_event()
    if not event or type(base_id) ~= "string" or base_id == "" then
        return false
    end
    if not event.bases[base_id] then
        self.logger:error("Rejected invasion start outside expected base set", { base = util.mask_uid(base_id) })
        return false
    elseif event.bases[base_id].status == "pending" then
        event.bases[base_id].groupId = group_id
        event.bases[base_id].status = "active"
        event.bases[base_id].startedAt = self.clock()
        event.bases[base_id].ranked = event.profileId == "native" or (event.compositions[base_id] and not event.compositions[base_id].failed)
    elseif event.bases[base_id].status == "active" and event.bases[base_id].groupId == group_id then
        return true
    else
        return false
    end
    event.lastLifecycleAt = self.clock()
    event.status = "active"
    self.state.status = "active"
    self:_mark_dirty()
    self.logger:info("Invasion joined Siege League", { base = util.mask_uid(base_id), occurrence = event.id })
    return true
end

function Director:_apply_credit_policy(event, record)
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
    if record.player_uid and not event.roster[record.player_uid] then
        self:reconcile_online_players()
        if not event.roster[record.player_uid] then
            record.source_kind = "uncredited"
            record.player_uid = nil
            record.player_name = nil
        end
    end
end

function Director:on_composition_result(base_id, replaced_count, selected_count, composition_error, assignments)
    local event = self:_active_event()
    if not event or type(base_id) ~= "string" then
        return false
    end
    local composition = event.compositions[base_id]
    if not composition then
        composition = { selections = {}, failed = false }
        event.compositions[base_id] = composition
    end
    composition.selections[#composition.selections + 1] = {
        profileId = event.profileId,
        replaced = replaced_count or 0,
        selected = selected_count or 0,
        error = composition_error,
        assignments = assignments or {},
    }
    if composition_error then
        composition.failed = true
        event.compositionFailed = true
        if event.bases[base_id] then event.bases[base_id].ranked = false end
        if self.scoreboard then self.scoreboard:unrank_base(base_id, "composition_failure") end
    elseif event.bases[base_id] and not composition.failed then
        event.bases[base_id].ranked = true
    end
    self:_mark_dirty()
    return composition_error == nil
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
    if event.bases[record.base_id].status ~= "active" then
        return false, "base_not_active"
    end
    if not record.group_id or record.group_id ~= event.bases[record.base_id].groupId then
        return false, "group_not_owned"
    end
    if event.bases[record.base_id].ranked == false then
        return false, "base_composition_unranked"
    end
    self:_apply_credit_policy(event, record)
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
    local base = event.bases[record.base_id]
    if not base or base.status ~= "active" then
        return false, "base_not_active"
    end
    if not record.group_id or record.group_id ~= base.groupId then
        return false, "group_not_owned"
    end
    self:_apply_credit_policy(event, record)
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
        if base.status == "active" or base.status == "pending" then
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
    if event.rankingIntegrity ~= "degraded" then
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
    else
        event.podiumSuppressedReason = "global_roster_incomplete"
    end
    return true
end

function Director:_classify_unresolved_bases(reason)
    local event = self.state.event
    if not event then return end
    local status = reason == "maximum runtime" and "runtime_timeout" or "operator_resolved"
    local now = self.clock()
    for _, base in pairs(event.bases) do
        if base.status == "pending" or base.status == "active" then
            base.status = status
            base.endedAt = now
        end
    end
end

function Director:resolve(reason)
    if self.state.status ~= "active" and self.state.status ~= "starting" and self.state.status ~= "recovery_required" then
        return false, "nothing to resolve"
    end
    local event = self.state.event
    self:_classify_unresolved_bases(reason or "completed")
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
    return string.format("%s (%s) %s: bases active=%d completed=%d, players=%d, tracked invaders=%d.", event.name, event.profileName or event.profileId or "unknown", self.state.status, active_bases, completed_bases, stats.players, stats.targets)
end

function Director:profiles_text()
    local enabled = {}
    for _, profile_id in ipairs(self.config.siegeLeague.allowedProfiles) do
        local profile = bounties.profile(profile_id)
        if profile then
            enabled[#enabled + 1] = profile.id .. " (" .. profile.name .. ")"
        end
    end
    return "Siege profiles: " .. table.concat(enabled, ", ") .. ". Default: " .. self.config.siegeLeague.defaultProfile .. "."
end

function Director:schedule_text()
    local upcoming = self.scheduler and self.scheduler:upcoming(5) or {}
    if #upcoming == 0 then return "No enabled Siege League schedules." end
    local parts = { "Upcoming Siege League:" }
    for _, item in ipairs(upcoming) do
        parts[#parts + 1] = item.id .. "=" .. item.localTime .. " (" .. item.profile .. ")"
    end
    return table.concat(parts, " ")
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
    local words = util.split_words(lowered)
    local public_query = lowered == "!event" or lowered == "!score" or lowered == "!leaderboard"
        or (words[1] == "!siege" and ({ status = true, profiles = true, schedule = true, score = true, leaderboard = true })[words[2] or "status"])
    if public_query and now - self.last_public_command < 5 then
        return true
    end
    self.command_times[uid] = now
    if public_query then self.last_public_command = now end
    if words[1] == "!siege" then
        local action = words[2] or "status"
        if action == "status" then
            self:_announce(self:status_text())
            return true
        elseif action == "profiles" then
            self:_announce(self:profiles_text())
            return true
        elseif action == "schedule" then
            self:_announce(self:schedule_text())
            return true
        elseif action == "score" then
            self:_announce(self:player_text(uid))
            return true
        elseif action == "leaderboard" then
            self:_announce(self:leaderboard_text())
            return true
        elseif action == "start" then
            local operator = config_module.is_operator(self.config, uid)
            if not operator and self.config.siegeLeague.chatStartPolicy ~= "anyUser" then
                self:_announce("Siege League start denied: only configured operators may start an alarm.")
                return true
            end
            if not operator then
                local last_start = self.state.lastUserStartAt or 0
                local remaining = last_start > 0 and (self.config.siegeLeague.userStartCooldownSeconds - (now - last_start)) or 0
                if remaining > 0 then
                    self:_announce("Siege League user-start cooldown: " .. math.ceil(remaining / 60) .. " minute(s) remaining.")
                    return true
                end
            end
            if now - self.last_start_attempt < 10 then
                self:_announce("Siege League start requests are temporarily rate-limited.")
                return true
            end
            self.last_start_attempt = now
            local profile_id, profile_error = self:_profile_allowed(words[3])
            if not profile_id then
                self:_announce("Siege League start failed: " .. tostring(profile_error))
                return true
            end
            if self.state.status ~= "idle" and self.state.status ~= "completed" and self.state.status ~= "aborted" then
                self:_announce("Siege League start failed: director is " .. self.state.status)
                return true
            end
            local previous_user_start = self.state.lastUserStartAt or 0
            if not operator then
                self.state.lastUserStartAt = now
                local persisted, persist_error = self:_persist("user_start_cooldown_intent", { playerUid = util.mask_uid(uid), profileId = profile_id })
                if not persisted then
                    self.state.lastUserStartAt = previous_user_start
                    self:_announce("Siege League start failed: unable to persist user cooldown: " .. tostring(persist_error))
                    return true
                end
            end
            local ok, result = self:arm_start("chat:" .. util.mask_uid(uid), profile_id, words[4])
            if not ok and not operator then
                self.state.lastUserStartAt = previous_user_start
                local rollback_ok = self:_persist("user_start_cooldown_rollback", { playerUid = util.mask_uid(uid), reason = tostring(result) })
                if not rollback_ok then
                    self.state.status = "recovery_required"
                end
            end
            if not ok then
                self:_announce("Siege League start failed: " .. tostring(result))
            end
            return true
        elseif config_module.is_operator(self.config, uid) and action == "cancel" then
            local ok, result = self.scheduler:cancel_manual("chat_operator")
            if ok then self:_checkpoint("manual_countdown_cancelled") end
            self:_announce((ok and "Siege countdown cancelled." or "Siege cancel failed: " .. tostring(result)))
            return true
        elseif config_module.is_operator(self.config, uid) and (action == "resolve" or action == "abort" or action == "reset") then
            return self:handle_operator_command(action, "chat:" .. util.mask_uid(uid))
        end
        self:_announce("Siege commands: !siege status|profiles|schedule|score|leaderboard|start <profile> [10-60 minutes].")
        return true
    elseif lowered == "!event" then
        self:_announce(self:status_text())
        return true
    elseif lowered == "!score" then
        self:_announce(self:player_text(uid))
        return true
    elseif lowered == "!leaderboard" then
        self:_announce(self:leaderboard_text())
        return true
    elseif util.starts_with(lowered, "!ped ") and config_module.is_operator(self.config, uid) then
        return self:handle_operator_command(message:sub(6), "chat:" .. util.mask_uid(uid))
    end
    return false
end

function Director:handle_operator_command(command, source)
    local words = util.split_words(command)
    local action = (words[1] or "status"):lower()
    local ok, result
    if action == "start" then
        ok, result = self:arm_start(source or "console", words[2], words[3])
    elseif action == "status" then
        ok, result = true, self:status_text()
    elseif action == "leaderboard" then
        ok, result = true, self:leaderboard_text()
    elseif action == "profiles" then
        ok, result = true, self:profiles_text()
    elseif action == "schedule" then
        ok, result = true, self:schedule_text()
    elseif action == "cancel" then
        ok, result = self.scheduler:cancel_manual("console_operator")
        if ok then self:_checkpoint("manual_countdown_cancelled") end
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
        ok, result = false, "unknown command; use start [profile] [minutes], cancel, status, profiles, schedule, leaderboard, resolve, abort, reset, or rewards"
    end
    if source and source:match("^chat:") then
        self:_announce((ok and "PED: " or "PED ERROR: ") .. tostring(result or "ok"))
    end
    return ok, result
end

function Director:tick()
    local now = self.clock()
    if self.scheduler then self.scheduler:tick(now) end
    local event = self:_active_event()
    if event then
        self:reconcile_online_players()
        if not event.discoveryClosed and now - event.startedAt >= self.config.siegeLeague.startDiscoverySeconds then
            if self.bridge.close_event_discovery then self.bridge:close_event_discovery() end
            event.discoveryClosed = true
            self:_mark_dirty()
        end
        if now - event.startedAt >= self.config.siegeLeague.maxRuntimeSeconds then
            self:resolve("maximum runtime")
        elseif now - event.startedAt >= self.config.siegeLeague.startDiscoverySeconds then
            local active_count = 0
            for _, base in pairs(event.bases) do
                if base.status == "pending" then
                    base.status = "native_start_missing"
                    base.endedAt = now
                    self:_mark_dirty()
                elseif base.status == "active" then
                    active_count = active_count + 1
                end
            end
            if active_count == 0 and all_bases_closed(event) and now - event.lastLifecycleAt >= self.config.siegeLeague.settleDelaySeconds then
                self:resolve("all expected bases classified")
            end
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
