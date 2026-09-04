local json = require("ped.json")
local bounties = require("ped.bounties")
local util = require("ped.util")

local M = {}

function M.defaults()
    return {
        schemaVersion = 3,
        mode = "laboratory",
        compatibility = {
            requiredAdapter = "palworld-1.0.3-lab",
            allowedServerBuildIds = json.array({ "24575149" }),
            allowedUe4ssVersions = json.array(),
        },
        runtime = {
            pollIntervalMs = 1000,
            checkpointIntervalSeconds = 5,
            logLevel = "info",
        },
        capabilities = {
            observeCombat = false,
            observeInvasions = false,
            chatCommands = false,
            startAllInvasions = false,
            substituteBountyMembers = false,
            grantItems = false,
        },
        diagnostics = {
            traceHooks = false,
            observationProbe = false,
        },
        limits = {
            maxBases = 64,
            maxTargets = 512,
            maxPlayers = 128,
            maxDamageRecords = 100000,
            maxAnnouncementLength = 500,
        },
        siegeLeague = {
            name = "Siege League",
            defaultProfile = "all-bounty",
            allowedProfiles = json.array(bounties.profile_ids()),
            chatStartPolicy = "operatorOrPalworldAdmin",
            userStartCooldownSeconds = 3600,
            manualCountdownMinutes = 10,
            allowCrossBaseRoaming = true,
            targetPoints = 1000,
            minimumParticipationPoints = 100,
            leaderboardSize = 10,
            startDiscoverySeconds = 60,
            settleDelaySeconds = 15,
            maxRuntimeSeconds = 1800,
            creditDirectPlayer = true,
            creditActivePal = true,
            creditBaseWorkers = false,
        },
        schedules = json.array({
            {
                id = "weekly-all-bounty",
                name = "Weekly All-Bounty Alarm",
                enabled = false,
                frequency = "weekly",
                dayOfWeek = "SAT",
                hour = 19,
                minute = 0,
                profile = "all-bounty",
                warningSeconds = json.array({ 600, 300, 60 }),
                lateStartToleranceSeconds = 60,
            },
        }),
        rewards = {
            allowedItemIds = json.array({ "BountyProof_1" }),
            participation = {
                enabled = true,
                itemId = "BountyProof_1",
                count = 1,
            },
            baseCompletion = {
                enabled = true,
                itemId = "BountyProof_1",
                count = 1,
                maxPerPlayer = 8,
            },
            podium = json.array({
                { rank = 1, itemId = "BountyProof_1", count = 5 },
                { rank = 2, itemId = "BountyProof_1", count = 3 },
                { rank = 3, itemId = "BountyProof_1", count = 2 },
            }),
        },
        operatorUids = json.array(),
    }
end

local function require_boolean(value, name)
    if type(value) ~= "boolean" then
        error(name .. " must be a boolean")
    end
end

local function require_integer(value, name, minimum, maximum)
    if not util.is_integer(value) or value < minimum or value > maximum then
        error(string.format("%s must be an integer from %d through %d", name, minimum, maximum))
    end
end

local function validate_reward(reward, name)
    if type(reward) ~= "table" then
        error(name .. " must be an object")
    end
    if reward.enabled ~= nil then
        require_boolean(reward.enabled, name .. ".enabled")
    end
    if type(reward.itemId) ~= "string" or not reward.itemId:match("^[A-Za-z0-9_]+$") then
        error(name .. ".itemId must be an existing alphanumeric/underscore item ID")
    end
    require_integer(reward.count, name .. ".count", 1, 1000)
end

