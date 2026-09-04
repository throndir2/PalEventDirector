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
local BANNER_MAX_LENGTH = 80

local function native_start_guard(bridge)
    if type(bridge.native_start_guard) == "function" then return bridge:native_start_guard() end
    return true -- Pure-Lua simulation bridges have no native adapter.
end

local function warning_sets_match(actual, expected)
    if type(actual) ~= "table" or #actual ~= #expected then return false end
    local remaining = {}
    for _, seconds in ipairs(expected) do remaining[seconds] = true end
    for _, seconds in ipairs(actual) do
        if not util.is_integer(seconds) or not remaining[seconds] then return false end
        remaining[seconds] = nil
    end
    return next(remaining) == nil
end

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
    local scheduler_interrupted = false
    for _, occurrence in pairs(restored and restored.scheduler.occurrences or {}) do
        if occurrence.status == "starting" or occurrence.status == "awaiting_confirmation" then
            scheduler_interrupted = true
        end
    end
    self.scheduler = Scheduler.new({
        schedules = self.config.schedules,
        clock = self.clock,
        persist = function(kind, data)
            return self:_persist(kind, data)
        end,
        notify = function(title, detail) return self:_notify(title, detail) end,
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
        if not self:_persist("recovery_required", { occurrenceId = self.state.event.id }) then
            error("Unable to persist interrupted-event recovery; diagnostic startup blocked")
        end
    elseif scheduler_interrupted then
        if not self:_persist("scheduler_recovery_required", { reason = "interrupted_native_preflight_or_start" }) then
            error("Unable to persist interrupted-preflight recovery; diagnostic startup blocked")
        end
    elseif recovered_from_journal then
        if not self:_checkpoint("journal_tail_recovered") then error("Unable to checkpoint journal recovery; diagnostic startup blocked") end
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

function Director:_banner(message)
    local maximum = math.min(BANNER_MAX_LENGTH, self.config.limits.maxAnnouncementLength)
    return self.bridge:announce(util.sanitize_text(message, maximum))
end

function Director:_chat(message, recipient_uid)
    message = util.sanitize_text(message, self.config.limits.maxAnnouncementLength)
    if type(self.bridge.send_chat) == "function" then
        return self.bridge:send_chat(message, recipient_uid)
    end
    return false, "system chat transport is unavailable"
end

function Director:_notify(title, detail)
    local announced, announce_error = self:_banner(title)
    if not announced then return false, announce_error, false end
    local chatted, chat_error = self:_chat(detail)
    if not chatted then
        self.logger:warn("Detailed system chat could not be delivered", { error = chat_error, title = title })
        return false, chat_error, true
    end
    return true
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
    local allowed, reason = native_start_guard(self.bridge)
    if not allowed then return false, reason end
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
    if self.bridge.preflight_environment then
        local environment_ok, environment_error = self.bridge:preflight_environment()
        if not environment_ok then
            return false, environment_error
        end
    end
    if countdown_minutes == nil or countdown_minutes == "" then
        countdown_minutes = self.config.siegeLeague.manualCountdownMinutes
    else
        countdown_minutes = tonumber(countdown_minutes)
        if countdown_minutes == nil then
            return false, "countdown must be an integer from 0 through 60 minutes"
        end
    end
    if not util.is_integer(countdown_minutes) or countdown_minutes < 0 or countdown_minutes > 60 then
        return false, "countdown must be an integer from 0 through 60 minutes"
    end
    local armed, result = self.scheduler:arm_manual(profile_id, source or "operator", countdown_minutes * 60, bounties.profile(profile_id).name)
    if not armed then return false, result end
    return true, result.key
end

function Director:_apply_dispatch_results(result)
    local event = self.state.event
    if not event or type(result) ~= "table" or type(result.requests) ~= "table" then return end
    local now = self.clock()
    for _, request in ipairs(result.requests) do
        local base = event.bases[request.baseId]
        if base then
            base.dispatchPhase = request.phase
            base.dispatchStatus = request.status
            base.dispatchError = request.error
            base.dispatchBefore = request.before
            base.dispatchAfter = request.after
            if request.status == "dispatch_call_failed" or request.status == "dispatch_precondition_failed" then
                base.status = request.status
                base.endedAt = now
            end
        end
    end
end

function Director:start(source, requested_profile, scheduler_token, scheduler_occurrence_key)
    local allowed, reason = native_start_guard(self.bridge)
    if not allowed then return false, reason end
    if scheduler_token ~= self.scheduler_start_token or type(scheduler_occurrence_key) ~= "string" then
        return false, "direct invasion start denied; use a scheduled or manual start"
    end
    local scheduler_occurrence = self.scheduler and self.scheduler.state.occurrences[scheduler_occurrence_key] or nil
    if not scheduler_occurrence or scheduler_occurrence.status ~= "starting" or scheduler_occurrence.profileId ~= requested_profile then
        return false, "scheduler start authorization is invalid"
    end
    local required_warnings = { 600, 300, 60 }
    if scheduler_occurrence.manual then
        local countdown_seconds = scheduler_occurrence.countdownSeconds
        local expected_warnings = Scheduler.manual_warning_seconds(countdown_seconds)
        local schedule = scheduler_occurrence.schedule
        if not expected_warnings or not schedule
            or scheduler_occurrence.intendedAt - scheduler_occurrence.plannedAt ~= countdown_seconds
            or not warning_sets_match(schedule.warningSeconds, expected_warnings) then
            return false, "manual scheduler start authorization is invalid"
        end
        required_warnings = expected_warnings
    end
    for _, seconds in ipairs(required_warnings) do
        if not scheduler_occurrence.warningsSent[tostring(seconds)] then
            return false, "scheduler start authorization lacks a required warning"
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
        schedulerOccurrenceKey = scheduler_occurrence_key,
        startedAt = now,
        startConfirmationDeadline = now + self.config.siegeLeague.startDiscoverySeconds,
        startConfirmedAt = nil,
        confirmedBaseCount = 0,
        fanoutDispatched = false,
        startedAtUtc = util.utc_now(),
        lastLifecycleAt = now,
        bases = {},
        compositions = {},
        timeoutBases = {},
        roster = {},
    }
    self.state.status = "starting"
    self.scoreboard = Scoreboard.new(self:_scoreboard_options(occurrence_id))
    local expected_bases, start_roster, discovery_error = {}, nil, nil
    if self.bridge.begin_event_discovery then
        expected_bases, start_roster, discovery_error = self.bridge:begin_event_discovery(profile_id, occurrence_id)
    end
    if discovery_error then
        if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
        self.state.event = nil
        self.state.status = previous_status
        self.scoreboard = nil
        return false, discovery_error
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
        self:_apply_dispatch_results(start_result)
        if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
        self.state.status = "aborted"
        self.state.event.status = "aborted"
        self.state.event.abortReason = type(start_result) == "table" and start_result.error or start_result
        for _, base in pairs(self.state.event.bases) do
            if base.status == "pending" and base.dispatchStatus == "awaiting_probe_confirmation" then
                base.status = "dispatch_skipped_probe_failed"
                base.dispatchStatus = "dispatch_skipped_probe_failed"
                base.endedAt = now
            end
        end
        self.scoreboard = nil
        local failure_persisted, failure_error = self:_persist("event_start_failed", { occurrenceId = occurrence_id, result = start_result })
        if not failure_persisted then
            self.state.status = "recovery_required"
            self.state.event.status = "recovery_required"
            self.state.event.recoveryReason = "unable to persist selected-base probe failure: " .. tostring(failure_error)
            return false, self.state.event.recoveryReason
        end
        self:_notify("SIEGE LEAGUE - START FAILED", "The selected-base probe call failed before any native invasion could be confirmed: " .. tostring(self.state.event.abortReason))
        return false, self.state.event.abortReason
    end
    self:_apply_dispatch_results(start_result)
    local dispatch_persisted, dispatch_error = self:_persist("event_dispatch_results", {
        occurrenceId = occurrence_id,
        phase = "probe",
        result = start_result,
    })
    if not dispatch_persisted then
        self.state.status = "recovery_required"
        self.state.event.status = "recovery_required"
        return false, "unable to persist selected-base dispatch results: " .. tostring(dispatch_error)
    end
    self.logger:info("Selected-base Siege League probe call returned; awaiting native lifecycle confirmation", {
        occurrence = occurrence_id,
        profile = profile_id,
        expectedBases = util.count(self.state.event.bases),
    })
    return true, occurrence_id, self.state.status == "active"
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
        event.bases[base_id].dispatchStatus = "lifecycle_confirmed"
        event.bases[base_id].startedAt = self.clock()
        event.bases[base_id].ranked = event.profileId == "native" or (event.compositions[base_id] and not event.compositions[base_id].failed)
    elseif event.bases[base_id].status == "active" and event.bases[base_id].groupId == group_id then
        return true
    else
        return false
    end
    local now = self.clock()
    local first_confirmation = event.startConfirmedAt == nil
    event.lastLifecycleAt = now
    event.confirmedBaseCount = (event.confirmedBaseCount or 0) + 1
    if first_confirmation then event.startConfirmedAt = now end
    event.status = "active"
    self.state.status = "active"
    local scheduler_confirmed, scheduler_error = self.scheduler:confirm_start(event.schedulerOccurrenceKey, event.id, now)
    if not scheduler_confirmed then
        event.status = "recovery_required"
        event.recoveryReason = "unable to confirm scheduler start: " .. tostring(scheduler_error)
        self.state.status = "recovery_required"
        self.logger:error("Native invasion started but scheduler confirmation failed", { base = util.mask_uid(base_id), error = scheduler_error })
        return true
    end
    local persisted, persist_error = self:_persist(first_confirmation and "event_start_confirmed" or "event_base_start_confirmed", {
        occurrenceId = event.id,
        base = util.mask_uid(base_id),
        group = util.mask_uid(group_id),
        confirmedBases = event.confirmedBaseCount,
    })
    if not persisted then
        event.status = "recovery_required"
        event.recoveryReason = "unable to persist native start confirmation: " .. tostring(persist_error)
        self.state.status = "recovery_required"
        self.logger:error("Native invasion started but confirmation could not be persisted", { base = util.mask_uid(base_id), error = persist_error })
        return true
    end
    if first_confirmation then
        local notified, notification_error = self:_notify(
            "SIEGE LEAGUE - RAID STARTED",
            bounties.profile(event.profileId).name .. ": A native invasion is confirmed. The remaining eligible online-guild bases will now be requested; move between bases, protect everything, and rack up contribution and final hits!"
        )
        if not notified then
            self.logger:warn("Confirmed raid start notification was incomplete", { error = notification_error })
        end
    end
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

function Director:_fail_unconfirmed_start(reason)
    local event = self.state.event
    if not event or event.startConfirmedAt then return false, "start already confirmed" end
    local now = self.clock()
    for _, base in pairs(event.bases) do
        if base.status == "pending" then
            if base.dispatchStatus == "probe_call_returned" or base.dispatchStatus == "lifecycle_confirmed" then
                base.status = "native_start_missing"
            else
                base.status = "dispatch_skipped_probe_unconfirmed"
            end
            base.endedAt = now
        end
    end
    event.status = "aborted"
    event.abortReason = reason or "no correlated native invasion lifecycle confirmed before start discovery timeout"
    event.endedAt = now
    event.endedAtUtc = util.utc_now()
    event.finalRankings = nil
    event.scoreStats = nil
    self.state.status = "aborted"
    self.scoreboard = nil
    local scheduler_failed, scheduler_error = self.scheduler:fail_start(event.schedulerOccurrenceKey, event.abortReason)
    if not scheduler_failed then
        event.status = "recovery_required"
        event.recoveryReason = "unable to fail scheduler start: " .. tostring(scheduler_error)
        self.state.status = "recovery_required"
        return false, event.recoveryReason
    end
    local persisted, persist_error = self:_persist("event_start_failed", {
        occurrenceId = event.id,
        reason = event.abortReason,
        expectedBases = util.count(event.bases),
        confirmedBases = 0,
    })
    if not persisted then
        event.status = "recovery_required"
        event.recoveryReason = "unable to persist unconfirmed start failure: " .. tostring(persist_error)
        self.state.status = "recovery_required"
        return false, event.recoveryReason
    end
    if self.bridge.end_event_tracking then self.bridge:end_event_tracking() end
    self:_notify(
        "SIEGE LEAGUE - START FAILED",
        "No selected-base native invasion lifecycle was confirmed before the discovery timeout. No Siege League results or rewards were created; review the masked dispatch diagnostics before retrying."
    )
    return true, event.abortReason
end

function Director:_dispatch_confirmed_fanout()
    local allowed, reason = native_start_guard(self.bridge)
    if not allowed then return false, reason end
    local event = self.state.event
    if not event or not event.startConfirmedAt or event.fanoutDispatched then return true end
    event.fanoutIntentAt = self.clock()
    local intent_persisted, intent_error = self:_persist("event_fanout_intent", {
        occurrenceId = event.id,
        confirmedProbe = true,
    })
    if not intent_persisted then
        event.status = "recovery_required"
        event.recoveryReason = "unable to persist fanout intent: " .. tostring(intent_error)
        self.state.status = "recovery_required"
        return false, event.recoveryReason
    end
    local dispatched, result = self.bridge:continue_invasion_dispatch()
    event.fanoutDispatched = true
    event.fanoutDispatchedAt = self.clock()
    event.discoveryDeadline = event.fanoutDispatchedAt + self.config.siegeLeague.startDiscoverySeconds
    if dispatched then
        self:_apply_dispatch_results(result)
    else
        event.fanoutError = tostring(result)
        for _, base in pairs(event.bases) do
            if base.status == "pending" and base.dispatchStatus == "awaiting_probe_confirmation" then
                base.status = "dispatch_call_failed"
                base.dispatchStatus = "dispatch_call_failed"
                base.dispatchError = event.fanoutError
                base.endedAt = self.clock()
            end
        end
    end
    local persisted, persist_error = self:_persist("event_fanout_dispatch_results", {
        occurrenceId = event.id,
        dispatched = dispatched,
        result = result,
    })
    if not persisted then
        event.status = "recovery_required"
        event.recoveryReason = "unable to persist fanout dispatch results: " .. tostring(persist_error)
        self.state.status = "recovery_required"
        return false, event.recoveryReason
    end
    return dispatched, result
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
    local allowed, quarantine_reason = native_start_guard(self.bridge)
    if not allowed then return false, quarantine_reason end
    if self.state.status ~= "active" and self.state.status ~= "starting" and self.state.status ~= "recovery_required" then
        return false, "nothing to resolve"
    end
    local event = self.state.event
    if not event.startConfirmedAt then
        return self:_fail_unconfirmed_start("resolve requested before any native invasion lifecycle was confirmed")
    end
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
    self:_notify("SIEGE LEAGUE - RESULTS", self:leaderboard_text(3))
    return true
end

function Director:abort(reason)
    local allowed, quarantine_reason = native_start_guard(self.bridge)
    if not allowed then return false, quarantine_reason end
    if not self.state.event or self.state.status == "idle" then
        return false, "nothing to abort"
    end
    if not self.state.event.startConfirmedAt then
        local scheduler_failed, scheduler_error = self.scheduler:fail_start(
            self.state.event.schedulerOccurrenceKey,
            "operator aborted before native start confirmation"
        )
        if not scheduler_failed then
            self.state.status = "recovery_required"
            self.state.event.status = "recovery_required"
            self.state.event.recoveryReason = "unable to settle scheduler during abort: " .. tostring(scheduler_error)
            return false, self.state.event.recoveryReason
        end
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
    self:_notify(
        "SIEGE LEAGUE - SCORING STOPPED",
        "Siege League scoring stopped. Native invasions were left to Palworld's normal lifecycle for safety."
    )
    return true
end

function Director:reset()
    local allowed, reason = native_start_guard(self.bridge)
    if not allowed then return false, reason end
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

function Director:_normalize_chat_principal(principal)
    if type(principal) == "string" then
        return {
            transport = "chat",
            uid = principal,
            palworldAdmin = nil,
            palworldAdminReadable = false,
            palworldAdminError = "authoritative Palworld administrator state was not supplied",
        }
    end
    if type(principal) ~= "table" or type(principal.uid) ~= "string" or principal.uid == "" then
        return nil
    end
    return principal
end

function Director:_authorize_chat_command(principal, action)
    principal = self:_normalize_chat_principal(principal)
    if not principal then
        return false, "authoritative chat principal is unavailable"
    end
    local uid = principal.uid
    local configured_operator = config_module.is_operator(self.config, uid)
    local policy = self.config.siegeLeague.chatStartPolicy
    local allowed = false
    local authority
    local denial
    if policy == "anyUser" then
        allowed = true
        if configured_operator then
            authority = "configured-operator"
        elseif principal.palworldAdminReadable == true and principal.palworldAdmin == true then
            authority = "palworld-admin"
        else
            authority = "any-user-policy"
        end
    elseif policy == "operatorOnly" then
        allowed = configured_operator
        authority = allowed and "configured-operator" or nil
        denial = "configured PED operator UID required"
    elseif policy == "palworldAdminOnly" then
        if principal.palworldAdminReadable ~= true then
            denial = "Palworld administrator state is unavailable or ambiguous: " .. tostring(principal.palworldAdminError or "APalPlayerController.bAdmin unavailable")
        elseif principal.palworldAdmin == true then
            allowed = true
            authority = "palworld-admin"
        else
            denial = "authenticated Palworld administrator required"
        end
    elseif policy == "operatorOrPalworldAdmin" then
        if configured_operator then
            allowed = true
            authority = "configured-operator"
        elseif principal.palworldAdminReadable ~= true then
            denial = "Palworld administrator state is unavailable or ambiguous: " .. tostring(principal.palworldAdminError or "APalPlayerController.bAdmin unavailable")
        elseif principal.palworldAdmin == true then
            allowed = true
            authority = "palworld-admin"
        else
            denial = "configured PED operator UID or authenticated Palworld administrator required"
        end
    else
        denial = "configured command authorization policy is unsupported"
    end
    local audit = {
        action = action,
        authority = authority,
        player = util.mask_uid(uid),
        policy = policy,
    }
    if allowed then
        self.logger:info("Privileged chat command authorized", audit)
        return true, nil, authority
    end
    audit.reason = denial
    self.logger:warn("Privileged chat command denied", audit)
    return false, denial
end

function Director:_handle_chat_start(principal, requested_profile, countdown_minutes, now)
    local uid = principal.uid
    local authorized, denial, authority = self:_authorize_chat_command(principal, "start")
    if not authorized then
        self:_chat("Siege League start denied: " .. tostring(denial) .. ".", uid)
        return true
    end
    local ordinary_user = authority == "any-user-policy"
    if ordinary_user then
        local last_start = self.state.lastUserStartAt or 0
        local remaining = last_start > 0 and (self.config.siegeLeague.userStartCooldownSeconds - (now - last_start)) or 0
        if remaining > 0 then
            self:_chat("Siege League user-start cooldown: " .. math.ceil(remaining / 60) .. " minute(s) remaining.", uid)
            return true
        end
    end
    if now - self.last_start_attempt < 10 then
        self:_chat("Siege League start requests are temporarily rate-limited.", uid)
        return true
    end
    self.last_start_attempt = now
    local profile_id, profile_error = self:_profile_allowed(requested_profile)
    if not profile_id then
        self:_chat("Siege League start failed: " .. tostring(profile_error), uid)
        return true
    end
    if self.state.status ~= "idle" and self.state.status ~= "completed" and self.state.status ~= "aborted" then
        self:_chat("Siege League start failed: director is " .. self.state.status, uid)
        return true
    end
    local previous_user_start = self.state.lastUserStartAt or 0
    if ordinary_user then
        self.state.lastUserStartAt = now
        local persisted, persist_error = self:_persist("user_start_cooldown_intent", {
            playerUid = util.mask_uid(uid),
            profileId = profile_id,
        })
        if not persisted then
            self.state.lastUserStartAt = previous_user_start
            self:_chat("Siege League start failed: unable to persist user cooldown: " .. tostring(persist_error), uid)
            return true
        end
    end
    local ok, result = self:arm_start("chat:" .. util.mask_uid(uid), profile_id, countdown_minutes)
    if not ok and ordinary_user then
        self.state.lastUserStartAt = previous_user_start
        local rollback_ok = self:_persist("user_start_cooldown_rollback", {
            playerUid = util.mask_uid(uid),
            reason = tostring(result),
        })
        if not rollback_ok then self.state.status = "recovery_required" end
    end
    if not ok then self:_chat("Siege League start failed: " .. tostring(result), uid) end
    return true
end

function Director:handle_chat(principal, message)
    if not native_start_guard(self.bridge) then return false end
    principal = self:_normalize_chat_principal(principal)
    if not principal then return false end
    local uid = principal.uid
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
    self.command_times[uid] = now
    if words[1] == "!siege" then
        local action = words[2] or "status"
        if action == "status" then
            self:_chat(self:status_text(), uid)
            return true
        elseif action == "profiles" then
            self:_chat(self:profiles_text(), uid)
            return true
        elseif action == "schedule" then
            self:_chat(self:schedule_text(), uid)
            return true
        elseif action == "score" then
            self:_chat(self:player_text(uid), uid)
            return true
        elseif action == "leaderboard" then
            self:_chat(self:leaderboard_text(), uid)
            return true
        elseif action == "start" then
            return self:_handle_chat_start(principal, words[3], words[4], now)
        elseif action == "cancel" or action == "resolve" or action == "abort" or action == "reset" then
            self:handle_operator_command(action, "chat:" .. util.mask_uid(uid), principal)
            return true
        end
        self:_chat("Siege commands: !siege status|profiles|schedule|score|leaderboard|start <profile> [0-60 minutes].", uid)
        return true
    elseif lowered == "!event" then
        self:_chat(self:status_text(), uid)
        return true
    elseif lowered == "!score" then
        self:_chat(self:player_text(uid), uid)
        return true
    elseif lowered == "!leaderboard" then
        self:_chat(self:leaderboard_text(), uid)
        return true
    elseif util.starts_with(lowered, "!ped ") then
        if words[2] == "start" then
            return self:_handle_chat_start(principal, words[3], words[4], now)
        end
        self:handle_operator_command(message:sub(6), "chat:" .. util.mask_uid(uid), principal)
        return true
    end
    return false
end

function Director:handle_operator_command(command, source, principal)
    local words = util.split_words(command)
    local action = (words[1] or "status"):lower()
    if action == "diagnose-preflight" then
        if source ~= "console" then return false, "diagnose-preflight is server-console-only" end
        if #words > 3 or (#words > 1 and #words ~= 3) then return false, "use diagnose-preflight, then diagnose-preflight confirm-disposable-readonly <expected-step>" end
        if type(self.bridge.diagnose_preflight) ~= "function" then return false, "preflight diagnostic is unavailable" end
        return self.bridge:diagnose_preflight(words[2], words[3])
    end
    local allowed, quarantine_reason = native_start_guard(self.bridge)
    if not allowed then
        if action == "status" and source == "console" then
            return true, quarantine_reason .. " " .. self:status_text()
        end
        return false, quarantine_reason
    end
    if source and source:match("^chat:") then
        local authorized, denial = self:_authorize_chat_command(principal, action)
        if not authorized then
            self:_chat("PED ERROR: command denied: " .. tostring(denial) .. ".", principal and principal.uid)
            return false, denial
        end
    end
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
    elseif action == "diagnose-native-all" then
        if source ~= "console" then
            ok, result = false, "diagnose-native-all is server-console-only"
        elseif type(self.bridge.diagnose_native_start_all) ~= "function" then
            ok, result = false, "native all-base diagnostic is unavailable"
        else
            ok, result = self.bridge:diagnose_native_start_all(words[2])
        end
    elseif action == "rewards" then
        if not self.config.capabilities.grantItems then
            ok, result = false, "capabilities.grantItems is disabled"
        else
            local count = self.rewards:process(self.bridge, 32, function() return self:_checkpoint("reward") end)
            ok, result = true, "processed " .. count .. " pending reward obligations"
        end
    else
        ok, result = false, "unknown command; use start [profile] [minutes], cancel, status, profiles, schedule, leaderboard, resolve, abort, reset, diagnose-native-all, or rewards"
    end
    if source and source:match("^chat:") then
        self:_chat((ok and "PED: " or "PED ERROR: ") .. tostring(result or "ok"), principal and principal.uid)
    end
    return ok, result
end

function Director:tick()
    if not native_start_guard(self.bridge) then return end
    local now = self.clock()
    if self.scheduler then self.scheduler:tick(now) end
    local event = self:_active_event()
    if event then
        self:reconcile_online_players()
        if not event.startConfirmedAt and now >= event.startConfirmationDeadline then
            self:_fail_unconfirmed_start("no correlated native invasion lifecycle confirmed before start discovery timeout")
            event = nil
        elseif event.startConfirmedAt and not event.fanoutDispatched then
            self:_dispatch_confirmed_fanout()
            event = self:_active_event()
        end
    end
    if event then
        local discovery_deadline = event.discoveryDeadline or event.startConfirmationDeadline
        if not event.discoveryClosed and event.fanoutDispatched and now >= discovery_deadline then
            if self.bridge.close_event_discovery then self.bridge:close_event_discovery() end
            event.discoveryClosed = true
            self:_mark_dirty()
        end
        if now - event.startedAt >= self.config.siegeLeague.maxRuntimeSeconds then
            self:resolve("maximum runtime")
        elseif event.fanoutDispatched and now >= discovery_deadline then
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
                if (event.confirmedBaseCount or 0) > 0 then
                    self:resolve("all expected bases classified")
                else
                    self:_fail_unconfirmed_start("all selected-base calls completed without a correlated native lifecycle")
                end
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
