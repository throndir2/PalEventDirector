local util = require("ped.util")

local Logger = {}
Logger.__index = Logger

local LEVELS = { debug = 10, info = 20, warn = 30, error = 40 }

function Logger.new(options)
    options = options or {}
    return setmetatable({
        level = LEVELS[options.level] or LEVELS.info,
        file_path = options.file_path,
        prefix = options.prefix or "PalEventDirector",
    }, Logger)
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

for _, level in ipairs({ "debug", "info", "warn", "error" }) do
    Logger[level] = function(self, message, fields)
        self:write(level, message, fields)
    end
end

return Logger
