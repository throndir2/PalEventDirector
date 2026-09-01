local json = require("ped.json")
local util = require("ped.util")

local M = {}

function M.defaults()
    return {
        schemaVersion = 1,
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
        require_integer(config.schemaVersion, "schemaVersion", 1, 1)
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
        require_integer(config.runtime.pollIntervalMs, "runtime.pollIntervalMs", 250, 60000)
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
            error("grantItems is not available in alpha.1; scoring and reward obligations are implemented, but live delivery requires journal replay validation")
        end
        if config.capabilities.startAllInvasions and (not config.capabilities.observeCombat or not config.capabilities.observeInvasions) then
            error("startAllInvasions requires observeCombat and observeInvasions")
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
