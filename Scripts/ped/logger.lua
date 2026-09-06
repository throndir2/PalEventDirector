local util = require("ped.util")
local json = require("ped.json")
local filesystem = require("ped.filesystem")
local NativeExperiments = require("ped.native_experiments")

local Logger = {}
Logger.__index = Logger

local LEVELS = { debug = 10, info = 20, warn = 30, error = 40 }

function Logger.new(options)
    options = options or {}
    return setmetatable({
        level = LEVELS[options.level] or LEVELS.info,
        file_path = options.file_path,
        breadcrumb_file_path = options.breadcrumb_file_path,
        experiment_file_path = options.experiment_file_path,
        filesystem = options.filesystem or filesystem,
        prefix = options.prefix or "PalEventDirector",
    }, Logger)
end

function Logger:native_experiment(record)
    if type(self.experiment_file_path) ~= "string" or not NativeExperiments.validate_record(record) then
        return false, "Native experiment record is unavailable or invalid"
    end
    return self.filesystem.append(self.experiment_file_path, json.encode(record) .. "\n")
end

function Logger:write(level, message, fields)
    if (LEVELS[level] or 100) < self.level then
        return
    end
    local suffix = ""
    if fields then
        local parts = {}
        for _, key in ipairs(util.sorted_keys(fields)) do
            parts[#parts + 1] = tostring(key) .. "=" .. util.sanitize_text(fields[key], 160)
        end
        if #parts > 0 then
            suffix = " " .. table.concat(parts, " ")
        end
    end
    local line = string.format("[%s] [%s] [%s] %s%s", util.utc_now(), self.prefix, level:upper(), util.sanitize_text(message, 1000), suffix)
    print(line .. "\n")
    if self.file_path then
        local file = io.open(self.file_path, "ab")
        if file then
            file:write(line, "\n")
            file:close()
        end
    end
end

function Logger:preflight_breadcrumb(step, build_id, object_valid)
    -- Never stringify a native object/error or serialize a returned settings struct.
    if type(step) ~= "string" or not step:match("^%d+%-%d+%-[a-z0-9%-]+%.%a+$")
        or (not step:match("%.before$") and not step:match("%.after$"))
        or build_id ~= "24575149" or type(object_valid) ~= "boolean"
        or type(self.breadcrumb_file_path) ~= "string" then
        return false
    end
    return self.filesystem.append(self.breadcrumb_file_path, json.encode({
        step = step,
        buildId = build_id,
        objectValid = object_valid,
    }) .. "\n")
end

for _, level in ipairs({ "debug", "info", "warn", "error" }) do
    Logger[level] = function(self, message, fields)
        self:write(level, message, fields)
    end
end

return Logger
