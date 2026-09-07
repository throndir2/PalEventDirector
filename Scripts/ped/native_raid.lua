local Layout = require("ped.native_layout")
local util = require("ped.util")

local Raid = {}
Raid.control_grade = 1

local SIGNATURE_ERROR = "Native raid bootstrap signature is unsupported"
local SCOPE_ERROR = "Native raid bootstrap scope is invalid"
local INITIALIZATION_ERROR = "Native raid state did not initialize"
local INFO_CLASS = "/Script/Pal.PalInvaderInfo"
local FIELD_KINDS = {
    ObjectProperty = true, ClassProperty = true, StructProperty = true, ByteProperty = true,
    EnumProperty = true, IntProperty = true, Int64Property = true, FloatProperty = true, DoubleProperty = true,
}

local function layout_report(access, label)
    return function(fields, expected, actual_count, expected_count)
        access.logger:error("Native raid bootstrap layout mismatch", {
            layout = label, actualFields = actual_count, expectedFields = expected_count,
        })
        for field_name, field in pairs(fields) do
            local safe_name = type(field_name) == "string" and #field_name <= 96
                and field_name:match("^[A-Za-z_][A-Za-z0-9_]*$") and not field_name:find(string.rep("%x", 32))
            access.logger:error("Native raid bootstrap field metadata", {
                layout = label, field = safe_name and field_name or "withheld-field",
                kind = FIELD_KINDS[field.kind] and field.kind or "unsupported",
                offset = util.is_integer(field.offset) and math.abs(field.offset) < 1048576 and field.offset or -1,
            })
        end
    end
end

local function expect_struct(field, name, expected, access)
    local owner = field:GetStruct()
    if not access.valid(owner) or owner:GetFName():ToString():lower() ~= name:lower() then error(SIGNATURE_ERROR, 0) end
    return Layout.expect(owner, expected, access.valid, SIGNATURE_ERROR, layout_report(access, name))
end

local function expect_transform(field, access)
    local fields = expect_struct(field, "Transform", {
        Rotation = { "StructProperty", 0 }, Translation = { "StructProperty", 32 }, Scale3D = { "StructProperty", 64 },
    }, access)
    expect_struct(fields.Rotation.field, "Quat", {
        X = { "DoubleProperty", 0 }, Y = { "DoubleProperty", 8 },
        Z = { "DoubleProperty", 16 }, W = { "DoubleProperty", 24 },
    }, access)
    for _, name in ipairs({ "Translation", "Scale3D" }) do
        expect_struct(fields[name].field, "Vector", {
            X = { "DoubleProperty", 0 }, Y = { "DoubleProperty", 8 }, Z = { "DoubleProperty", 16 },
        }, access)
    end
end

local function expect_function(owner, method, expected, access)
    local fn = owner[method]
    if not access.valid(fn) or fn:type() ~= "UFunction" or (fn:GetFunctionFlags() & 0x2400) ~= 0x2400 then
        error(SIGNATURE_ERROR, 0)
    end
    return Layout.expect(fn, expected, access.valid, SIGNATURE_ERROR, layout_report(access, method))
end

function Raid.prepare(bridge, access)
    access.logger = bridge.logger
    local library = bridge:_static_find("/Script/Engine.Default__GameplayStatics")
    local class = bridge:_static_find(INFO_CLASS)
    if not access.valid(library) or not access.valid(class) or class:type() ~= "UClass"
        or class:GetFName():ToString():lower() ~= "palinvaderinfo" then
        error(SCOPE_ERROR, 0)
    end
    local begin = expect_function(library, "BeginDeferredActorSpawnFromClass", {
        WorldContextObject = { "ObjectProperty", 0 }, ActorClass = { "ClassProperty", 8 },
        SpawnTransform = { "StructProperty", 16 }, CollisionHandlingOverride = { "EnumProperty", 112 },
        Owner = { "ObjectProperty", 120 }, ReturnValue = { "ObjectProperty", 128 },
    }, access)
    expect_transform(begin.SpawnTransform.field, access)
    local finish = expect_function(library, "FinishSpawningActor", {
        Actor = { "ObjectProperty", 0 }, SpawnTransform = { "StructProperty", 16 },
        ReturnValue = { "ObjectProperty", 112 },
    }, access)
    expect_transform(finish.SpawnTransform.field, access)
    local remaining = bridge:_static_find("/Script/Pal.PalInvaderInfo:GetRemainInvadeStartRealTimeSeconds")
    if not access.valid(remaining) or remaining:type() ~= "UFunction"
        or (remaining:GetFunctionFlags() & 0x2400) ~= 0x400 then error(SIGNATURE_ERROR, 0) end
    Layout.expect(remaining, { ReturnValue = { "FloatProperty", 0 } }, access.valid, SIGNATURE_ERROR,
        layout_report(access, "GetRemainInvadeStartRealTimeSeconds"))
    return { library = library, class = class }
