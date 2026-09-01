local M = {}

local separator = package.config:sub(1, 1)

local function normalize(value)
    value = tostring(value or "")
    if separator == "\\" then
        return value:gsub("/", "\\")
    end
    return value:gsub("\\", "/")
end

function M.join(...)
    local parts = { ... }
    local result = ""
    for _, part in ipairs(parts) do
        part = normalize(part)
        if part ~= "" then
            if result == "" then
                result = part:gsub(separator == "\\" and "\\+$" or "/+$", "")
            else
                part = part:gsub(separator == "\\" and "^\\+" or "^/+", "")
                result = result .. separator .. part
            end
        end
    end
    return result
end

function M.dirname(value)
    value = normalize(value)
    local pattern = separator == "\\" and "^(.*)\\[^\\]*$" or "^(.*)/[^/]*$"
    return value:match(pattern) or "."
end

function M.file_exists(value)
    local file = io.open(value, "rb")
    if not file then
        return false
    end
    file:close()
    return true
end

local function trusted_shell_path(value)
    return type(value) == "string" and value ~= "" and not value:find('["\r\n]')
end

local function is_absolute(value)
    local canonical = tostring(value or ""):gsub("\\", "/")
    return canonical:match("^%a:/") ~= nil or canonical:sub(1, 2) == "//" or canonical:sub(1, 1) == "/"
end

function M.ensure_directory(value)
    value = normalize(value)
    if not trusted_shell_path(value) then
        return false, "unsafe or empty directory path"
    end
    local probe = M.join(value, ".ped-directory-probe")
    local existing = io.open(probe, "ab")
    if existing then
        existing:close()
        os.remove(probe)
        return true
    end
    local command
    if separator == "\\" then
        command = string.format('mkdir "%s" >NUL 2>NUL', value)
    else
        command = string.format('mkdir -p "%s" >/dev/null 2>&1', value)
    end
    os.execute(command)
    local created = io.open(probe, "wb")
    if not created then
        return false, "unable to create or write directory: " .. value
    end
    created:close()
    os.remove(probe)
    return true
end

function M.script_path(stack_level)
    local info = debug.getinfo(stack_level or 2, "S")
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return normalize(source)
end

function M.resolve_data_directory(scripts_root)
    local override = os.getenv("PAL_EVENT_DIRECTOR_DATA_DIR")
    if override and trusted_shell_path(override) and is_absolute(override) then
        return normalize(override), "environment"
    elseif override then
        return nil, "unsafe-relative-environment-override"
    end

    local canonical = normalize(scripts_root):gsub("\\", "/")
    local lower = canonical:lower()
    local marker = "/mods/nativemods/ue4ss/mods/"
    local marker_start = lower:find(marker, 1, true)
    if marker_start then
        local server_root = canonical:sub(1, marker_start - 1)
        return normalize(server_root .. "/Pal/Saved/PalEventDirector"), "official-loader-layout"
    end

    local legacy_marker = "/pal/binaries/win64/mods/"
    marker_start = lower:find(legacy_marker, 1, true)
    if marker_start then
        local server_root = canonical:sub(1, marker_start - 1)
        return normalize(server_root .. "/Pal/Saved/PalEventDirector"), "legacy-ue4ss-layout"
    end

    return nil, "unrecognized-layout"
end

return M
