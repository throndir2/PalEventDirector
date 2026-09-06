local separator = package.config:sub(1, 1)
local function join(...)
    return table.concat({ ... }, separator)
end

local scripts_package_root = assert(arg[4], "packaged Scripts directory is required")
package.path = table.concat({
    join(scripts_package_root, "?.lua"),
    join(scripts_package_root, "?", "init.lua"),
}, ";")
package.cpath = ""

local Path = require("ped.path")
local scripts_root = assert(arg[1], "scripts root is required")
local expected_directory = assert(arg[2], "expected data directory is required")
local expected_source = assert(arg[3], "expected path source is required")
local actual_directory, actual_source = Path.resolve_data_directory(scripts_root, function() return nil end)

if actual_directory ~= expected_directory or actual_source ~= expected_source then
    io.stderr:write(string.format(
        "installer path contract failed: directory=%s source=%s expectedDirectory=%s expectedSource=%s\n",
        tostring(actual_directory),
        tostring(actual_source),
        expected_directory,
        expected_source
    ))
    os.exit(1)
end

io.write("PASS installer ModTarget is accepted by packaged path resolver\n")

require("ped.director")
require("ped.palworld")
require("ped.logger")
io.write("PASS packaged runtime imports are self-contained\n")
