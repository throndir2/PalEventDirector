local Diagnostic = {}
Diagnostic.__index = Diagnostic

local BUILD_ID = "24575149"
local RUNTIME_TAG = "2281fa31"
local RUNTIME_API = "3.0.1"
local TOKEN = "confirm-disposable-readonly"
local CALL_BUFFER_BYTES = 0x200 -- Verified in the pinned UE4SS LuaUFunction.hpp.
local FAILURE_CLASSES = {
    ["lua-operation"] = true,
    ["metadata-method-lookup"] = true,
    ["metadata-enumeration"] = true,
}
local ERROR_SIGNATURES = {
    { text = "A function requiring userdata as param #1 was called without userdata at param #1", code = "receiver-required" },
    { text = "has no instance inside lua_instances unordered map", code = "unregistered-lua-state" },
    { text = "userdata_internal_type", code = "invalid-userdata" },
    { text = "attempt to call a nil value", code = "non-callable-value" },
    { text = "attempt to call a userdata value", code = "non-callable-value" },
    { text = "FName constructor unavailable", code = "fname-constructor-unavailable" },
    { text = "Native probe data has an unexpected type", code = "probe-data-shape" },
    { text = "Native probe data changed during observation", code = "probe-data-changed" },
    { text = "Native probe table schema is unsupported", code = "probe-table-schema" },
    { text = "Native probe metadata is unsupported", code = "probe-metadata" },
    { text = "Native probe observer registration failed", code = "probe-hook-registration" },
    { text = "[Lua::call_function]", code = "callback-error" },
}

local function failure_detail(value)
    if type(value) ~= "string" then return "non-string-error" end
    local prefix = value:sub(1, 1024)
    for _, signature in ipairs(ERROR_SIGNATURES) do
        if prefix:find(signature.text, 1, true) then return signature.code end
    end
    return "unclassified-lua-error"
end

local function integer(value)
    return type(value) == "number" and value == math.floor(value) and value == value
end

function Diagnostic.new(options)
    options = options or {}
    local self = setmetatable({
        config = assert(options.config),
        record = assert(options.record),
        engine = options.engine or _G,
        getenv = options.getenv or os.getenv,
        run_id = options.run_id or os.time(),
        ordinal = 0,
        pending = nil,
        running = false,
        halted = false,
        completed = false,
        stop_reason = nil,
        live_objects = {},
        native_readiness = options.native_readiness == true,
        native_ready = false,
        ready_world = nil,
    }, Diagnostic)
    assert(integer(self.run_id) and self.run_id >= 0)
    self.thread = coroutine.create(function() self:_plan() end)
    return self
end

function Diagnostic:_stop(reason)
    -- Only fixed, developer-authored reasons enter output. Native errors are discarded.
    self.stop_reason = reason
    error("preflight diagnostic halted", 0)
end

function Diagnostic:_require(condition, reason)
    if not condition then self:_stop(reason) end
end

function Diagnostic:_op(name, object_valid, callback, is_validity_check, failure_class)
    return coroutine.yield({
        name = name,
        object_valid = object_valid == true,
        callback = callback,
        is_validity_check = is_validity_check == true,
        failure_class = FAILURE_CLASSES[failure_class] and failure_class or "lua-operation",
    })
end