function M.validate(config)
    if type(config) ~= "table" then
        return false, "configuration root must be an object"
    end
    local ok, message = pcall(function()
        require_integer(config.schemaVersion, "schemaVersion", 3, 3)
        if config.mode ~= "laboratory" and config.mode ~= "production" then
            error("mode must be 'laboratory' or 'production'")
        end
        if type(config.compatibility.requiredAdapter) ~= "string" or config.compatibility.requiredAdapter == "" then
            error("compatibility.requiredAdapter is required")
        end
        for index, build_id in ipairs(config.compatibility.allowedServerBuildIds or {}) do
            if type(build_id) ~= "string" or not build_id:match("^%d+$") then
                error("compatibility.allowedServerBuildIds[" .. index .. "] must be numeric text")
            end
        end
        for index, runtime_version in ipairs(config.compatibility.allowedUe4ssVersions or {}) do
            if type(runtime_version) ~= "string" or not runtime_version:match("^%d+%.%d+%.%d+$") then
                error("compatibility.allowedUe4ssVersions[" .. index .. "] is invalid")
            end
        end
        require_integer(config.runtime.pollIntervalMs, "runtime.pollIntervalMs", 250, 5000)
        require_integer(config.runtime.checkpointIntervalSeconds, "runtime.checkpointIntervalSeconds", 1, 300)
        if not ({ debug = true, info = true, warn = true, error = true })[config.runtime.logLevel] then
            error("runtime.logLevel is invalid")
        end
        for name, value in pairs(config.capabilities) do
            require_boolean(value, "capabilities." .. name)
        end
        require_boolean(config.diagnostics.traceHooks, "diagnostics.traceHooks")
        require_boolean(config.diagnostics.observationProbe, "diagnostics.observationProbe")
        if config.capabilities.grantItems then
            error("grantItems is not available in alpha.3; scoring and reward obligations are implemented, but live delivery requires journal replay validation")
        end
        if config.capabilities.startAllInvasions and (not config.capabilities.observeCombat or not config.capabilities.observeInvasions) then
            error("startAllInvasions requires observeCombat and observeInvasions")
        end
        if config.capabilities.startAllInvasions and #(config.compatibility.allowedServerBuildIds or {}) < 1 then
            error("startAllInvasions requires at least one allowedServerBuildIds entry")
        end
        if config.capabilities.startAllInvasions and #(config.compatibility.allowedUe4ssVersions or {}) < 1 then
            error("startAllInvasions requires at least one allowedUe4ssVersions entry")
        end
        if not ({
            operatorOnly = true,
            palworldAdminOnly = true,
            operatorOrPalworldAdmin = true,
            anyUser = true,
        })[config.siegeLeague.chatStartPolicy] then
            error("siegeLeague.chatStartPolicy must be 'operatorOnly', 'palworldAdminOnly', 'operatorOrPalworldAdmin', or 'anyUser'")
        end
        require_integer(config.siegeLeague.userStartCooldownSeconds, "siegeLeague.userStartCooldownSeconds", 60, 604800)
        require_integer(config.siegeLeague.manualCountdownMinutes, "siegeLeague.manualCountdownMinutes", 0, 60)
        local allowed_profiles = {}
        for index, profile_id in ipairs(config.siegeLeague.allowedProfiles or {}) do
            local normalized = bounties.normalize_profile_id(profile_id)
            if not normalized or normalized ~= profile_id then
                error("siegeLeague.allowedProfiles[" .. index .. "] is not a canonical built-in profile ID")
            end
            if allowed_profiles[profile_id] then
                error("duplicate allowed profile " .. profile_id)
            end
            allowed_profiles[profile_id] = true
        end
        if not allowed_profiles[config.siegeLeague.defaultProfile] then
            error("siegeLeague.defaultProfile must be present in allowedProfiles")
        end
        for profile_id in pairs(allowed_profiles) do
            if profile_id ~= "native" and not config.capabilities.substituteBountyMembers and config.capabilities.startAllInvasions then
                error("non-native allowed profiles require substituteBountyMembers when startAllInvasions is enabled")
            end
        end
        require_integer(config.limits.maxBases, "limits.maxBases", 1, 256)
        require_integer(config.limits.maxTargets, "limits.maxTargets", 1, 4096)
        require_integer(config.limits.maxPlayers, "limits.maxPlayers", 1, 1024)
        require_integer(config.limits.maxDamageRecords, "limits.maxDamageRecords", 100, 1000000)
        require_integer(config.limits.maxAnnouncementLength, "limits.maxAnnouncementLength", 40, 1000)
        require_boolean(config.siegeLeague.allowCrossBaseRoaming, "siegeLeague.allowCrossBaseRoaming")
        if not config.siegeLeague.allowCrossBaseRoaming then
            error("this release requires cross-base roaming; disable the event instead of changing its scoring contract")
        end
        require_integer(config.siegeLeague.targetPoints, "siegeLeague.targetPoints", 1, 1000000)
        require_integer(config.siegeLeague.minimumParticipationPoints, "siegeLeague.minimumParticipationPoints", 0, config.siegeLeague.targetPoints * config.limits.maxTargets)
        require_integer(config.siegeLeague.leaderboardSize, "siegeLeague.leaderboardSize", 1, 50)
        require_integer(config.siegeLeague.startDiscoverySeconds, "siegeLeague.startDiscoverySeconds", 5, 600)
        require_integer(config.siegeLeague.settleDelaySeconds, "siegeLeague.settleDelaySeconds", 1, 300)
        require_integer(config.siegeLeague.maxRuntimeSeconds, "siegeLeague.maxRuntimeSeconds", 60, 21600)
        require_boolean(config.siegeLeague.creditDirectPlayer, "siegeLeague.creditDirectPlayer")
        require_boolean(config.siegeLeague.creditActivePal, "siegeLeague.creditActivePal")
        require_boolean(config.siegeLeague.creditBaseWorkers, "siegeLeague.creditBaseWorkers")
        local schedule_ids = {}
        local weekdays = { SUN = true, MON = true, TUE = true, WED = true, THU = true, FRI = true, SAT = true }
        for index, schedule in ipairs(config.schedules or {}) do
            local prefix = "schedules[" .. index .. "]"
            if type(schedule.id) ~= "string" or not schedule.id:match("^[a-z0-9][a-z0-9%-%.]*$") then error(prefix .. ".id is invalid") end
            if schedule_ids[schedule.id] then error("duplicate schedule id " .. schedule.id) end
            schedule_ids[schedule.id] = true
            if type(schedule.name) ~= "string" or util.trim(schedule.name) == "" or #schedule.name > 120 then error(prefix .. ".name is invalid") end
            require_boolean(schedule.enabled, prefix .. ".enabled")
            if schedule.enabled and not config.capabilities.startAllInvasions then error(prefix .. " requires startAllInvasions") end
            if schedule.frequency ~= "daily" and schedule.frequency ~= "weekly" then error(prefix .. ".frequency must be daily or weekly") end
            if schedule.frequency == "weekly" and not weekdays[schedule.dayOfWeek] then error(prefix .. ".dayOfWeek is invalid") end
            require_integer(schedule.hour, prefix .. ".hour", 0, 23)
            require_integer(schedule.minute, prefix .. ".minute", 0, 59)
            if not allowed_profiles[schedule.profile] then error(prefix .. ".profile is not enabled") end
            if schedule.enabled and schedule.profile ~= "native" and not config.capabilities.substituteBountyMembers then
                error(prefix .. " requires substituteBountyMembers")
            end
            require_integer(schedule.lateStartToleranceSeconds, prefix .. ".lateStartToleranceSeconds", 0, 600)
            local warnings = {}
            for warning_index, seconds in ipairs(schedule.warningSeconds or {}) do
                require_integer(seconds, prefix .. ".warningSeconds[" .. warning_index .. "]", 1, 86400)
                warnings[seconds] = true
            end
            if not warnings[600] or not warnings[300] or not warnings[60] then
                error(prefix .. ".warningSeconds must include 600, 300, and 60")
            end
        end
        validate_reward(config.rewards.participation, "rewards.participation")
        validate_reward(config.rewards.baseCompletion, "rewards.baseCompletion")
        require_integer(config.rewards.baseCompletion.maxPerPlayer, "rewards.baseCompletion.maxPerPlayer", 1, config.limits.maxBases)
        local allowed_items = {}
        for index, item_id in ipairs(config.rewards.allowedItemIds or {}) do
            if type(item_id) ~= "string" or not item_id:match("^[A-Za-z0-9_]+$") then
                error("rewards.allowedItemIds[" .. index .. "] is invalid")
            end
            allowed_items[item_id] = true
        end
        if not allowed_items[config.rewards.participation.itemId] or not allowed_items[config.rewards.baseCompletion.itemId] then
            error("all configured reward items must be explicitly allowlisted")
        end
        local ranks = {}
        for index, reward in ipairs(config.rewards.podium or {}) do
            validate_reward(reward, "rewards.podium[" .. index .. "]")
            require_integer(reward.rank, "rewards.podium[" .. index .. "].rank", 1, 3)
            if ranks[reward.rank] then
                error("duplicate podium reward rank " .. reward.rank)
            end
            ranks[reward.rank] = true
            if not allowed_items[reward.itemId] then
                error("rewards.podium[" .. index .. "].itemId is not allowlisted")
            end
        end
        for index, uid in ipairs(config.operatorUids or {}) do
            if type(uid) ~= "string" or #uid < 8 or #uid > 64 or not uid:match("^[%x%-]+$") then
                error("operatorUids[" .. index .. "] must be a GUID string")
            end
        end
    end)
    return ok, ok and nil or tostring(message)
