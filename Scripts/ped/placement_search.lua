local util = require("ped.util")

local Search = {}
Search.__index = Search

local ERROR = "Custom assault placement is unavailable"

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function point(value)
    if type(value) ~= "table" or not finite(value.X) or not finite(value.Y) or not finite(value.Z) then error(ERROR, 0) end
    return { X = value.X, Y = value.Y, Z = value.Z }
end

function Search.new(options)
    local origin = point(options.origin)
    if not finite(options.range) or options.range < 500 or options.range > 100000
        or not util.is_integer(options.slot) or options.slot < 1 or options.slot > 8
        or not finite(options.rotation) or type(options.allowFallback) ~= "boolean" then error(ERROR, 0) end
    local candidates = {}
    if options.preferred then candidates[1] = { position = point(options.preferred), mode = "approach" } end
    if options.allowFallback then
        local radius = math.min(1000, options.range * 0.65)
        for ring = 1, 2 do
            for index = 1, 8 do
                local angle = math.rad(options.rotation + (options.slot - 1) * 45 + (index - 1) * 45)
                local distance = radius * (ring == 1 and 1 or 0.5)
                candidates[#candidates + 1] = { mode = "in-base", position = {
                    X = origin.X + math.cos(angle) * distance,
                    Y = origin.Y + math.sin(angle) * distance,
                    Z = origin.Z,
                } }
            end
        end
    end
    return setmetatable({ candidates = candidates, cursor = 1, attempts = 0,
        fallbackReason = not options.preferred and "approach-unavailable" or nil }, Search)
end

function Search:poll(check, budget)
    if self.interrupted then error(ERROR, 0) end
    if self.finished then return util.deep_copy(self.finished) end
    if type(check) ~= "function" or not util.is_integer(budget) or budget < 1 or budget > 2 then error(ERROR, 0) end
    for _ = 1, budget do
        local candidate = self.candidates[self.cursor]
        if not candidate then break end
        self.cursor, self.attempts, self.interrupted = self.cursor + 1, self.attempts + 1, true
        local result = check(point(candidate.position), candidate.mode)
        if type(result) ~= "table" or type(result.ready) ~= "boolean" then error(ERROR, 0) end
        if result.ready then
            result.position = point(result.position)
            result.mode, result.attempts = candidate.mode, self.attempts
            result.fallbackReason = candidate.mode == "in-base" and self.fallbackReason or nil
            self.finished, self.interrupted = util.deep_copy(result), false
            return result
        end
        if type(result.reason) ~= "string" or #result.reason > 64 or not result.reason:match("^[a-z0-9%-]+$") then error(ERROR, 0) end
        self.reason = result.reason
        if candidate.mode == "approach" then self.fallbackReason = result.reason end
        self.interrupted = false
    end
    local result = { ready = false, reason = self.reason or "approach-unavailable", attempts = self.attempts }
    if self.cursor <= #self.candidates then
        result.pending = true
    else
        self.finished = util.deep_copy(result)
    end
    return result
end

return Search
