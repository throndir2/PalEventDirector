local util = require("ped.util")

local Scheduler = {}
Scheduler.__index = Scheduler

local WEEKDAYS = {
    SUN = 1,
    MON = 2,
    TUE = 3,
    WED = 4,
    THU = 5,
    FRI = 6,
    SAT = 7,
}

local TERMINAL_STATUS = {
    blocked = true,
    cancelled = true,
    failed = true,
    missed = true,
    recovery_required = true,
    started = true,
}

local function local_date(now)
    local date = os.date("*t", now)
    date.isdst = nil
    return date
end

local function date_key(date)
    return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
end

local function occurrence_key(schedule, intended_at)
    return schedule.id .. "@" .. tostring(intended_at)
end

function Scheduler.new(options, restored_state)
    options = options or {}
    local state = restored_state or {
        schemaVersion = 2,
        occurrences = {},
        manualNonce = 0,
    }
    if state.schemaVersion ~= 2 then
        error("unsupported scheduler state schema")
    end
    for _, occurrence in pairs(state.occurrences or {}) do
        if occurrence.status == "starting" then
            occurrence.status = "recovery_required"
            occurrence.reason = "server_restarted_during_start"
        end
    end
    return setmetatable({
        schedules = options.schedules or {},
        clock = options.clock or util.now_seconds,
        persist = options.persist or function() return true end,
        announce = options.announce or function() return true end,
        start_event = options.start_event or function() return false, "start unavailable" end,
        can_start = options.can_start or function() return true end,
        start_token = options.start_token,
        warning_grace_seconds = options.warning_grace_seconds or 10,
        max_terminal_history = options.max_terminal_history or 256,
        state = state,
    }, Scheduler)
end

function Scheduler:to_state()
    return self.state
end

local function matches_weekday(schedule, date)
    if schedule.frequency ~= "weekly" then
        return true
    end
    local expected = WEEKDAYS[schedule.dayOfWeek]
    return expected ~= nil and date.wday == expected
end

function Scheduler:_candidate_for_date(schedule, date)
    if not schedule.enabled or not matches_weekday(schedule, date) then
        return nil
    end
    local candidate = {
        year = date.year,
        month = date.month,
        day = date.day,
        hour = schedule.hour,
        min = schedule.minute,
        sec = 0,
        isdst = nil,
    }
    local timestamp = os.time(candidate)
    local normalized = local_date(timestamp)
    if normalized.year ~= candidate.year or normalized.month ~= candidate.month or normalized.day ~= candidate.day
        or normalized.hour ~= candidate.hour or normalized.min ~= candidate.min then
        return nil
    end
    return timestamp
end

function Scheduler:next_occurrence(schedule, now)
    now = now or self.clock()
    local date = local_date(now)
    for day_offset = 0, 8 do
        local probe_time = os.time({
            year = date.year,
            month = date.month,
            day = date.day + day_offset,
            hour = 12,
            min = 0,
            sec = 0,
            isdst = nil,
        })
        local probe_date = local_date(probe_time)
        local candidate = self:_candidate_for_date(schedule, probe_date)
        if candidate and candidate >= now then
            return candidate
        end
    end
    return nil
end

function Scheduler:_materialize(schedule, intended_at)
    local key = occurrence_key(schedule, intended_at)
    local occurrence = self.state.occurrences[key]
    if occurrence then
        return occurrence
    end
    occurrence = {
        key = key,
        scheduleId = schedule.id,
        profileId = schedule.profile,
        intendedAt = intended_at,
        intendedLocalDate = date_key(local_date(intended_at)),
        warningsSent = {},
        warningAttempts = {},
        status = "planned",
        plannedAt = self.clock(),
        schedule = util.deep_copy(schedule),
    }
    self.state.occurrences[key] = occurrence
    local persisted, persist_error = self.persist("schedule_occurrence_planned", occurrence)
    if not persisted then
        self.state.occurrences[key] = nil
        return nil, persist_error
    end
    return occurrence
end