function Diagnostic:_valid(name, object)
    self:_require(object ~= nil, "Required diagnostic object is absent; stop and preserve the breadcrumb log.")
    local result = self:_op(name .. "-valid", false, function() return object:IsValid() end, true)
    self:_require(result == true, "Object validity check failed; stop and preserve the breadcrumb log.")
    self.live_objects[#self.live_objects + 1] = { name = name, object = object }
end

function Diagnostic:_lookup(name, path)
    local object = self:_op(name .. "-lookup", false, function() return self.engine.StaticFindObject(path) end)
    self:_valid(name, object)
    return object
end

function Diagnostic:_properties(name, owner, maximum)
    local enumerate = self:_op(name .. "-properties-method", true, function()
        return owner.ForEachProperty
    end, false, "metadata-method-lookup")
    self:_require(type(enumerate) == "function",
        "Property enumeration method is unavailable or not callable on this wrapper; signature validation stopped.")
    local result = self:_op(name .. "-properties", true, function()
        local properties = {}
        -- This callback only retains metadata handles; it calls no reflected methods.
        -- LuaMadeSimple consumes the explicit receiver before reading the callback.
        enumerate(owner, function(property)
            properties[#properties + 1] = property
            if #properties > maximum then return true end
            -- get_bool(false) pops the result before the pinned iterator's discard.
            -- Nil continuation avoids that double removal; true still bounds work.
            return nil
        end)
        return properties
    end, false, "metadata-enumeration")
    self:_require(type(result) == "table" and #result <= maximum, "Unexpected property inventory; signature validation stopped.")
    return result
end

function Diagnostic:_metadata_value(name, expected_kind, callback)
    local value = self:_op(name, true, callback)
    self:_require(value ~= nil, "Copied metadata value is unavailable; signature validation stopped.")
    -- Pinned FName/FieldClass values have no IsValid method. Their remote owners
    -- remain in live_objects; validate the copied wrapper before reading it.
    local kind = self:_op(name .. "-type", true, function() return value:type() end)
    self:_require(kind == expected_kind, "Copied metadata wrapper type differs from the pinned binding.")
    return value
end

function Diagnostic:_metadata_name(name, owner)
    local value = self:_metadata_value(name .. "-fname", "FName", function() return owner:GetFName() end)
    local text = self:_op(name .. "-name", true, function() return value:ToString() end)
    self:_require(type(text) == "string", "Metadata name is unavailable; signature validation stopped.")
    return text
end

function Diagnostic:_signature(label, function_name, result_kind, result_class)
    local path = "/Script/Pal.PalUtility:" .. function_name
    local fn = self:_lookup(label .. "-function", path)
    local kind = self:_op(label .. "-function-type", true, function() return fn:type() end)
    self:_require(kind == "UFunction", "The requested metadata is not a UFunction.")
    local flags = self:_op(label .. "-function-flags", true, function() return fn:GetFunctionFlags() end)
    self:_require(integer(flags) and (flags & 0x2400) == 0x2400, "Native/static UFunction flags do not match the audited declaration.")
    local properties = self:_properties(label, fn, 2)
    self:_require(#properties == 2, "UFunction parameter/return count does not match the audited declaration.")
    local input, output, return_offset
    for index, property in ipairs(properties) do
        local prefix = label .. "-parameter-" .. index
        self:_valid(prefix, property)
        local name = self:_metadata_name(prefix, property)
        local is_input = name == "WorldContextObject"
        local is_return = name == "ReturnValue"
        self:_require(is_input or is_return, "UFunction parameter/return names differ from the audited declaration.")
        local field_class = self:_metadata_value(prefix .. "-field-class", "FieldClass", function() return property:GetClass() end)
        local field_kind = self:_metadata_name(prefix .. "-field-class", field_class)
        self:_require(field_kind == (is_input and "ObjectProperty" or result_kind),
            "UFunction parameter/return property types differ from the audited declaration.")
        local offset = self:_op(prefix .. "-offset", true, function() return property:GetOffset_Internal() end)
        self:_require(integer(offset) and offset == (is_input and 0 or 8), "UFunction parameter/return offsets differ from the expected Windows x64 pointer layout.")
        if is_input then
            self:_require(input == nil, "Duplicate UFunction input property.")
            input = property
        else
            self:_require(output == nil, "Duplicate UFunction return property.")
            output, return_offset = property, offset
        end
    end
    self:_require(input ~= nil and output ~= nil, "Incomplete UFunction signature.")
    local input_class = self:_op(label .. "-input-class", true, function() return input:GetPropertyClass() end)
    self:_valid(label .. "-input-class", input_class)
    local input_name = self:_op(label .. "-input-class-name", true, function() return input_class:GetFullName() end)
    self:_require(input_name == "Class /Script/CoreUObject.Object", "WorldContextObject is not the audited UObject pointer type.")
    if result_kind == "ObjectProperty" then
        local output_class = self:_op(label .. "-return-class", true, function() return output:GetPropertyClass() end)
        self:_valid(label .. "-return-class", output_class)
        local output_name = self:_op(label .. "-return-class-name", true, function() return output_class:GetFullName() end)
        self:_require(output_name == "Class /Script/Pal." .. result_class, "UFunction return class differs from the audited pointer type.")
    end
    return output, return_offset
end

function Diagnostic:_option_readiness(utility, world)
    self:_signature("options", "GetOptionSubsystem", "ObjectProperty", "PalOptionSubsystem")
    self:_valid("utility-before-options", utility)
    self:_valid("world-before-options", world)
    local options = self:_op("get-option-subsystem", true, function() return utility:GetOptionSubsystem(world) end)
    self:_valid("options-subsystem", options)
    local options_world = self:_op("options-get-world", true, function() return options:GetWorld() end)
    self:_valid("options-world", options_world)
    local expected_address = self:_op("options-expected-world-address", true, function() return world:GetAddress() end)
    local actual_address = self:_op("options-world-address", true, function() return options_world:GetAddress() end)
    self:_require(integer(expected_address) and expected_address > 0 and actual_address == expected_address,
        "Option subsystem belongs to a different world; addresses will not be logged.")
    local settings = self:_metadata_value("options-settings-view", "UScriptStruct", function() return options.OptionWorldSettings end)
    local enabled = self:_op("options-invasion-enabled", true, function() return settings.bEnableInvaderEnemy end)
    self:_require(enabled == true, "Native enemy invasions are disabled or unreadable in the world-scoped option subsystem.")
    self.native_ready, self.ready_world = true, world
end

function Diagnostic:_plan()
    local api = self:_op("ue4ss-version", false, function() return { self.engine.UE4SS.GetVersion() } end)
    self:_require(type(api) == "table" and api[1] == 3 and api[2] == 0 and api[3] == 1, "Runtime API differs from the pinned diagnostic build.")

    local utility = self:_lookup("utility", "/Script/Pal.Default__PalUtility")
    local controller = self:_op("controller-lookup", false, function() return self.engine.FindFirstOf("PalPlayerController") end)
    self:_valid("controller", controller)
    local world = self:_op("controller-get-world", true, function() return controller:GetWorld() end)
    self:_valid("world", world)

    -- Screen the current build's exposed metadata before calling the first new suspect.
    -- GetWorld and GetAddress below are UE4SS UObject bindings, not UFunctions.
    self:_signature("manager", "GetInvaderManager", "ObjectProperty", "PalInvaderManager")
    self:_valid("utility-before-manager", utility)
    self:_valid("world-before-manager", world)
    local manager = self:_op("get-invader-manager", true, function() return utility:GetInvaderManager(world) end)
    self:_valid("manager", manager)
    local manager_world = self:_op("manager-get-world", true, function() return manager:GetWorld() end)
    self:_valid("manager-world", manager_world)
    local manager_address = self:_op("manager-get-address", true, function() return manager:GetAddress() end)
    self:_require(integer(manager_address) and manager_address > 0, "Manager address check failed; the address will not be logged.")
    local world_address = self:_op("world-get-address", true, function() return world:GetAddress() end)
    local manager_world_address = self:_op("manager-world-get-address", true, function() return manager_world:GetAddress() end)
    self:_require(integer(world_address) and world_address > 0 and world_address == manager_world_address, "Manager world identity check failed; addresses will not be logged.")
    manager_address, world_address, manager_world_address = nil, nil, nil

    if self.native_readiness then
        self:_option_readiness(utility, world)
        return
    end

    local result_property, return_offset = self:_signature("settings", "GetOptionWorldSettings", "StructProperty")
    local settings_type = self:_op("settings-return-type", true, function() return result_property:GetStruct() end)
    self:_valid("settings-return-type", settings_type)
    local type_name = self:_op("settings-return-type-name", true, function() return settings_type:GetFullName() end)
    self:_require(type_name == "ScriptStruct /Script/Pal.PalOptionWorldSettings", "Settings return struct differs from the audited declaration.")
    local fields = self:_properties("settings-layout", settings_type, 256)
    self:_require(#fields > 0, "Settings struct layout is unavailable; its getter must not be invoked.")
    -- Last-declared fields can prove overflow without materializing ANY settings values.
    -- Inspect offsets only: no names, credentials, UIDs, or settings data are read here.
    for index = #fields, 1, -1 do
        local field = fields[index]
        self:_valid("settings-layout-field-" .. index, field)
        local offset = self:_op("settings-layout-field-" .. index .. "-offset", true, function() return field:GetOffset_Internal() end)
        self:_require(integer(offset) and offset >= 0, "Settings field offset is unavailable; its getter must not be invoked.")
        if return_offset + offset + 1 > CALL_BUFFER_BYTES then
            self:_stop("GetOptionWorldSettings is blocked: runtime field offsets exceed the pinned UE4SS 512-byte call buffer. No settings value or invasion was requested.")
        end
    end
    -- This runtime does not expose ParmsSize/PropertiesSize through its Lua API.
    -- A small lower bound is NOT an upper-bound proof; never guess a safe ABI.
    self:_stop("GetOptionWorldSettings is blocked: exact ParmsSize/return extent cannot be verified with this pinned Lua API. No settings value, enable flag, active-invasion scan, eligibility traversal, or dispatch was requested.")
end

function Diagnostic:_gate()
    if self.getenv("COMPUTERNAME") ~= "IMOUTO" then return false, "Preflight diagnostics are IMOUTO-only." end
    if self.config.mode ~= "laboratory" then return false, "Preflight diagnostics require laboratory mode." end
    if self.getenv("PAL_EVENT_DIRECTOR_SERVER_BUILD_ID") ~= BUILD_ID
        or self.getenv("PAL_EVENT_DIRECTOR_UE4SS_TAG") ~= RUNTIME_TAG
        or self.getenv("PAL_EVENT_DIRECTOR_UE4SS_API_VERSION") ~= RUNTIME_API then
        return false, "Pinned build/runtime attestation is absent or mismatched; use the diagnostic launcher."
    end
    return true
end

function Diagnostic:_advance(value)
    local ok, yielded = coroutine.resume(self.thread, value)
    if not ok then
        self.halted = true
        self.native_ready, self.ready_world = false, nil
        self.pending = nil
        self.thread = nil -- Drop every retained native handle; do not stringify yielded errors.
        self.live_objects = {}
        return false, self.stop_reason or "Diagnostic Lua operation failed; preserve breadcrumbs and do not retry this session."
    end
    if coroutine.status(self.thread) == "dead" then
        self.completed, self.thread, self.pending = true, nil, nil
        return true
    end
    self.ordinal = self.ordinal + 1
    self.pending = yielded
    self.pending.step = string.format("%d-%04d-%s", self.run_id, self.ordinal, yielded.name)
    return true
end

function Diagnostic:_record(phase, object_valid, suffix)
    local ok, saved = pcall(self.record, self.pending.step .. (suffix or "") .. "." .. phase, BUILD_ID, object_valid == true)
    return ok and saved == true
end

function Diagnostic:_halt()
    self.halted, self.running, self.thread, self.pending = true, false, nil, nil
    self.native_ready, self.ready_world = false, nil
    self.live_objects = {}
end

function Diagnostic:run(confirmation, expected_step)
    local allowed, reason = self:_gate()
    if not allowed then return false, reason end
    if self.running then return false, "A diagnostic operation is already in progress." end
    if self.halted then return false, self.stop_reason or "Diagnostic session halted; preserve breadcrumbs. No retry is permitted." end
    if self.completed then return false, "Diagnostic session is complete; no diagnostic operation will run again." end
    if confirmation ~= nil and confirmation ~= TOKEN then return false, "Use diagnose-preflight confirm-disposable-readonly <expected-step>." end
    if not self.pending then
        local ready, advance_error = self:_advance()
        if not ready then return false, advance_error end
    end
    if confirmation == nil then return true, "Next: " .. self.pending.step .. ". Confirmation executes ONE read-only operation; a native crash remains possible." end
    if expected_step ~= self.pending.step then return false, "Exact previewed step is required; no operation ran. Next: " .. self.pending.step end
    self.running = true
    -- Console/file ingress runs on the game thread. Recheck every owning UObject and
    -- metadata handle in the same callback as its use, not only in a prior command.
    for index, entry in ipairs(self.live_objects) do
        local suffix = "-liveness-" .. index
        if not self:_record("before", false, suffix) then
            self:_halt()
            return false, "Liveness before-marker could not be flushed; operation not executed."
        end
        local live_ok, live = pcall(function() return entry.object:IsValid() end)
        if not live_ok or not self:_record("after", live == true, suffix) or live ~= true then
            self:_halt()
            return false, "A retained diagnostic object is no longer valid, or its check could not be recorded; session halted before use."
        end
    end
    if not self:_record("before", self.pending.object_valid) then
        self:_halt()
        return false, "Before-marker could not be flushed; no native operation ran and this session is halted."
    end
    -- pcall only contains ordinary Lua errors. Stack-cookie fail-fast is NOT catchable.
    local ok, result = pcall(self.pending.callback)
    if not ok then
        self.stop_reason = "Read-only operation failed [" .. self.pending.failure_class .. "/" .. failure_detail(result)
            .. "]; raw error suppressed. Preserve the before-marker; do not retry."
        self:_halt()
        return false, self.stop_reason
    end
    local object_valid = self.pending.object_valid
    if self.pending.is_validity_check then object_valid = result == true end
    if not self:_record("after", object_valid) then
        self:_halt()
        return false, "Operation returned but after-marker could not be flushed; do not retry this session."
    end
    local completed_step = self.pending.step
    local advanced, advance_error = self:_advance(result)
    self.running = false
    if not advanced then return false, advance_error end
    if self.completed then
        return true, "Returned: " .. completed_step .. ". Inspect its after-marker. Diagnostic inspection completed; this is not a gameplay prerequisite. No dispatch ran."
    end
    return true, "Returned: " .. completed_step .. ". Inspect its after-marker. Next: " .. self.pending.step .. ". No dispatch ran."
end

Diagnostic.classify_error = failure_detail
return Diagnostic