end

function M.diagnostic_session(config)
    -- In-memory safety overlay; never discard or rewrite the operator's existing config.
    local effective = util.deep_copy(config)
    for name in pairs(effective.capabilities) do effective.capabilities[name] = false end
    for _, schedule in ipairs(effective.schedules) do schedule.enabled = false end
    effective.diagnostics.traceHooks = false
    effective.diagnostics.observationProbe = false
    return effective
end

function M.load(file_path, logger)
    local defaults = M.defaults()
    local file = io.open(file_path, "rb")
    if not file then
        local output = assert(io.open(file_path, "wb"))
        output:write(json.encode(defaults), "\n")
        output:close()
        if logger then
            logger:warn("Created safe default configuration; invasion starts and item grants remain disabled", { path = file_path })
        end
        return defaults, true
    end
    local text = file:read("*a")
    file:close()
    local ok, decoded = pcall(json.decode, text)
    if not ok then
        return nil, false, "configuration JSON is invalid: " .. tostring(decoded)
    end
    local config = util.deep_merge(defaults, decoded)
    local valid, validation_error = M.validate(config)
    if not valid then
        return nil, false, validation_error
    end
    return config, false
end

function M.is_operator(config, uid)
    uid = tostring(uid or ""):lower():gsub("[^%x]", "")
    for _, configured_uid in ipairs(config.operatorUids or {}) do
        if configured_uid:lower():gsub("[^%x]", "") == uid then
            return true
        end
    end
    return false
end

return M
