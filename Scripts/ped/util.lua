local M = {}

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

function M.is_integer(value)
    return is_integer(value)
end

function M.clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

function M.shallow_copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

function M.deep_copy(source, seen)
    if type(source) ~= "table" then
        return source
    end
    seen = seen or {}
    if seen[source] then
        return seen[source]
    end
    local result = {}
    seen[source] = result
    for key, value in pairs(source) do
        result[M.deep_copy(key, seen)] = M.deep_copy(value, seen)
    end
    return setmetatable(result, getmetatable(source))
end

function M.deep_merge(base, overlay)
    local result = M.deep_copy(base or {})
    for key, value in pairs(overlay or {}) do
        local value_meta = type(value) == "table" and getmetatable(value) or nil
        local result_meta = type(result[key]) == "table" and getmetatable(result[key]) or nil
        local value_is_array = value_meta and value_meta.__json_kind == "array"
        local result_is_array = result_meta and result_meta.__json_kind == "array"
        if type(value) == "table" and type(result[key]) == "table" and not value_is_array and not result_is_array then
            result[key] = M.deep_merge(result[key], value)
        else
            result[key] = M.deep_copy(value)
        end
    end
    return result
end

function M.sorted_keys(source)
    local keys = {}
    for key in pairs(source or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then
            return left < right
        end
        return tostring(left) < tostring(right)
    end)
    return keys
end

function M.count(source)
    local total = 0
    for _ in pairs(source or {}) do
        total = total + 1
    end
    return total
end

function M.starts_with(value, prefix)
    return type(value) == "string" and value:sub(1, #prefix) == prefix
end

function M.trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.sanitize_text(value, maximum_length)
    value = tostring(value or "")
    value = value:gsub("[%z\1-\8\11\12\14-\31\127]", "")
    value = value:gsub("[\r\n]+", " ")
    value = M.trim(value)
    if maximum_length and #value > maximum_length then
        value = value:sub(1, maximum_length)
    end
    return value
end

-- A deterministic non-cryptographic hash used only for IDs/checksums/tie order.
-- Keep every intermediate below 2^53 so Lua integer and JS-backed test VMs agree.
function M.hash32(value)
    local hash = 5381
    value = tostring(value or "")
    for index = 1, #value do
        hash = (hash * 33 + value:byte(index)) % 2147483647
    end
    return string.format("%08x", hash)
end

function M.utc_now()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.now_seconds()
    return os.time()
end

function M.new_occurrence_id(now_seconds, nonce)
    now_seconds = now_seconds or M.now_seconds()
    nonce = nonce or 0
    return string.format("siege-%d-%04d-%s", now_seconds, nonce % 10000, M.hash32(tostring(now_seconds) .. ":" .. tostring(nonce)))
end

function M.mask_uid(uid)
    uid = tostring(uid or "unknown")
    if #uid <= 8 then
        return uid
    end
    return uid:sub(1, 4) .. "…" .. uid:sub(-4)
end

function M.split_words(value)
    local result = {}
    for word in tostring(value or ""):gmatch("%S+") do
        result[#result + 1] = word
    end
    return result
end

return M
