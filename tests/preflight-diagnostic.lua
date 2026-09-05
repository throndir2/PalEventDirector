return function(test, equal, truthy)
    local Diagnostic = require("ped.preflight_diagnostic")
    local Bridge = require("ped.palworld")
    local Config = require("ped.config")
    local Director = require("ped.director")
    local Logger = require("ped.logger")
    local Ingress = require("ped.diagnostic_ingress")
    local json = require("ped.json")
    local util = require("ped.util")
    local TOKEN = "confirm-disposable-readonly"

    local function fixture(options)
        options = options or {}
        local records, operations = {}, {}
        local env = {
            COMPUTERNAME = "IMOUTO",
            PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = "24575149",
            PAL_EVENT_DIRECTOR_UE4SS_TAG = "2281fa31",
            PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = "3.0.1",
        }
        local function call(name, callback)
            return function(...)
                operations[#operations + 1] = name
                local before = records[#records]
                truthy(before and before.step:match("%.before$"), "native operation had no flushed before-marker")
                if options.failure == name then
                    local value = options.failure_value
                    if value == nil then value = setmetatable({}, { __tostring = function() error("native error was stringified") end }) end
                    error(value, 0)
                end
                return callback(...)
            end
        end
        local function object(name, methods)
            methods = methods or {}
            methods.IsValid = call(name .. ".IsValid", function() return options.invalid ~= name end)
            local iterator = methods.ForEachProperty
            methods.ForEachProperty = nil
            local enumerator = iterator
            if type(iterator) == "function" then
                enumerator = call(name .. ".ForEachProperty", function(receiver, callback)
                    equal(receiver, methods, "ForEachProperty requires the explicit wrapper receiver")
                    equal(type(callback), "function")
                    return iterator(callback)
                end)
            end
            local lookup = call(name .. ".ForEachProperty.lookup", function() return enumerator end)
            return setmetatable(methods, {
                __tostring = function() error("native object was stringified") end,
                __index = function(_, key) if key == "ForEachProperty" then return lookup() end end,
            })
        end
        local function enumerate_values(callback, values)
            for _, value in ipairs(values) do
                local stop = callback(value)
                truthy(stop == nil or stop == true, "false continuation triggers the pinned double-removal hazard")
                if stop then break end
            end
        end
        local world = object("world", { GetAddress = call("world.GetAddress", function() return 123 end) })
        local manager = object("manager", {
            GetWorld = call("manager.GetWorld", function() return world end),
            GetAddress = call("manager.GetAddress", function() return 456 end),
        })
        local controller = object("controller", { GetWorld = call("controller.GetWorld", function() return world end) })
        local foreign_world = object("foreign-options-world", { GetAddress = call("foreign-options-world.GetAddress", function() return 789 end) })
        local settings_view = setmetatable({
            type = call("options-settings.type", function() return options.bad_settings_type and "UObject" or "UScriptStruct" end),
            bEnableInvaderEnemy = options.invaders_enabled ~= false,
        }, { __tostring = function() error("settings values were stringified") end })
        local option_subsystem = object("options-subsystem", {
            GetWorld = call("options-subsystem.GetWorld", function() return options.foreign_options_world and foreign_world or world end),
            OptionWorldSettings = settings_view,
        })
        local utility = object("utility", {
            GetInvaderManager = call("utility.GetInvaderManager", function(_, argument) equal(argument, world); return manager end),
            GetOptionSubsystem = call("utility.GetOptionSubsystem", function(_, argument) equal(argument, world); return option_subsystem end),
            GetOptionWorldSettings = function() error("unsafe settings getter was invoked") end,
        })
        local fields = { object("settings-last-field", {
            GetOffset_Internal = call("settings-last-field.GetOffset_Internal", function() return options.settings_offset or 512 end),
        }) }
        local settings_type = object("settings-type", {
            GetFullName = call("settings-type.GetFullName", function() return "ScriptStruct /Script/Pal.PalOptionWorldSettings" end),
            ForEachProperty = function(callback) enumerate_values(callback, fields) end,
        })
        local function class(name)
            return object(name, { GetFullName = call(name .. ".GetFullName", function() return "Class " .. name end) })
        end
        local function copied_name(label, text)
            return setmetatable({
                type = call(label .. ".type", function() return options.bad_fname_wrapper and "FString" or "FName" end),
                ToString = call(label .. ".ToString", function() return text end),
            }, { __tostring = function() error("copied metadata was stringified") end })
        end
        local function field_metadata(label, name, kind)
            return {
                GetFullName = function() error("compound property display names must not determine the signature") end,
                GetFName = call(label .. ".GetFName", function()
                    if options.missing_fname then return nil end
                    return copied_name(label .. "-fname", name)
                end),
                GetClass = call(label .. ".GetClass", function()
                    return setmetatable({
                        type = call(label .. "-field-class.type", function() return options.bad_field_wrapper and "UClass" or "FieldClass" end),
                        GetFName = call(label .. "-field-class.GetFName", function() return copied_name(label .. "-field-class-fname", kind) end),
                    }, { __tostring = function() error("field class was stringified") end })
                end),
            }
        end
        local function signature(method, result_kind, result_class)
            local input_methods = field_metadata(method .. "-input", options.input_name or "WorldContextObject", options.input_kind or "ObjectProperty")
            input_methods.GetOffset_Internal = call(method .. ".input-offset", function() return 0 end)
            input_methods.GetPropertyClass = call(method .. ".input-class", function() return class("/Script/CoreUObject.Object") end)
            local input = object(method .. "-input", input_methods)
            local output_methods = field_metadata(method .. "-output", options.output_name or "ReturnValue", options.output_kind or result_kind)
            output_methods.GetOffset_Internal = call(method .. ".return-offset", function() return options.return_offset or 8 end)
            output_methods.GetPropertyClass = call(method .. ".return-class", function() return class("/Script/Pal." .. (result_class or "PalInvaderManager")) end)
            output_methods.GetStruct = call(method .. ".return-struct", function() return settings_type end)
            local output = object(method .. "-output", output_methods)
            local enumerate
            if not options.missing_enumerator then
                enumerate = function(callback) enumerate_values(callback, { input, output }) end
            end
            if options.noncallable_enumerator then enumerate = {} end
            return object(method, {
                type = call(method .. ".type", function() return "UFunction" end),
                GetFunctionFlags = call(method .. ".flags", function() return options.flags or 0x2400 end),
                ForEachProperty = enumerate,
            })
        end
        local metadata = {
            ["/Script/Pal.Default__PalUtility"] = utility,
            ["/Script/Pal.PalUtility:GetInvaderManager"] = signature("GetInvaderManager", "ObjectProperty"),
            ["/Script/Pal.PalUtility:GetOptionWorldSettings"] = signature("GetOptionWorldSettings", "StructProperty"),
            ["/Script/Pal.PalUtility:GetOptionSubsystem"] = signature("GetOptionSubsystem", "ObjectProperty", "PalOptionSubsystem"),
        }
        local engine = {
            UE4SS = { GetVersion = call("runtime.GetVersion", function() return 3, 0, options.bad_api and 2 or 1 end) },
            StaticFindObject = call("StaticFindObject", function(path) return metadata[path] end),
            FindFirstOf = call("FindFirstOf", function(name) equal(name, "PalPlayerController"); return controller end),
        }
        local diagnostic = Diagnostic.new({
            config = Config.defaults(),
            engine = engine,
            getenv = function(name) return env[name] end,
            run_id = 100,
            native_readiness = options.native_readiness,
            record = function(step, build, valid)
                if options.record_failure and step:match(options.record_failure .. "$") then return false end
                records[#records + 1] = { step = step, buildId = build, objectValid = valid }
                return true
            end,
        })
        return diagnostic, records, operations, env
    end

    local function finish(diagnostic, operations, allow_completion)
        local reason
        for _ = 1, 160 do
            local previous = #operations
            truthy(diagnostic:run())
            local ok, result = diagnostic:run(TOKEN, diagnostic.pending.step)
            local target_operations = 0
            for index = previous + 1, #operations do
                if not operations[index]:match("%.IsValid$") then target_operations = target_operations + 1 end
            end
            truthy(#operations > previous)
            truthy(target_operations <= 1, "one confirmation executed more than one requested operation")
            if allow_completion and diagnostic.completed then reason = result; break end
            if not ok then reason = result; break end
        end
        truthy(reason, "diagnostic did not stop before settings materialization")
        return reason
    end

    test("optional inspection completes without becoming a gameplay prerequisite", function()
        local diagnostic, records, operations = fixture({ native_readiness = true })
        local result = finish(diagnostic, operations, true)
        truthy(diagnostic.completed and diagnostic.native_ready)
        truthy(result:match("Diagnostic inspection completed"))
        truthy(records[#records].step:match("options%-invasion%-enabled.after$"))
        local count = #operations
        equal(diagnostic:run(TOKEN), false)
        equal(#operations, count)
        local bridge = Bridge.new({ config = Config.defaults(), logger = {}, delivery_profile = "laboratory-native-test" })
        equal(bridge:native_start_guard(), false)
        bridge.config.capabilities.startAllInvasions = true
        bridge.registered, bridge.periodic_active = true, true
        equal(bridge.preflight_diagnostic, nil)
        truthy(bridge:native_start_guard())
        bridge.preflight_diagnostic = { halted = true, completed = false }
        truthy(bridge:native_start_guard(), "optional diagnostic was a mandatory gate")
        bridge.config.capabilities.startAllInvasions = false
        equal(bridge:native_start_guard(), false)
        bridge.config.capabilities.startAllInvasions = true
        bridge.periodic_active = false
        equal(bridge:native_start_guard(), false)
        bridge.periodic_active = true
        equal(bridge:diagnose_native_start_all("confirm-disposable-start-all"), false)
        bridge.native_fault = "fixture native fault"
        equal(bridge:native_start_guard(), false)
    end)

    test("laboratory readiness rejects wrong-world options disabled invasions and wrong struct wrappers", function()
        for _, options in ipairs({
            { foreign_options_world = true }, { invaders_enabled = false }, { bad_settings_type = true },
            { failure = "utility.GetOptionSubsystem" },
        }) do
            options.native_readiness = true
            local diagnostic, _, operations = fixture(options)
            finish(diagnostic, operations, true)
            equal(diagnostic.native_ready, false)
            equal(diagnostic.completed, false)
            equal(diagnostic.ready_world, nil)
        end
    end)

    test("world invasion setting uses the option subsystem property and never its large getter", function()
        local world = { IsValid = function() return true end, GetAddress = function() return 123 end }
        local foreign = { IsValid = function() return true end, GetAddress = function() return 456 end }
        local options_world = world
        local settings = { bEnableInvaderEnemy = true }
        local options = { IsValid = function() return true end, GetWorld = function() return options_world end, OptionWorldSettings = settings }
        local bridge = Bridge.new({ config = Config.defaults(), logger = { preflight_breadcrumb = function() return true end } })
        bridge.utility = {
            IsValid = function() return true end,
            GetOptionSubsystem = function(_, context) equal(context, world); return options end,
            GetOptionWorldSettings = function() error("unsafe by-value getter invoked") end,
        }
        truthy(bridge:_world_invaders_enabled(world))
        settings.bEnableInvaderEnemy = false
        equal(bridge:_world_invaders_enabled(world), false)
        settings.bEnableInvaderEnemy = nil
        equal(bridge:_world_invaders_enabled(world), false)
        settings.bEnableInvaderEnemy = true
        options_world = foreign
        equal(bridge:_world_invaders_enabled(world), false)
        options_world = world
        options.OptionWorldSettings = nil
        equal(bridge:_world_invaders_enabled(world), false)
    end)

    test("normal native operations preserve flushed boundaries multiple returns and private errors", function()
        for _, failure in ipairs({ "none", "before", "after", "operation" }) do
            local records, calls = {}, 0
            local bridge = Bridge.new({ config = Config.defaults(), logger = {
                preflight_breadcrumb = function(_, step, build, valid)
                    if step:match("%." .. failure .. "$") then return false end
                    records[#records + 1] = { step = step, buildId = build, objectValid = valid }
                    return true
                end,
                error = function() end,
            } })
            local ok, first, second, third = bridge:_native_step("fixture", function()
                calls = calls + 1
                truthy(records[#records].step:match("%.before$"))
                if failure == "operation" then error(setmetatable({}, { __tostring = function() error("private native error formatted") end })) end
                return 7, nil, "last"
            end)
            if failure == "none" then
                truthy(ok)
                equal(first, 7); equal(second, nil); equal(third, "last")
                equal(#records, 2)
                truthy(records[2].step:match("%.after$"))
            else
                equal(ok, false)
                truthy(first:match("Native operation stopped"))
                if failure == "operation" then truthy(first:match("non%-string%-error")) end
                equal(calls, failure == "before" and 0 or 1)
                local count = #records
                equal(bridge:_native_step("retry", function() error("native operation retried") end), false)
                equal(#records, count)
            end
            for _, record in ipairs(records) do equal(util.count(record), 3); equal(record.objectValid, false) end
        end
    end)

    test("normal start validation runs directly and traces a failing manager call without retry", function()
        for _, fail_manager in ipairs({ false, true }) do
            local records, option_calls = {}, 0
            local config = Config.defaults()
            config.capabilities.startAllInvasions = true
            local world = { IsValid = function() return true end, GetAddress = function() return 100 end }
            local manager = { IsValid = function() return true end, GetAddress = function() return 200 end, GetWorld = function() return world end }
            local roster = { { uid = "fixture-player", world = world } }
            local bridge = Bridge.new({ config = config, delivery_profile = "laboratory-native-test", logger = {
                preflight_breadcrumb = function(_, step) records[#records + 1] = step; return true end,
                error = function() end,
            } })
            bridge.registered, bridge.periodic_active = true, true
            bridge.utility = {
                IsValid = function() return true end,
                GetInvaderManager = function()
                    if fail_manager then error(setmetatable({}, { __tostring = function() error("private native error formatted") end })) end
                    return manager
                end,
                GetOptionSubsystem = function()
                    option_calls = option_calls + 1
                    return { IsValid = function() return true end, GetWorld = function() return world end,
                        OptionWorldSettings = { bEnableInvaderEnemy = true } }
                end,
                GetOptionWorldSettings = function() error("unsafe settings getter invoked") end,
            }
            bridge.preflight_environment = function() return true end
            bridge.list_online_players = function() return roster end
            bridge._registered_base_ids = function() return { "fixture-base" } end
            bridge.active_invasion_count = function() return 0 end
            bridge._eligible_online_guild_bases = function()
                return { ["fixture-base"] = true }, { ["fixture-base"] = "native-id" }, { ["fixture-base"] = "fixture-guild" }, roster
            end
            bridge._static_find = function() return { IsValid = function() return true end } end
            equal(bridge.preflight_diagnostic, nil)
            local ok, reason = bridge:preflight_start("native")
            if fail_manager then
                equal(ok, false)
                truthy(reason:match("non%-string%-error"))
                truthy(records[#records]:match("start%-get%-invader%-manager.before$"))
                equal(option_calls, 0)
                local count = #records
                equal(bridge:preflight_start("native"), false)
                equal(#records, count)
            else
                truthy(ok, reason)
                equal(option_calls, 1)
                equal(bridge.pending_manager, manager)
                equal(bridge.pending_world, world)
                truthy(bridge.pending_expected_bases["fixture-base"])
                equal(#bridge.pending_roster, 1)
                truthy(records[#records]:match("start%-dispatch%-function.after$"))
            end
        end
    end)

    test("preflight diagnostic is inert until exact host build runtime and console confirmation", function()
        local diagnostic, records, operations, env = fixture()
        equal(#operations, 0)
        truthy(diagnostic:run())
        equal(#records, 0)
        equal(#operations, 0)
        equal(diagnostic:run("wrong-token"), false)
        equal(#operations, 0)
        equal(diagnostic:run(TOKEN), false, "unbound confirmation must never advance")
        for _, name in ipairs({ "COMPUTERNAME", "PAL_EVENT_DIRECTOR_SERVER_BUILD_ID", "PAL_EVENT_DIRECTOR_UE4SS_TAG", "PAL_EVENT_DIRECTOR_UE4SS_API_VERSION" }) do
            local previous = env[name]
            env[name] = "mismatch"
            equal(diagnostic:run(TOKEN), false)
            equal(#operations, 0)
            env[name] = previous
        end
        local ok, message = diagnostic:run(TOKEN, "100-9999-wrong-step")
        equal(ok, false)
        truthy(message:match("Exact previewed step"))
        equal(#operations, 0)
    end)

    test("diagnostic records separate manager world address and metadata boundaries then refuses oversized return", function()
        local diagnostic, records, operations = fixture()
        local reason = finish(diagnostic, operations)
        truthy(reason:match("exceed.*512%-byte"))
        local order = {}
        for index, name in ipairs(operations) do order[name] = index end
        truthy(order["utility.GetInvaderManager"] < order["manager.GetWorld"])
        truthy(order["manager.GetWorld"] < order["manager.GetAddress"])
        truthy(order["manager.GetAddress"] < order["GetOptionWorldSettings.return-struct"])
        equal(#records, #operations * 2)
        for index = 1, #records, 2 do
            local before, after = records[index], records[index + 1]
            equal(before.step:gsub("%.before$", ""), after.step:gsub("%.after$", ""))
            equal(before.buildId, "24575149")
            equal(type(before.objectValid), "boolean")
            equal(util.count(before), 3)
        end
        local count = #operations
        equal(diagnostic:run(TOKEN), false)
        equal(#operations, count, "halted diagnostic retried automatically")
        equal(diagnostic.thread, nil)
    end)

    test("unverifiable small settings lower bound also blocks the by-value getter", function()
        local diagnostic, _, operations = fixture({ settings_offset = 16 })
        local reason = finish(diagnostic, operations)
        truthy(reason:match("exact ParmsSize/return extent cannot be verified"))
    end)

    test("diagnostic rejects mismatched UFunction shape before invoking manager", function()
        for _, options in ipairs({ { flags = 0 }, { return_offset = 16 }, { invalid = "utility" }, { bad_api = true }, { missing_enumerator = true }, { noncallable_enumerator = true } }) do
            local diagnostic, _, operations = fixture(options)
            finish(diagnostic, operations)
            for _, name in ipairs(operations) do truthy(name ~= "utility.GetInvaderManager") end
        end
    end)

    test("signature uses exact field names and classes rather than compound display paths", function()
        for _, options in ipairs({
            { input_name = "NotWorldContextObject" }, { output_name = "NotReturnValue" },
            { input_kind = "ClassProperty" }, { output_kind = "StructProperty" },
            { input_name = 0 }, { input_kind = 0 },
            { bad_fname_wrapper = true }, { bad_field_wrapper = true }, { missing_fname = true },
        }) do
            local diagnostic, _, operations = fixture(options)
            finish(diagnostic, operations)
            for _, name in ipairs(operations) do truthy(name ~= "utility.GetInvaderManager") end
        end
        local diagnostic, _, operations = fixture()
        truthy(finish(diagnostic, operations):match("exceed.*512%-byte"))
        local seen = {}
        for _, name in ipairs(operations) do seen[name] = true end
        truthy(seen["GetInvaderManager-input.GetFName"])
        truthy(seen["GetInvaderManager-input.GetClass"])
        truthy(seen["GetInvaderManager-input-field-class.GetFName"])
        truthy(seen["GetInvaderManager-input-field-class-fname.ToString"])
    end)

    test("copied metadata reads still recheck their owning property after an operator pause", function()
        for _, boundary in ipairs({
            { step = "manager-parameter-1-fname-type", operation = "GetInvaderManager-input-fname.type" },
            { step = "manager-parameter-1-field-class-name", operation = "GetInvaderManager-input-field-class-fname.ToString" },
        }) do
            local options = {}
            local diagnostic, _, operations = fixture(options)
            for _ = 1, 80 do
                truthy(diagnostic:run())
                if diagnostic.pending.name == boundary.step then break end
                truthy(diagnostic:run(TOKEN, diagnostic.pending.step))
            end
            equal(diagnostic.pending.name, boundary.step)
            options.invalid = "GetInvaderManager-input"
            local previous = #operations
            local ok, reason = diagnostic:run(TOKEN, diagnostic.pending.step)
            equal(ok, false)
            truthy(reason:match("no longer valid"))
            for index = previous + 1, #operations do truthy(operations[index] ~= boundary.operation) end
            equal(diagnostic.thread, nil)
        end
    end)

    test("diagnostic rechecks retained handles before use after an operator pause", function()
        local options = {}
        local diagnostic, _, operations = fixture(options)
        for _ = 1, 80 do
            diagnostic:run()
            if diagnostic.pending.name == "get-invader-manager" then break end
            truthy(diagnostic:run(TOKEN, diagnostic.pending.step))
        end
        equal(diagnostic.pending.name, "get-invader-manager")
        options.invalid = "world"
        local ok, reason = diagnostic:run(TOKEN, diagnostic.pending.step)
        equal(ok, false)
        truthy(reason:match("no longer valid"))
        for _, name in ipairs(operations) do truthy(name ~= "utility.GetInvaderManager") end
        equal(diagnostic.thread, nil)
    end)

    test("diagnostic loses no boundary to error formatting or failed breadcrumb writes", function()
        local diagnostic, records, operations = fixture({ failure = "utility.GetInvaderManager" })
        local reason = finish(diagnostic, operations)
        truthy(reason:match("%[lua%-operation/non%-string%-error%].*raw error suppressed"))
        truthy(records[#records].step:match("get%-invader%-manager.before$"))
        local count = #operations
        equal(diagnostic:run(TOKEN), false)
        equal(#operations, count)
        local before_fail, _, before_calls = fixture({ record_failure = "before" })
        before_fail:run()
        equal(before_fail:run(TOKEN, before_fail.pending.step), false)
        equal(#before_calls, 0)
        equal(before_fail:run(TOKEN), false)
        local after_fail, _, after_calls = fixture({ record_failure = "after" })
        after_fail:run()
        equal(after_fail:run(TOKEN, after_fail.pending.step), false)
        equal(#after_calls, 1)
        equal(after_fail:run(TOKEN), false)
        equal(#after_calls, 1)
    end)

    test("metadata enumeration failures use a bounded privacy-safe classification", function()
        local diagnostic, records, operations = fixture({ failure = "GetInvaderManager.ForEachProperty" })
        local reason = finish(diagnostic, operations)
        truthy(reason:match("%[metadata%-enumeration/non%-string%-error%].*raw error suppressed"))
        truthy(records[#records].step:match("manager%-properties.before$"))
        for _, record in ipairs(records) do
            equal(record.failure, nil)
            equal(util.count(record), 3)
        end
    end)

    test("property method exposure has its own boundary and never falls back to another wrapper", function()
        for _, options in ipairs({
            { failure = "GetInvaderManager.ForEachProperty.lookup" },
            { missing_enumerator = true },
            { noncallable_enumerator = true },
        }) do
            local diagnostic, records, operations = fixture(options)
            local reason = finish(diagnostic, operations)
            if options.failure then
                truthy(reason:match("%[metadata%-method%-lookup/non%-string%-error%]"))
                truthy(records[#records].step:match("manager%-properties%-method.before$"))
            else
                truthy(reason:match("method is unavailable or not callable"))
                truthy(records[#records].step:match("manager%-properties%-method.after$"))
            end
            for _, name in ipairs(operations) do
                truthy(name ~= "GetInvaderManager.ForEachProperty" and name ~= "utility.GetInvaderManager")
            end
            local count = #operations
            equal(diagnostic:run(TOKEN), false)
            equal(#operations, count)
        end
    end)

    test("diagnostic error details are bounded allowlisted and retained after halt", function()
        local marker = "DO_NOT_EMIT_FIXTURE_PAYLOAD"
        for _, case in ipairs({
            { value = "A function requiring userdata as param #1 was called without userdata at param #1", code = "receiver-required" },
            { value = "has no instance inside lua_instances unordered map", code = "unregistered-lua-state" },
            { value = "userdata_internal_type", code = "invalid-userdata" },
            { value = "[Lua::call_function] attempt to call a nil value", code = "non-callable-value" },
            { value = "[Lua::call_function] unexpected callback failure", code = "callback-error" },
            { value = string.rep("x", 1024) .. "userdata_internal_type", code = "unclassified-lua-error" },
            { value = "unrecognized failure", code = "unclassified-lua-error" },
            { value = false, code = "non-string-error" },
        }) do
            local value = case.value
            if type(value) == "string" then value = value .. " " .. marker end
            local diagnostic, records, operations = fixture({
                failure = "GetInvaderManager.ForEachProperty", failure_value = value,
            })
            local reason = finish(diagnostic, operations)
            truthy(reason:find("[metadata-enumeration/" .. case.code .. "]", 1, true))
            equal(reason:find(marker, 1, true), nil)
            truthy(#reason < 240)
            truthy(records[#records].step:match("manager%-properties.before$"))
            local count = #operations
            local ok, halted_reason = diagnostic:run(TOKEN)
            equal(ok, false)
            equal(halted_reason, reason)
            equal(#operations, count)
        end
    end)

    test("preflight breadcrumb writer emits exactly three safe fields regardless of log level", function()
        local output = {}
        local logger = Logger.new({
            level = "error", breadcrumb_file_path = "fixture.ndjson",
            filesystem = { append = function(_, line) output[#output + 1] = line; return true end },
        })
        truthy(logger:preflight_breadcrumb("100-0001-manager-lookup.before", "24575149", true))
        local record = json.decode(output[1])
        equal(util.count(record), 3)
        equal(record.objectValid, true)
        equal(record.buildId, "24575149")
        local sentinel = setmetatable({}, { __tostring = function() error("sensitive value stringified") end })
        equal(logger:preflight_breadcrumb(sentinel, "24575149", true), false)
        equal(logger:preflight_breadcrumb("100-0002-test.after", "24575149", sentinel), false)
        equal(#output, 1)
    end)

    test("quarantined bridge and director reject every native start path before intent or reflection", function()
        local config = Config.defaults()
        for name in pairs(config.capabilities) do config.capabilities[name] = true end
        config.schedules[1].enabled = true
        local writes = 0
        local store = { load_snapshot = function() return nil end, append = function() writes = writes + 1; return true end, save_snapshot = function() return true end }
        local logger = { info = function() end, warn = function() end, error = function() end }
        local bridge = Bridge.new({ config = config, logger = logger })
        bridge.preflight_environment = function() error("quarantine reached environment calls") end
        bridge._find_first = function() error("quarantine reached native lookup") end
        bridge._resolve_world_manager = function() error("quarantine reached native manager") end
        local replies = {}
        bridge.send_chat = function(_, message) replies[#replies + 1] = message; return true end
        local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger })
        for _, command in ipairs({ "start native 0", "start native 10", "diagnose-native-all confirm-disposable-start-all", "reset", "abort", "resolve", "rewards" }) do
            equal(director:handle_operator_command(command, "console"), false)
        end
        equal(director:arm_start("console", "native", 0), false)
        equal(director:start("schedule", "native", director.scheduler_start_token, "x"), false)
        truthy(director:handle_chat("admin", "!siege start native 0"))
        truthy(replies[#replies]:match("start blocked"))
        director:tick()
        equal(bridge:preflight_start("native"), false)
        equal(bridge:begin_event_discovery("native", "x"), nil)
        equal(bridge:start_all_invasions(), false)
        equal(bridge:continue_invasion_dispatch(), false)
        equal(bridge:diagnose_native_start_all("confirm-disposable-start-all"), false)
        equal(bridge:_dispatch_selected_base("x", "probe").status, "dispatch_quarantined")
        equal(writes, 0)
        equal(util.count(director.scheduler.state.occurrences), 0)
    end)

    test("diagnostic-only startup suppresses hooks and polling even with old enabled configuration", function()
        local previous_console, previous_hook, previous_loop = _G.RegisterConsoleCommandGlobalHandler, _G.RegisterHook, _G.LoopInGameThreadWithDelay
        local config = Config.defaults()
        for name in pairs(config.capabilities) do config.capabilities[name] = true end
        local callback
        _G.RegisterConsoleCommandGlobalHandler = function(_, handler) callback = handler end
        _G.RegisterHook = function() error("quarantined hook registered") end
        _G.LoopInGameThreadWithDelay = function() error("quarantined automatic poll registered") end
        local bridge = Bridge.new({ config = config, logger = { warn = function() end }, delivery_profile = "preflight-diagnostic-only" })
        local ok, result = pcall(function() truthy(bridge:register()); truthy(callback) end)
        _G.RegisterConsoleCommandGlobalHandler, _G.RegisterHook, _G.LoopInGameThreadWithDelay = previous_console, previous_hook, previous_loop
        truthy(ok, result)
        local effective = Config.diagnostic_session(config)
        for _, value in pairs(effective.capabilities) do equal(value, false) end
        equal(config.capabilities.startAllInvasions, true, "in-memory quarantine modified persistent configuration")
        local laboratory = Config.diagnostic_session(config, "laboratory-native-test")
        truthy(laboratory.capabilities.chatCommands and laboratory.capabilities.startAllInvasions)
        equal(laboratory.capabilities.grantItems, false)
        equal(laboratory.schedules[1].enabled, false)
    end)

    test("laboratory chat and gameplay controls work without a manual preflight", function()
        local old_console, old_loop, old_getenv = _G.RegisterConsoleCommandGlobalHandler, _G.LoopInGameThreadWithDelay, os.getenv
        local config = Config.defaults()
        for name in pairs(config.capabilities) do config.capabilities[name] = name ~= "grantItems" end
        local hooks, received, principal_calls, poll, ticks = {}, nil, 0, nil, 0
        local bridge = Bridge.new({ config = config, logger = { warn = function() end }, delivery_profile = "laboratory-native-test" })
        bridge.preflight_environment = function() return true end
        bridge._register_hook = function(_, name, _, callback) hooks[name] = callback; return true end
        bridge.command_principal = function() principal_calls = principal_calls + 1; return { uid = "fixture" } end
        bridge.director = { handle_chat = function(_, _, text) received = text end,
            tick = function() if bridge:native_start_guard() then ticks = ticks + 1 end end }
        _G.RegisterConsoleCommandGlobalHandler = function() end
        _G.LoopInGameThreadWithDelay = function(_, callback) poll = callback; return 1 end
        os.getenv = function(name) if name == "COMPUTERNAME" then return "IMOUTO" end; return old_getenv(name) end
        local ok, failure = pcall(function()
            truthy(bridge:register())
            truthy(hooks.chat)
            truthy(hooks.damage and hooks.invasion_start and hooks.select_invaders)
            truthy(bridge.periodic_active)
            truthy(bridge:native_start_guard())
            equal(bridge.preflight_diagnostic, nil)
            poll()
            equal(ticks, 1)
            hooks.chat({}, "ordinary chat")
            equal(principal_calls, 0)
            hooks.chat({}, "!siege status")
            equal(received, "!siege status")
            equal(principal_calls, 1)
            poll()
            equal(ticks, 2)
            bridge:unregister()
            equal(bridge:native_start_guard(), false)
            poll()
            equal(ticks, 2)
        end)
        _G.RegisterConsoleCommandGlobalHandler, _G.LoopInGameThreadWithDelay, os.getenv = old_console, old_loop, old_getenv
        truthy(ok, failure)
    end)

    test("chat queries work while mutations are blocked by incomplete startup", function()
        local config = Config.defaults()
        for name in pairs(config.capabilities) do config.capabilities[name] = name ~= "grantItems" end
        local now, writes, replies = 100, 0, {}
        local bridge = Bridge.new({ config = config, logger = {}, delivery_profile = "laboratory-native-test" })
        bridge.send_chat = function(_, text) replies[#replies + 1] = text; return true end
        bridge._resolve_world_manager = function() error("locked chat reached native preflight") end
        local director = Director.new({
            config = config, bridge = bridge, clock = function() return now end,
            logger = { info = function() end, warn = function() end, error = function() end },
            store = { load_snapshot = function() return nil end,
                append = function() writes = writes + 1; return true end, save_snapshot = function() return true end },
        })
        local principal = { uid = "fixture-admin", palworldAdminReadable = true, palworldAdmin = true }
        for _, command in ipairs({
            "!siege status", "!siege profiles", "!siege schedule", "!siege score", "!siege leaderboard",
            "!ped status", "!siege start native 0", "!ped start native 0",
            "!siege cancel", "!siege abort", "!siege resolve", "!siege reset",
        }) do
            local previous = #replies
            truthy(director:handle_chat(principal, command))
            truthy(#replies > previous, "chat command had no response")
            equal(writes, 0, "locked command wrote an event or cooldown intent")
            now = now + 3
        end
    end)

    test("interrupted local ingress blocks console registration before any diagnostic can run", function()
        local fs = require("ped.filesystem")
        local original_exists = fs.exists
        local original_console, original_loop, original_enqueue = _G.RegisterConsoleCommandGlobalHandler, _G.LoopAsync, _G.ExecuteInGameThread
        local handlers, polls = 0, 0
        fs.exists = function() return true end
        _G.RegisterConsoleCommandGlobalHandler = function() handlers = handlers + 1 end
        _G.LoopAsync = function() polls = polls + 1 end
        _G.ExecuteInGameThread = function() error("unexpected game-thread request") end
        local ok, failure = pcall(function()
            local bridge = Bridge.new({ config = Config.defaults(), logger = {}, diagnostic_command_directory = "fixture" })
            local registered, reason = bridge:register()
            equal(registered, false)
            truthy(reason:match("pending/in%-flight"))
            equal(handlers, 0)
            equal(polls, 0)
            equal(bridge:diagnose_preflight(TOKEN, "100-0001-ue4ss-version"), false)
        end)
        fs.exists = original_exists
        _G.RegisterConsoleCommandGlobalHandler, _G.LoopAsync, _G.ExecuteInGameThread = original_console, original_loop, original_enqueue
        truthy(ok, failure)
    end)

    test("preflight crash scheduler intent remains recovery-required and cannot rearm after restart", function()
        local config = Config.defaults()
        local saved = {
            schemaVersion = 2,
            director = { schemaVersion = 2, status = "idle", nonce = 0 },
            rewards = { schemaVersion = 1, obligations = {}, order = {} },
            scheduler = { schemaVersion = 2, manualNonce = 1, occurrences = {
                crashed = { status = "starting", manual = true, profileId = "native", intendedAt = 100 },
            } },
        }
        local writes = {}
        local store = { load_snapshot = function() return util.deep_copy(saved) end,
            append = function(_, kind, _, snapshot) writes[#writes + 1] = { kind = kind, snapshot = util.deep_copy(snapshot) }; return true end,
            save_snapshot = function() return true end }
        local logger = { info = function() end, warn = function() end, error = function() end }
        local bridge = Bridge.new({ config = config, logger = logger })
        local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger })
        equal(director.scheduler.state.occurrences.crashed.status, "recovery_required")
        equal(writes[1].kind, "scheduler_recovery_required")
        equal(writes[1].snapshot.scheduler.occurrences.crashed.status, "recovery_required")
        equal(director:arm_start("console", "native", 0), false)
        director:tick()
        equal(#writes, 1)
        equal(director.scheduler.state.manualNonce, 1)
    end)

    test("read-only diagnostic command is console-only and does not call full preflight", function()
        local calls = 0
        local bridge = { diagnose_preflight = function(_, token, step)
            calls = calls + 1; equal(token, TOKEN); equal(step, "expected"); return true, "one operation" end }
        local director = Director.new({ config = Config.defaults(), bridge = bridge,
            store = { load_snapshot = function() return nil end }, logger = {} })
        equal(director:handle_operator_command("diagnose-preflight " .. TOKEN .. " expected", "chat:admin"), false)
        equal(calls, 0)
        truthy(director:handle_operator_command("diagnose-preflight " .. TOKEN .. " expected", "console"))
        equal(calls, 1)
    end)

    test("local diagnostic ingress claims explicit requests and never replays startup leftovers", function()
        local files, queued = {}, {}
        local fs = {
            exists = function(name) return files[name] ~= nil end,
            read = function(name) return files[name] end,
            write = function(name, bytes) files[name] = bytes; return true end,
            remove = function(name) files[name] = nil; return true end,
            rename = function(from, to) if not files[from] or files[to] then return false end; files[to] = files[from]; files[from] = nil; return true end,
        }
        local calls = 0
        local ingress = Ingress.new({ directory = "fixture", filesystem = fs,
            enqueue = function(callback) queued[#queued + 1] = callback end,
            execute = function(token, step) calls = calls + 1; equal(token, nil); equal(step, nil); return true, "Next: 100-0001-ue4ss-version" end })
        ingress:poll()
        equal(#queued, 0)
        files[ingress.request] = json.encode({ schemaVersion = 1, id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", preview = true,
            confirmation = TOKEN, expectedStep = "100-0001-ue4ss-version" })
        ingress:poll()
        equal(#queued, 1)
        equal(calls, 0, "request bypassed game-thread dispatch")
        truthy(files[ingress.claimed])
        ingress:poll()
        equal(#queued, 1)
        local restarted = Ingress.new({ directory = "fixture", filesystem = fs, execute = function() error("replayed") end, enqueue = function() error("replayed") end })
        truthy(restarted.blocked)
        restarted:poll()
        queued[1]()
        equal(calls, 1)
        equal(files[ingress.claimed], nil)
        equal(json.decode(files[ingress.response]).id, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        files[ingress.request] = "pending from previous boot"
        local stale = Ingress.new({ directory = "fixture", filesystem = fs })
        truthy(stale.blocked)
        stale:poll()
        equal(files[ingress.request], "pending from previous boot")
    end)
end