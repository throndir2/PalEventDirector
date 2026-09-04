package.path = "./Scripts/?.lua;./Scripts/?/init.lua;" .. package.path
local Diagnostic = require("ped.preflight_diagnostic")
local Logger = require("ped.logger")
local Config = require("ped.config")
local logger = Logger.new({ breadcrumb_file_path = assert(arg[1]) })
local env = {
    COMPUTERNAME = "IMOUTO",
    PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = "24575149",
    PAL_EVENT_DIRECTOR_UE4SS_TAG = "2281fa31",
    PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = "3.0.1",
}
local diagnostic = Diagnostic.new({
    config = Config.defaults(),
    getenv = function(name) return env[name] end,
    engine = { UE4SS = { GetVersion = function() os.exit(86) end } },
    run_id = 100,
    record = function(step, build, valid) return logger:preflight_breadcrumb(step, build, valid) end,
})
diagnostic:run()
local _, reason = diagnostic:run("confirm-disposable-readonly", diagnostic.pending.step)
error("simulated fail-fast unexpectedly returned: " .. reason)