function Scheduler:arm_manual(profile, source, countdown_seconds, name)
    countdown_seconds = countdown_seconds or 600
    if not util.is_integer(countdown_seconds) or countdown_seconds < 600 or countdown_seconds > 3600 then
        return false, "manual countdown must be from 10 through 60 minutes"
    end
    for _, occurrence in pairs(self.state.occurrences) do
        if occurrence.manual and occurrence.status == "planned" then
            return false, "a manual Siege League countdown is already armed"
        end
    end
    self.state.manualNonce = (self.state.manualNonce or 0) + 1
    local now = self.clock()
    local schedule = {
        id = "manual-" .. self.state.manualNonce,
        name = name or profile,
        enabled = true,
        frequency = "manual",
        profile = profile,
        warningSeconds = { 600, 300, 60 },
        lateStartToleranceSeconds = 60,
    }
    local intended = now + countdown_seconds
    local occurrence = {
        key = occurrence_key(schedule, intended),
        scheduleId = schedule.id,
        profileId = profile,
        intendedAt = intended,
        intendedLocalDate = date_key(local_date(intended)),
        warningsSent = {},
        warningAttempts = {},
        status = "planned",
        plannedAt = now,
        manual = true,
        source = source,
        schedule = util.deep_copy(schedule),
    }
    self.state.occurrences[occurrence.key] = occurrence
    if not self.persist("manual_countdown_armed", occurrence) then
        self.state.occurrences[occurrence.key] = nil
        return false, "unable to persist manual countdown"
    end
    if countdown_seconds == 600 then
        local warned, warning_error = self:_emit_warning(schedule, occurrence, 600)
        if not warned then
            occurrence.status = "recovery_required"
            occurrence.reason = "initial_warning_failed: " .. tostring(warning_error)
            self.persist("manual_countdown_recovery_required", occurrence)
            return false, warning_error
        end
    end
    return true, occurrence
end

function Scheduler:cancel_manual(reason)
    for _, occurrence in pairs(self.state.occurrences) do
        if occurrence.manual and occurrence.status == "planned" then
            local previous_reason = occurrence.reason
            occurrence.status = "cancelled"
            occurrence.reason = reason or "operator"
            local persisted, persist_error = self.persist("manual_countdown_cancelled", occurrence)
            if not persisted then
                occurrence.status = "planned"
                occurrence.reason = previous_reason
                return false, persist_error
            end
            return true, occurrence.key
        end
    end
    return false, "no manual countdown is armed"
end

function Scheduler:_warning_message(schedule, seconds)
    local minutes = math.floor(seconds / 60)
    local unit = minutes == 1 and "minute" or "minutes"
    return string.format("SIEGE LEAGUE - %s begins in %d %s. Only bases belonging to guilds with an online member at start will be attacked.", schedule.name or schedule.profile, minutes, unit)
end

function Scheduler:_emit_warning(schedule, occurrence, seconds)
    local key = tostring(seconds)
    if occurrence.warningsSent[key] then
        return true
    end
    occurrence.warningAttempts = occurrence.warningAttempts or {}
    occurrence.warningAttempts[key] = (occurrence.warningAttempts[key] or 0) + 1
    if not self.persist("schedule_warning_intent", {
        occurrenceKey = occurrence.key,
        seconds = seconds,
        attempt = occurrence.warningAttempts[key],
    }) then
        return false, "unable to persist warning intent"
    end
    local announced, announce_error = self.announce(self:_warning_message(schedule, seconds))
    if not announced then
        occurrence.lastWarningError = tostring(announce_error or "announcement unavailable")
        return false, occurrence.lastWarningError
    end
    occurrence.warningsSent[key] = true
    occurrence.lastWarningError = nil
    occurrence.warningSentAt = occurrence.warningSentAt or {}
    occurrence.warningSentAt[key] = self.clock()
    local persisted, persist_error = self.persist("schedule_warning_sent", {
        occurrenceKey = occurrence.key,
        seconds = seconds,
    })
    if not persisted then
        occurrence.warningsSent[key] = nil
        occurrence.warningSentAt[key] = nil
        return false, persist_error
    end
    return true
end

function Scheduler:_mark_terminal(occurrence, status, reason, kind)
    local previous_status = occurrence.status
    local previous_reason = occurrence.reason
    occurrence.status = status
    occurrence.reason = reason
    local persisted, persist_error = self.persist(kind, occurrence)
    if not persisted then
        occurrence.status = previous_status
        occurrence.reason = previous_reason
        return false, persist_error
    end
    return true
end