end

function Raid.start(bridge, access, base_id, target, scope)
    local request = bridge.request_windows[base_id]
    local ready, bindings = bridge:_native_step("raid-bootstrap-signatures", function()
        return Raid.prepare(bridge, access)
    end)
    if not ready then return false, bindings end
    local checked, available = bridge:_native_step("raid-bootstrap-scope", function()
        if not access.valid(bridge.event_world) or not access.valid(bridge.event_manager)
            or not access.valid(target.base) or access.guid(target.nativeId) ~= base_id then error(SCOPE_ERROR, 0) end
        local current = bridge.event_manager.InvaderInfo
        return current == nil or current:IsValid() == false
    end)
    if not checked then return false, available end
    if not available then
        return false, "A native raid-state actor already exists. A second bootstrap would replace its ownership; no actor or incident was created.",
            "raid-state-already-exists"
    end
    local captured, capture_error = bridge:_capture_system_incident_baseline(request.baseline, scope)
    if not captured then return false, capture_error end
    local transform = {
        Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
        Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 },
    }
    local spawned, info = bridge:_native_call("raid-bootstrap-spawn-deferred", bindings.library,
        "BeginDeferredActorSpawnFromClass", bridge.event_world, bindings.class, transform, 0, nil)
    if not spawned then return false, info end
    local initialized, initialization_error = bridge:_native_step("raid-bootstrap-inputs", function()
        if not access.valid(info) or not info:IsA(INFO_CLASS) then error(INITIALIZATION_ERROR, 0) end
        request.raidInfo = info
        local world_ok, world = bridge:_native_call("raid-bootstrap-deferred-world", info, "GetWorld")
        if not world_ok then return end
        if not access.same(world, bridge.event_world) then error(SCOPE_ERROR, 0) end
        -- Keep the fresh actor's default due time; DateTime is opaque to this Lua binding.
        info.BaseCampId = target.nativeId
        info.InvadeGrade = Raid.control_grade
        if access.guid(info.BaseCampId) ~= base_id or info.InvadeGrade ~= Raid.control_grade then error(INITIALIZATION_ERROR, 0) end
    end)
    if not initialized then return false, initialization_error end
    local due_ok, remaining = bridge:_native_call("raid-bootstrap-due-time", info, "GetRemainInvadeStartRealTimeSeconds")
    if not due_ok then return false, remaining end
    local checked_time, time_error = bridge:_native_step("raid-bootstrap-due-result", function()
        if type(remaining) ~= "number" or remaining ~= remaining or math.abs(remaining) == math.huge or remaining > 0 then
            error("Native raid default start time is not immediately due", 0)
        end
    end)
    if not checked_time then return false, time_error end
    bridge.blueprint_used = true
    local finished, actor = bridge:_native_call("raid-bootstrap-finish-spawning", bindings.library,
        "FinishSpawningActor", info, transform)
    if not finished then return false, actor end
    local verified, result = bridge:_native_step("raid-bootstrap-registration", function()
        if not access.same(actor, info) or not access.same(bridge.event_manager.InvaderInfo, info) then
            error(INITIALIZATION_ERROR, 0)
        end
        local world_ok, world = bridge:_native_call("raid-bootstrap-actor-world", info, "GetWorld")
        if not world_ok then return end
        if not access.same(world, bridge.event_world) or access.guid(info.BaseCampId) ~= base_id then error(SCOPE_ERROR, 0) end
        bridge.logger:info("Native raid-state actor initialized", {
            grade = Raid.control_grade, nativeRegistration = true, directBlueprintCall = false,
        })
        return info
    end)
    if not verified then return false, result end
    return true, result
end

return Raid
