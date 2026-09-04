local separator = package.config:sub(1, 1)
local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
    source = source:sub(2)
end
source = source:gsub("[/\\]", separator)
local scripts_root = source:match(separator == "\\" and "^(.*)\\[^\\]*$" or "^(.*)/[^/]*$") or "."
package.path = table.concat({
    scripts_root .. separator .. "?.lua",
    scripts_root .. separator .. "?" .. separator .. "init.lua",
    package.path,
}, ";")

local function boot()
    local Config = require("ped.config")
    local Director = require("ped.director")
    local Logger = require("ped.logger")
    local Bridge = require("ped.palworld")
    local Store = require("ped.store")
    local path = require("ped.path")
    local version = require("ped.version")

    local data_directory, path_source = path.resolve_data_directory(scripts_root)
    if not data_directory then
        error("Unable to derive an external data directory (classification: " .. tostring(path_source or "unknown") .. "). Set PAL_EVENT_DIRECTOR_DATA_DIR to an absolute writable path.")
    end
    local directory_ok, directory_error = path.ensure_directory(data_directory)
    if not directory_ok then
        error(directory_error)
    end
    local logger = Logger.new({
        level = "info",
        file_path = path.join(data_directory, "pal-event-director.log"),
    })
    logger:info("Loading server-only UE4SS Lua mod", {
        version = version.version,
        adapter = version.adapter,
        dataPathSource = path_source,
    })

    local config, created, config_error = Config.load(path.join(data_directory, "config.json"), logger)
    if not config then
        error(config_error)
    end
    logger.level = ({ debug = 10, info = 20, warn = 30, error = 40 })[config.runtime.logLevel] or 20
    local store = Store.new(data_directory, logger)
    local bridge = Bridge.new({ config = config, logger = logger })
    local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger })
    bridge:attach_director(director)
    local registered, registration_error = bridge:register()
    if not registered then
        error(registration_error)
    end

    _G.PalEventDirector = {
        version = version,
        config = config,
        data_directory = data_directory,
        status = function() return director:status_text() end,
    }
    local mod_ref = rawget(_G, "ModRef")
    if mod_ref and type(mod_ref.OnUnload) == "function" then
        mod_ref:OnUnload(function()
            bridge:unregister()
            _G.PalEventDirector = nil
        end)
    end
    logger:info("Pal Event Director loaded", {
        mode = config.mode,
        configCreated = created,
        startAllInvasions = config.capabilities.startAllInvasions,
        grantItems = config.capabilities.grantItems,
    })
    if created then
        logger:warn("Edit persistent config.json and restart the mod before mutation capabilities can be enabled")
    end
end

local ok, boot_error = xpcall(boot, debug.traceback)
if not ok then
    print("[PalEventDirector] [FATAL] " .. tostring(boot_error) .. "\n")
end
