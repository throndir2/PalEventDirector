local path = require("ped.path")

local M = {}

function M.ensure_directory(directory)
    return path.ensure_directory(directory)
end

function M.exists(file_path)
    return path.file_exists(file_path)
end

function M.read(file_path)
    local file, open_error = io.open(file_path, "rb")
    if not file then
        return nil, open_error
    end
    local content = file:read("*a")
    file:close()
    return content
end

function M.write(file_path, content)
    local file, open_error = io.open(file_path, "wb")
    if not file then
        return false, open_error
    end
    local ok, write_error = file:write(content)
    if not ok then
        file:close()
        return false, write_error
    end
    file:flush()
    file:close()
    return true
end

function M.append(file_path, content)
    local file, open_error = io.open(file_path, "ab")
    if not file then
        return false, open_error
    end
    local ok, write_error = file:write(content)
    if not ok then
        file:close()
        return false, write_error
    end
    file:flush()
    file:close()
    return true
end

function M.remove(file_path)
    local ok, remove_error = os.remove(file_path)
    if ok or not M.exists(file_path) then
        return true
    end
    return false, remove_error
end

function M.rename(source, destination)
    return os.rename(source, destination)
end

return M
