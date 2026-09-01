local util = require("ped.util")

local M = {}
local ARRAY_MT = { __json_kind = "array" }
local OBJECT_MT = { __json_kind = "object" }
M.null = setmetatable({}, { __tostring = function() return "null" end })

function M.array(value)
    return setmetatable(value or {}, ARRAY_MT)
end

function M.object(value)
    return setmetatable(value or {}, OBJECT_MT)
end

local ESCAPES = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function encode_string(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
        return ESCAPES[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

local function table_kind(value)
    local metatable = getmetatable(value)
    if metatable and metatable.__json_kind then
        return metatable.__json_kind
    end
    local maximum = 0
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return "object"
        end
        maximum = math.max(maximum, key)
        count = count + 1
    end
    if count > 0 and maximum == count then
        return "array"
    end
    return "object"
end

local function encode_value(value, stack)
    local value_type = type(value)
    if value == M.null or value_type == "nil" then
        return "null"
    elseif value_type == "boolean" then
        return value and "true" or "false"
    elseif value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("cannot encode a non-finite JSON number")
        end
        return tostring(value)
    elseif value_type == "string" then
        return encode_string(value)
    elseif value_type ~= "table" then
        error("cannot encode JSON value of type " .. value_type)
    end

    if stack[value] then
        error("cannot encode a cyclic JSON table")
    end
    stack[value] = true

    local parts = {}
    if table_kind(value) == "array" then
        for index = 1, #value do
            parts[index] = encode_value(value[index], stack)
        end
        stack[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    for _, key in ipairs(util.sorted_keys(value)) do
        if type(key) ~= "string" then
            error("JSON object keys must be strings")
        end
        parts[#parts + 1] = encode_string(key) .. ":" .. encode_value(value[key], stack)
    end
    stack[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

function M.encode(value)
    return encode_value(value, {})
end

local function utf8_char(codepoint)
    if utf8 and utf8.char then
        return utf8.char(codepoint)
    end
    if codepoint <= 0x7f then
        return string.char(codepoint)
    elseif codepoint <= 0x7ff then
        return string.char(0xc0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
    elseif codepoint <= 0xffff then
        return string.char(0xe0 + math.floor(codepoint / 0x1000), 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
    end
    return string.char(0xf0 + math.floor(codepoint / 0x40000), 0x80 + math.floor(codepoint / 0x1000) % 0x40, 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
end

local function decoder(text)
    local position = 1
    local length = #text

    local function fail(message)
        error(string.format("JSON error at byte %d: %s", position, message), 0)
    end

    local function skip_whitespace()
        local _, finish = text:find("^[ \t\r\n]*", position)
        position = (finish or position - 1) + 1
    end

    local parse_value

    local function parse_string()
        if text:sub(position, position) ~= '"' then
            fail("expected string")
        end
        position = position + 1
        local parts = {}
        local start = position
        while position <= length do
            local byte = text:byte(position)
            if byte == 34 then
                parts[#parts + 1] = text:sub(start, position - 1)
                position = position + 1
                return table.concat(parts)
            elseif byte == 92 then
                parts[#parts + 1] = text:sub(start, position - 1)
                position = position + 1
                local escape = text:sub(position, position)
                local simple = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
                if simple[escape] then
                    parts[#parts + 1] = simple[escape]
                    position = position + 1
                elseif escape == "u" then
                    local hex = text:sub(position + 1, position + 4)
                    if not hex:match("^%x%x%x%x$") then
                        fail("invalid unicode escape")
                    end
                    local codepoint = tonumber(hex, 16)
                    position = position + 5
                    if codepoint >= 0xd800 and codepoint <= 0xdbff then
                        if text:sub(position, position + 1) ~= "\\u" then
                            fail("high surrogate without low surrogate")
                        end
                        local low_hex = text:sub(position + 2, position + 5)
                        local low = tonumber(low_hex, 16)
                        if not low or low < 0xdc00 or low > 0xdfff then
                            fail("invalid low surrogate")
                        end
                        codepoint = 0x10000 + (codepoint - 0xd800) * 0x400 + (low - 0xdc00)
                        position = position + 6
                    elseif codepoint >= 0xdc00 and codepoint <= 0xdfff then
                        fail("unexpected low surrogate")
                    end
                    parts[#parts + 1] = utf8_char(codepoint)
                else
                    fail("invalid escape")
                end
                start = position
            elseif byte < 32 then
                fail("control character in string")
            else
                position = position + 1
            end
        end
        fail("unterminated string")
    end

    local function parse_number()
        local remaining = text:sub(position)
        local token = remaining:match("^-?0") or remaining:match("^-?[1-9]%d*")
        if not token then
            fail("invalid number")
        end
        local cursor = #token + 1
        if remaining:sub(cursor, cursor) == "." then
            local fraction = remaining:sub(cursor):match("^%.%d+")
            if not fraction then fail("invalid fraction") end
            token = token .. fraction
            cursor = #token + 1
        end
        if remaining:sub(cursor, cursor):match("[eE]") then
            local exponent = remaining:sub(cursor):match("^[eE][+-]?%d+")
            if not exponent then fail("invalid exponent") end
            token = token .. exponent
        end
        local following = remaining:sub(#token + 1, #token + 1)
        if following:match("[%d%.eE%+%-]") then
            fail("invalid number boundary")
        end
        local value = tonumber(token)
        if not value then
            fail("invalid number")
        end
        position = position + #token
        return value
    end

    local function parse_array()
        position = position + 1
        skip_whitespace()
        local result = M.array()
        if text:sub(position, position) == "]" then
            position = position + 1
            return result
        end
        while true do
            result[#result + 1] = parse_value()
            skip_whitespace()
            local character = text:sub(position, position)
            if character == "]" then
                position = position + 1
                return result
            elseif character ~= "," then
                fail("expected ',' or ']'")
            end
            position = position + 1
            skip_whitespace()
        end
    end

    local function parse_object()
        position = position + 1
        skip_whitespace()
        local result = M.object()
        if text:sub(position, position) == "}" then
            position = position + 1
            return result
        end
        while true do
            local key = parse_string()
            skip_whitespace()
            if text:sub(position, position) ~= ":" then
                fail("expected ':'")
            end
            position = position + 1
            skip_whitespace()
            result[key] = parse_value()
            skip_whitespace()
            local character = text:sub(position, position)
            if character == "}" then
                position = position + 1
                return result
            elseif character ~= "," then
                fail("expected ',' or '}'")
            end
            position = position + 1
            skip_whitespace()
        end
    end

    parse_value = function()
        skip_whitespace()
        local character = text:sub(position, position)
        if character == '"' then
            return parse_string()
        elseif character == "{" then
            return parse_object()
        elseif character == "[" then
            return parse_array()
        elseif character == "-" or character:match("%d") then
            return parse_number()
        elseif text:sub(position, position + 3) == "true" then
            position = position + 4
            return true
        elseif text:sub(position, position + 4) == "false" then
            position = position + 5
            return false
        elseif text:sub(position, position + 3) == "null" then
            position = position + 4
            return M.null
        end
        fail("unexpected token")
    end

    local result = parse_value()
    skip_whitespace()
    if position <= length then
        fail("trailing content")
    end
    return result
end

function M.decode(text)
    if type(text) ~= "string" then
        error("JSON input must be a string")
    end
    return decoder(text)
end

return M