function Scheduler:_start(schedule, occurrence, now)
    if occurrence.status ~= "planned" then
        return
    end
    local late_by = now - occurrence.intendedAt
    if late_by > (schedule.lateStartToleranceSeconds or 0) then
        self:_mark_terminal(occurrence, "missed", "late_tolerance_exceeded", "schedule_occurrence_missed")
        return
    end
    local can_start, reason = self.can_start()
    if not can_start then
        self:_mark_terminal(occurrence, "blocked", reason, "schedule_occurrence_blocked")
        return
    end
    occurrence.status = "starting"
    if not self.persist("schedule_start_intent", occurrence) then
        occurrence.status = "recovery_required"
        occurrence.reason = "unable_to_persist_start_intent"
        return
    end
    local started, result = self.start_event("schedule:" .. schedule.id, schedule.profile, self.start_token, occurrence.key)
    if started then
        occurrence.status = "started"
        occurrence.occurrenceId = result
        occurrence.startedAt = now
        if not self.persist("schedule_started", occurrence) then
            occurrence.status = "recovery_required"
            occurrence.reason = "unable_to_persist_start_result"
        end
    else
        occurrence.status = "failed"
        occurrence.reason = tostring(result)
        if not self.persist("schedule_start_failed", occurrence) then
            occurrence.status = "recovery_required"
            occurrence.reason = "unable_to_persist_start_failure"
        end
    end
end

function Scheduler:_process(schedule, occurrence, now)
    if occurrence.status ~= "planned" then return end
    local warning_seconds = util.deep_copy(schedule.warningSeconds or {})
    table.sort(warning_seconds, function(left, right) return left > right end)
    for _, seconds in ipairs(warning_seconds) do
        local warning_key = tostring(seconds)
        local warning_at = occurrence.intendedAt - seconds
        if not occurrence.warningsSent[warning_key] and now >= warning_at then
            if now > warning_at + self.warning_grace_seconds then
                self:_mark_terminal(occurrence, "missed", "mandatory_warning_missed_" .. warning_key, "schedule_occurrence_missed")
                return
            end
            local warned = self:_emit_warning(schedule, occurrence, seconds)
            if not warned then return end
        end
    end
    if now >= occurrence.intendedAt then
        self:_start(schedule, occurrence, now)
    end
end

function Scheduler:tick(now)
    now = now or self.clock()
    for _, schedule in ipairs(self.schedules) do
        if schedule.enabled then
            local intended = self:next_occurrence(schedule, now)
            if intended then
                self:_materialize(schedule, intended)
            end
        end
    end
    for _, occurrence in pairs(self.state.occurrences) do
        if occurrence.status == "planned" and occurrence.schedule then
            self:_process(occurrence.schedule, occurrence, now)
        end
    end
    local terminal = {}
    for key, occurrence in pairs(self.state.occurrences) do
        if TERMINAL_STATUS[occurrence.status] then
            terminal[#terminal + 1] = { key = key, intendedAt = occurrence.intendedAt or 0 }
        end
    end
    if #terminal > self.max_terminal_history then
        table.sort(terminal, function(left, right)
            if left.intendedAt ~= right.intendedAt then return left.intendedAt < right.intendedAt end
            return left.key < right.key
        end)
        local removed = {}
        for index = 1, #terminal - self.max_terminal_history do
            local key = terminal[index].key
            removed[key] = self.state.occurrences[key]
            self.state.occurrences[key] = nil
        end
        local persisted = self.persist("schedule_history_pruned", { removed = #terminal - self.max_terminal_history })
        if not persisted then
            for key, occurrence in pairs(removed) do self.state.occurrences[key] = occurrence end
        end
    end
end

function Scheduler:upcoming(limit, now)
    now = now or self.clock()
    local result = {}
    local included = {}
    for _, occurrence in pairs(self.state.occurrences) do
        if occurrence.status == "planned" and occurrence.intendedAt >= now then
            result[#result + 1] = {
                id = occurrence.scheduleId,
                name = occurrence.schedule and occurrence.schedule.name or "Siege League",
                profile = occurrence.profileId,
                intendedAt = occurrence.intendedAt,
                localTime = os.date("%Y-%m-%d %H:%M %Z", occurrence.intendedAt),
            }
            included[occurrence.key] = true
        end
    end
    for _, schedule in ipairs(self.schedules) do
        if schedule.enabled then
            local intended = self:next_occurrence(schedule, now)
            if intended and not included[occurrence_key(schedule, intended)] then
                result[#result + 1] = {
                    id = schedule.id,
                    name = schedule.name,
                    profile = schedule.profile,
                    intendedAt = intended,
                    localTime = os.date("%Y-%m-%d %H:%M %Z", intended),
                }
            end
        end
    end
    table.sort(result, function(left, right) return left.intendedAt < right.intendedAt end)
    while limit and #result > limit do table.remove(result) end
    return result
end

return Scheduler
