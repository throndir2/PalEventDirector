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
    local content, read_error = file:read("*a")
    local closed, close_error = file:close()
    if content == nil then
        return nil, read_error
    end
    if not closed then
        return nil, close_error
    end
    return content
end

local function write_all(file_path, mode, content)
    local file, open_error = io.open(file_path, mode)
    if not file then
        return false, open_error
    end
    local written, write_error = file:write(content)
    if not written then
        file:close()
        return false, write_error
    end
    local flushed, flush_error = file:flush()
    if not flushed then
        file:close()
        return false, flush_error
    end
    local closed, close_error = file:close()
    if not closed then
        return false, close_error
    end
    return true
end

function M.write(file_path, content)
    return write_all(file_path, "wb", content)
end

function M.append(file_path, content)
    return write_all(file_path, "ab", content)
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
