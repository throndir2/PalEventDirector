local Layout = require("ped.native_layout")
local util = require("ped.util")
local bounties = require("ped.bounties")
local PlacementSearch = require("ped.placement_search")
local invoke_function = require("ped.native_observer").invoke
local Qualification = require("ped.shape_qualification")
local Cadence = require("ped.cadence_trial")

local Native = {}
Native.__index = Native

local SIGNATURE = "Custom assault signature is unsupported"
local SCOPE = "Custom assault scope is invalid"
local OWNERSHIP = "Custom assault ownership is unreadable"
local IDENTITY = "Custom assault actor identity changed"
local INITIALIZATION = "Custom assault initialization is incomplete"
local ACTION = "Custom assault native action failed"
local STARTUP_PAWN = bounties.pawn_class("BOSS_Hunter_Rifle")
local CLASSES = {
    travel = "/Game/Pal/Blueprint/Controller/AIAction/Visitor/BP_AIAction_Visitor_TravelToBaseCamp.BP_AIAction_Visitor_TravelToBaseCamp_C",
    encounter = "/Game/Pal/Blueprint/Controller/AIAction/NPC/BP_AIAction_NPC_Encount.BP_AIAction_NPC_Encount_C",
    combat = "/Game/Pal/Blueprint/Controller/AIAction/NPC/BP_AIAction_NPC_CombatBase.BP_AIAction_NPC_CombatBase_C",
    melee = "/Game/Pal/Blueprint/Action/NPC/BP_Action_NPC_MeleeAttack.BP_Action_NPC_MeleeAttack_C",
}
local TERMINAL = { dead = true, captured = true, missing = true }

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function vector(value)
    if value == nil or not finite(value.X) or not finite(value.Y) or not finite(value.Z) then error(SCOPE, 0) end
    return { X = value.X, Y = value.Y, Z = value.Z }
end

local function distance_squared(left, right)
    local x, y, z = left.X - right.X, left.Y - right.Y, left.Z - right.Z
    return x * x + y * y + z * z
end

local function guid(value, allow_zero)
    if value == nil then error(OWNERSHIP, 0) end
    local copy, nonzero = {}, false
    for _, key in ipairs({ "A", "B", "C", "D" }) do
        local part = value[key]
        if not util.is_integer(part) or part < -2147483648 or part > 4294967295 then error(OWNERSHIP, 0) end
        copy[key] = part
        nonzero = nonzero or part ~= 0
    end
    if not allow_zero and not nonzero then error(IDENTITY, 0) end
    return copy
end

local function same_guid(left, right)
    for _, key in ipairs({ "A", "B", "C", "D" }) do
        if (left[key] & 0xffffffff) ~= (right[key] & 0xffffffff) then return false end
    end
    return true
end

local function full_id(value, allow_pending)
    if value == nil then error("Custom assault individual ID return is absent", 0) end
    return { PlayerUId = guid(value.PlayerUId, true), InstanceId = guid(value.InstanceId, allow_pending == true), DebugName = "" }
end

local function same_id(left, right)
    return same_guid(left.PlayerUId, right.PlayerUId) and same_guid(left.InstanceId, right.InstanceId)
end

local function is_zero(value)
    for _, key in ipairs({ "A", "B", "C", "D" }) do if value[key] ~= 0 then return false end end
    return true
end

local function member_key(member)
    return member.groupId .. ":" .. member.index
end

function Native.new(bridge, access)
    return setmetatable({ bridge = bridge, a = access, records = {}, classes = {}, placements = {}, placementSearches = {} }, Native)
end

function Native:release_tracking()
    self.records, self.placements, self.placementSearches = {}, {}, {}
    self.recoveryPending, self.recoveryStartedAt = nil, nil
    self.recoveryCursor, self.recoveryCompleted = nil, nil
end

function Native:_call(label, owner, method, ...)
    local ok, result = self.bridge:_native_call("custom-" .. label, owner, method, ...)
    if not ok then error(result, 0) end
    return result
end

function Native:_signature(path, expected)
    local fn = self.bridge:_static_find(path)
    if not self.a.valid(fn) or fn:type() ~= "UFunction" or (fn:GetFunctionFlags() & 0x400) == 0 then
        error(SIGNATURE, 0)
    end
    return Layout.expect(fn, expected, self.a.valid, SIGNATURE)
end

function Native:_struct(field, name, expected)
    local struct = field:GetStruct()
    if not self.a.valid(struct) or struct:GetFName():ToString():lower() ~= name:lower() then error(SIGNATURE, 0) end
    return Layout.expect(struct, expected, self.a.valid, SIGNATURE)
end

function Native:qualify()
    local spawn = self:_signature("/Script/Pal.PalNPCManager:SpawnNPCForServer", {
        SpawnInfo = { "StructProperty", 0 }, spawnCallback = { "DelegateProperty", 64 },
        ReturnValue = { "ObjectProperty", 80 },
    })
    local fields = self:_struct(spawn.SpawnInfo.field, "PalNPCSpawnInfo", {
        ControllerClass = { "ClassProperty", 0 }, CharacterID = { "NameProperty", 8 },
        Level = { "IntProperty", 16 }, Location = { "StructProperty", 24 },
        Yaw = { "FloatProperty", 48 }, Squad = { "ObjectProperty", 56 },
    })
    self:_struct(fields.Location.field, "Vector", {
        X = { "DoubleProperty", 0 }, Y = { "DoubleProperty", 8 }, Z = { "DoubleProperty", 16 },
    })
    self:_signature("/Script/Pal.PalCharacterManager:DespawnCharacterByHandle", {
        handle = { "ObjectProperty", 0 }, spawnCallback = { "DelegateProperty", 8 },
    })
    local action = self:_signature("/Script/Pal.PalAIActionComponent:SetActionClassParameter", {
        NewActionClass = { "ClassProperty", 0 }, Parameter = { "StructProperty", 8 },
        ReturnValue = { "ObjectProperty", 88 },
    })
    self:_struct(action.Parameter.field, "PalAIActionDynamicParameter", {
        GeneralActor1 = { "ObjectProperty", 0 }, GeneralVector1 = { "StructProperty", 8 },
        GeneralVector2 = { "StructProperty", 32 }, GeneralIndex1 = { "IntProperty", 56 },
        GeneralBool1 = { "BoolProperty", 60 }, GeneralInteger1 = { "IntProperty", 64 },
        GeneralInteger2 = { "IntProperty", 68 }, SelfDestructWaza = { "EnumProperty", 72 },
    })
    self:_signature("/Script/Pal.PalBaseCampModel:TryGetRandomPositionInside", {
        Origin = { "StructProperty", 0 }, Radius = { "FloatProperty", 24 },
        ToLocation = { "StructProperty", 32 }, ReturnValue = { "BoolProperty", 56 },
    })
    self:_signature("/Script/Pal.PalAIController:PalMoveToLocation", {
        Dest = { "StructProperty", 0 }, AcceptanceRadius = { "FloatProperty", 24 },
        bStopOnOverlap = { "BoolProperty", 28 }, bUsePathfinding = { "BoolProperty", 29 },
        bProjectDestinationToNavigation = { "BoolProperty", 30 }, bCanStrafe = { "BoolProperty", 31 },
        FilterClass = { "ClassProperty", 32 }, bAllowPartialPaths = { "BoolProperty", 40 },
        ReturnValue = { "ByteProperty", 41 },
    })
    self:_signature("/Script/Pal.PalUtility:GeneralTurnToActor_WithMovementRotationSpeed", {
        TurnActor = { "ObjectProperty", 0 }, GoalDirectionActor = { "ObjectProperty", 8 },
        DeltaTime = { "FloatProperty", 16 },
    })
    self:_signature("/Script/Pal.PalUtility:InConeShapAndDitance_Actor", {
        SelfActor = { "ObjectProperty", 0 }, TargetActor = { "ObjectProperty", 8 },
        Degree = { "FloatProperty", 16 }, Distance = { "FloatProperty", 20 },
        ReturnValue = { "BoolProperty", 24 },
    })
    self:_signature("/Script/Pal.PalAIActionComponent:GetCurrentAction_BP", { ReturnValue = { "ObjectProperty", 0 } })
    self:_signature("/Script/Pal.PalAICombatModule:GetTargetActor", { ReturnValue = { "ObjectProperty", 0 } })
    self:_signature("/Script/Pal.PalCharacterParameterComponent:GetHPRate", { ReturnValue = { "FloatProperty", 0 } })
    for _, method in ipairs({"IsEndInitialize","IsMagazineEmpty"}) do
        self:_signature("/Script/Pal.PalNPCAIWeaponHandle:" .. method, { ReturnValue={"BoolProperty",0} })
    end
    self:_signature("/Script/Pal.PalNPCAIWeaponHandle:GetRemainingBullet", {ReturnValue={"IntProperty",0}})
    self:_signature("/Script/Pal.PalNPCAIWeaponHandle:GetSphereCastRadius", {ReturnValue={"FloatProperty",0}})
    self:_signature("/Script/Pal.PalStateMachine:GetCurrentState", {ReturnValue={"ObjectProperty",0}})
    self:_signature("/Script/Pal.PalUtility:LineTraceToTarget_ForAIAttack", {
        SelfActor={"ObjectProperty",0},Target={"ObjectProperty",8},Radius={"FloatProperty",16},ReturnValue={"BoolProperty",20},
    })
    self:_signature("/Script/Pal.PalShooterComponent:GetHasWeapon", {ReturnValue={"ObjectProperty",0}})
    for _, method in ipairs({"CanShoot","CanAim","IsShooting","IsReloading","IsAiming","IsRequestAiming","IsPlayShootingAnimation"}) do
        self:_signature("/Script/Pal.PalShooterComponent:" .. method, {ReturnValue={"BoolProperty",0}})
    end
    for _, method in ipairs({"IsAiming_Layered","IsRequestAiming_Layered"}) do
        self:_signature("/Script/Pal.PalShooterComponent:" .. method, {
            Priority={"EnumProperty",0},ReturnValue={"BoolProperty",1},
        })
    end
    for _, method in ipairs({"InFanShap","InFanShapAimTarget"}) do
        self:_signature("/Script/Pal.PalUtility:" .. method, {
            SelfActor={"ObjectProperty",0},TargetActor={"ObjectProperty",8},Degree={"FloatProperty",16},
            ReturnValue={"BoolProperty",20},
        })
    end
    self:_signature("/Script/Pal.PalUtility:IsAIAttackAbleByPlayerCamera", {
        SelfActor={"ObjectProperty",0},TargetActor={"ObjectProperty",8},ReturnValue={"BoolProperty",16},
    })
    for _, method in ipairs({"GetPendingMovementInputVector","GetLastMovementInputVector"}) do
        self:_signature("/Script/Engine.Pawn:" .. method, {ReturnValue={"StructProperty",0}})
    end
    self:_signature("/Script/Engine.CharacterMovementComponent:GetCurrentAcceleration", {ReturnValue={"StructProperty",0}})
    self:_signature("/Script/Engine.Actor:K2_GetActorRotation", {ReturnValue={"StructProperty",0}})
    self:_signature("/Script/Engine.ActorComponent:GetOwner", {ReturnValue={"ObjectProperty",0}})
    self:_signature("/Script/Engine.ActorComponent:GetComponentTickInterval",{ReturnValue={"FloatProperty",0}})
    self:_signature("/Script/Engine.ActorComponent:IsComponentTickEnabled",{ReturnValue={"BoolProperty",0}})
    self:_signature("/Script/Pal.PalAIController:IsActiveAI",{ReturnValue={"BoolProperty",0}})
    for _,method in ipairs({"IsActive","IsPaused"}) do
        self:_signature("/Script/Pal.PalAIActionBase:"..method,{ReturnValue={"BoolProperty",0}})
    end
    self:_signature("/Script/Engine.KismetSystemLibrary:GetOuterObject", {
        Object={"ObjectProperty",0},ReturnValue={"ObjectProperty",8},
    })
    for _, method in ipairs({"IsMovingOnGround","IsFalling","IsFlying"}) do
        self:_signature("/Script/Engine.NavMovementComponent:" .. method, {ReturnValue={"BoolProperty",0}})
    end
    self:_signature("/Script/Pal.PalUtility:CanAdjustLocationToFloorFromCDO", {
        WorldContext = { "ObjectProperty", 0 }, InClass = { "ClassProperty", 8 },
        InLocation = { "StructProperty", 16 }, UpOffset = { "FloatProperty", 40 },
        OutLocation = { "StructProperty", 48 }, ShortRayLength = { "BoolProperty", 72 },
        ReturnValue = { "BoolProperty", 73 },
    })
    self:_signature("/Script/NavigationSystem.NavigationSystemV1:K2_ProjectPointToNavigation", {
        WorldContextObject = { "ObjectProperty", 0 }, Point = { "StructProperty", 8 },
        ProjectedLocation = { "StructProperty", 32 }, NavData = { "ObjectProperty", 56 },
        FilterClass = { "ClassProperty", 64 }, QueryExtent = { "StructProperty", 72 },
        ReturnValue = { "BoolProperty", 96 },
    })
    self:_signature("/Script/NavigationSystem.NavigationSystemV1:FindPathToLocationSynchronously", {
        WorldContextObject={"ObjectProperty",0},PathStart={"StructProperty",8},PathEnd={"StructProperty",32},
        PathfindingContext={"ObjectProperty",56},FilterClass={"ClassProperty",64},ReturnValue={"ObjectProperty",72},
    })
    for _, method in ipairs({"IsValid","IsPartial"}) do
        self:_signature("/Script/NavigationSystem.NavigationPath:"..method,{ReturnValue={"BoolProperty",0}})
    end
    self:_signature("/Script/NavigationSystem.NavigationPath:GetPathLength",{ReturnValue={"FloatProperty",0}})
    self:_signature("/Script/Engine.Actor:K2_GetRootComponent",{ReturnValue={"ObjectProperty",0}})
    self:_signature("/Script/Engine.Actor:GetLevel",{ReturnValue={"ObjectProperty",0}})
    self:_signature("/Script/Engine.Pawn:GetMovementComponent",{ReturnValue={"ObjectProperty",0}})
    for _, method in ipairs({"GetScaledCapsuleRadius","GetScaledCapsuleHalfHeight"}) do
        self:_signature("/Script/Engine.CapsuleComponent:"..method,{ReturnValue={"FloatProperty",0}})
    end
    self:_signature("/Script/Engine.PrimitiveComponent:GetWalkableSlopeOverride",{ReturnValue={"StructProperty",0}})
    self:_signature("/Script/Engine.KismetSystemLibrary:CapsuleOverlapComponents",{
        WorldContextObject={"ObjectProperty",0},CapsulePos={"StructProperty",8},Radius={"FloatProperty",32},
        HalfHeight={"FloatProperty",36},ObjectTypes={"ArrayProperty",40},ComponentClassFilter={"ClassProperty",56},
        ActorsToIgnore={"ArrayProperty",64},OutComponents={"ArrayProperty",80},ReturnValue={"BoolProperty",96},
    })
    self:_signature("/Script/Pal.PalUtility:GetEngineCollisionChannelByPalTraceType",{
        type={"EnumProperty",0},ReturnValue={"ByteProperty",1},
    })
    self:_signature("/Script/Engine.PrimitiveComponent:GetCollisionEnabled",{ReturnValue={"ByteProperty",0}})
    self:_signature("/Script/Engine.PrimitiveComponent:GetCollisionProfileName",{ReturnValue={"NameProperty",0}})
    self:_signature("/Script/Pal.PalUtility:GetEngineCollisionChannelByPalObjectType",{
        type={"EnumProperty",0},ReturnValue={"ByteProperty",1},
    })
    self:_signature("/Script/Pal.PalUtility:IsWildNPC",{
        Actor={"ObjectProperty",0},ReturnValue={"BoolProperty",8},
    })
    for _,method in ipairs({"GetWalkableFloorAngleByPriority","GetInWaterRate"}) do
        self:_signature("/Script/Pal.PalCharacterMovementComponent:"..method,{ReturnValue={"FloatProperty",0}})
    end
    self:_signature("/Script/Engine.PrimitiveComponent:GetCollisionResponseToChannel",{
        Channel={"ByteProperty",0},ReturnValue={"ByteProperty",1},
    })
    self:_signature("/Script/Pal.PalPhysicsUtility:CapsuleTraceSingleByPalTraceType", {
        WorldContextObject={"ObjectProperty",0},Start={"StructProperty",8},End={"StructProperty",32},
        Radius={"FloatProperty",56},HalfHeight={"FloatProperty",60},PalTraceType={"EnumProperty",64},
        bTraceComplex={"BoolProperty",65},bReturnPhysicalMaterial={"BoolProperty",66},bReturnTraceIndex={"BoolProperty",67},
        HitResult={"StructProperty",72},DrawDebugType={"ByteProperty",304},TraceColor={"StructProperty",308},
        TraceHitColor={"StructProperty",324},DrawTime={"FloatProperty",340},ReturnValue={"BoolProperty",344},
    })
    self:_signature("/Script/Pal.PalPhysicsUtility:LineTraceSingleByPalTraceType", {
        WorldContextObject = { "ObjectProperty", 0 }, Start = { "StructProperty", 8 }, End = { "StructProperty", 32 },
        PalTraceType = { "EnumProperty", 56 }, bTraceComplex = { "BoolProperty", 57 },
        bReturnPhysicalMaterial = { "BoolProperty", 58 }, bReturnTraceIndex = { "BoolProperty", 59 },
        HitResult = { "StructProperty", 64 }, DrawDebugType = { "ByteProperty", 296 },
        TraceColor = { "StructProperty", 300 }, TraceHitColor = { "StructProperty", 316 },
        DrawTime = { "FloatProperty", 332 }, ReturnValue = { "BoolProperty", 336 },
    })
    self.qualified = true
    return true
end

function Native:_class(path)
    local class = self.bridge:_static_find(path)
    if not self.a.valid(class) then
        local load = rawget(_G, "LoadAsset")
        if type(load) ~= "function" then error(SCOPE, 0) end
        local found, loaded
        class, found, loaded = load(path)
        if found ~= true or loaded ~= true then error(SCOPE, 0) end
    end
    if not self.a.valid(class) or class:IsClass() ~= true
        or class:GetFName():ToString():lower() ~= path:match("%.([^%.]+)$"):lower() then error(SCOPE, 0) end
    return class
end

function Native:qualify_simulation_observation()
    for _,path in ipairs({
        "/Script/Pal.PalCharacter:GetActiveActorFlag",
        "/Script/Engine.Actor:GetActorEnableCollision",
        "/Script/Engine.Actor:IsActorTickEnabled",
        "/Script/Engine.ActorComponent:IsActive",
        "/Script/Engine.ActorComponent:IsComponentTickEnabled",
        "/Script/Engine.PrimitiveComponent:GetGenerateOverlapEvents",
    }) do self:_signature(path,{ReturnValue={"BoolProperty",0}}) end
    for _,path in ipairs({
        "/Script/Engine.Actor:GetActorTickInterval",
        "/Script/Engine.ActorComponent:GetComponentTickInterval",
        "/Script/Engine.MovementComponent:GetGravityZ",
    }) do self:_signature(path,{ReturnValue={"FloatProperty",0}}) end
    for _,method in ipairs({"GetCollisionEnabled","GetCollisionObjectType"}) do
        self:_signature("/Script/Engine.PrimitiveComponent:"..method,{ReturnValue={"ByteProperty",0}})
    end
    for _,method in ipairs({"GetLastUpdateLocation","GetLastUpdateVelocity"}) do
        self:_signature("/Script/Engine.CharacterMovementComponent:"..method,{ReturnValue={"StructProperty",0}})
    end
    self:_signature("/Script/Engine.Actor:GetAllChildActors",{
        ChildActors={"ArrayProperty",0},bIncludeDescendants={"BoolProperty",16},
    })
    self:_signature("/Script/Engine.Actor:GetParentActor",{ReturnValue={"ObjectProperty",0}})
    self:_signature("/Script/Engine.Actor:GetComponentsByInterface",{
        Interface={"ClassProperty",0},ReturnValue={"ArrayProperty",8},
    })
    self:_signature("/Script/Engine.PrimitiveComponent:GetCollisionResponseToChannel",{
        Channel={"ByteProperty",0},ReturnValue={"ByteProperty",1},
    })
    self.simulationObservationQualified=true
end

function Native:actor_world(actor,strict)
    local function valid(object)
        if object==nil then return false end
        if strict then return Cadence.valid_checked(object) end
        return self.a.valid(object)
    end
    if not valid(actor) then return nil end
    local fn=self.bridge:_static_find("/Script/Engine.Actor:GetLevel")
    local level=invoke_function(self,"custom-actor-level",fn,actor)
    if not strict then level=self.a.unwrap(level) end
    if not valid(level) or not level:IsA("/Script/Engine.Level") then return nil end
    local world=level.OwningWorld
    if not strict then world=self.a.unwrap(world) end
    if not valid(world) or not world:IsA("/Script/Engine.World") then return nil,level end
    return world,level
end

function Native:prepare(world)
    if not self.a.valid(world) then error(SCOPE, 0) end
    self:qualify()
    self.world, self.utility = world, self.bridge:_utility()
    self.npcManager = self:_call("npc-manager", self.utility, "GetNPCManager", world)
    self.characterManager = self:_call("character-manager", self.utility, "GetCharacterManager", world)
    if not self.a.valid(self.npcManager) or not self.a.valid(self.characterManager)
        or not self.a.same(self:_call("npc-manager-world", self.npcManager, "GetWorld"), world)
        or not self.a.same(self:_call("character-manager-world", self.characterManager, "GetWorld"), world) then
        error(SCOPE, 0)
    end
    self.controllerClass = self.npcManager.NPCAIControllerBaseClass
    if not self.a.valid(self.controllerClass) or self.controllerClass:type() ~= "UClass" then error(SCOPE, 0) end
    local class, generic = self.controllerClass, false
    for _ = 1, 8 do
        if not self.a.valid(class) then break end
        if class:GetFName():ToString():lower() == "bp_npcaicontroller_c" then generic = true; break end
        class = class:GetSuperStruct()
    end
    if not generic then error(SCOPE, 0) end
    for _, key in ipairs(util.sorted_keys(CLASSES)) do
        local loaded, class = self.bridge:_native_step("custom-class-" .. key, function() return self:_class(CLASSES[key]) end)
        if not loaded then error(class, 0) end
        self.classes[key] = class
    end
    self.classes.invoker = self:_class("/Script/Pal.PalNavigationInvokerComponent")
    self.navigationLibrary = self.bridge:_static_find("/Script/NavigationSystem.Default__NavigationSystemV1")
    self.physicsLibrary = self.bridge:_static_find("/Script/Pal.Default__PalPhysicsUtility")
    if not self.a.valid(self.navigationLibrary) or not self.a.valid(self.physicsLibrary) then error(SCOPE, 0) end
    return true
end

function Native.startup_base_ids(ids,count,ordinal)
    if ordinal==nil then return ids end
    if not util.is_integer(ordinal) or ordinal<1 or ordinal>64 or not util.is_integer(count) or count<1 then error(SCOPE,0) end
    if ordinal+count-1>#ids then return nil end
    local selected={}
    for index=ordinal,ordinal+count-1 do selected[#selected+1]=ids[index] end
    return selected
end

function Native:startup_prepare(count,ordinal)
    return self.bridge:_native_step("startup-world-and-bases", function()
        local find = rawget(_G, "FindAllOf")
        if type(find) ~= "function" then error(SCOPE, 0) end
        local instances = find("PalGameInstance") or {}
        if #instances > 8 then error(SCOPE, 0) end
        local world
        for _, instance in ipairs(instances) do
            if self.a.valid(instance) and not instance:GetFName():ToString():match("^Default__") then
                local candidate = self:_call("headless-world", instance, "GetWorld")
                if self.a.valid(candidate) then
                    if not candidate:IsA("/Script/Engine.World") or (world and not self.a.same(world, candidate)) then error(SCOPE, 0) end
                    world = candidate
                end
            end
        end
        if not world then return nil end
        local utility = self.bridge:_utility()
        if not self.a.valid(utility) then return nil end
        local manager = self:_call("headless-base-registry", utility, "GetInvaderManager", world)
        if not self.a.valid(manager) then return nil end
        if not self.a.same(self:_call("headless-registry-world", manager, "GetWorld"), world) then error(SCOPE, 0) end
        local observers = self.a.unwrap(manager.Observers)
        if observers == nil then return nil end
        local ids = {}
        observers:ForEach(function(key)
            local id = self.a.guid(key)
            if id then ids[#ids + 1] = id end
            if #ids > self.bridge.config.limits.maxBases then return true end
            return nil
        end)
        if #ids < count then return nil end
        if #ids > self.bridge.config.limits.maxBases then error(SCOPE, 0) end
        table.sort(ids)
        local selected=Native.startup_base_ids(ids,count,ordinal)
        if not selected then return {blockedCode="selected-base-unavailable",availableBases=#ids,candidates={}} end
        self:prepare(world)
        self.startupPawnClass = self:_class(STARTUP_PAWN)
        if not self.a.valid(self:_call("startup-pawn-cdo", self.startupPawnClass, "GetCDO")) then error(SCOPE, 0) end
        local scopes, candidates = {}, {}
        local physical = { sampled = 0, floor = 0, centerFloor = 0, centerTrace = 0, spawnNav = 0, goalNav = 0 }
        for _, id in ipairs(selected) do
            local target, reason = self.bridge:_resolve_dispatch_target(manager, id)
            if not target then error(reason, 0) end
            local scope = self:prepare_base(id, target, world, {})
            if not scope.unavailable then
                if #candidates < count then candidates[#candidates + 1] = scope end
                physical.sampled = physical.sampled + 1
                if self:startup_floor(world, scope.origin) then physical.centerFloor = physical.centerFloor + 1 end
                if self:startup_trace(world, scope.origin) then physical.centerTrace = physical.centerTrace + 1 end
                local floor = scope.positions[1] and self:startup_floor(world, scope.positions[1]) or nil
                if floor then
                    physical.floor = physical.floor + 1
                    local spawn_nav = self:startup_nav(world, floor)
                    local goal_nav = self:startup_nav(world, scope.origin)
                    if spawn_nav then physical.spawnNav = physical.spawnNav + 1 end
                    if goal_nav then physical.goalNav = physical.goalNav + 1 end
                    local corrected = spawn_nav and self:startup_floor(world, spawn_nav) or nil
                    if corrected and goal_nav and distance_squared(corrected, scope.origin) <= scope.leashRadius ^ 2
                        and math.abs(corrected.Z - scope.origin.Z) <= 3000 then
                        scope.positions[1] = corrected
                        scopes[#scopes + 1] = scope
                    end
                end
            end
            if #scopes == count then break end
        end
        if #scopes ~= count then
            return { blockedCode = "floor-or-navigation-unavailable", physical = physical, availableBases = #ids, candidates = candidates }
        end
        return { scopes = scopes, physical = physical, availableBases = #ids }
    end)
end

function Native:startup_support(scopes)
    return require("ped.startup_support").new(self, scopes)
end

function Native:qualify_player_presence()
    self:_signature("/Script/Pal.PalPlayerController:GetPlayerUId",{ReturnValue={"StructProperty",0}})
    self:_signature("/Script/Pal.PalPlayerController:GetDefaultPlayerCharacter",{ReturnValue={"ObjectProperty",0}})
    self:_signature("/Script/Pal.PalCharacter:IsInitialized",{ReturnValue={"BoolProperty",0}})
    self:_signature("/Script/Engine.Actor:K2_GetActorLocation",{ReturnValue={"StructProperty",0}})
    self.playerPresenceQualified=true
end

function Native:startup_player_presence(scope)
    return self.bridge:_native_step("startup-player-presence",function()
        if not self.playerPresenceQualified or not scope or not Cadence.valid_checked(scope.base)
            or not Cadence.same_checked(scope.world,self.world) or not finite(scope.range) or scope.range<=0
            or self.a.guid(guid(self:_call("player-presence-base",scope.base,"GetId"),false))~=scope.baseId then error(SCOPE,0) end
        local find=rawget(_G,"FindAllOf")
        if type(find)~="function" then error(SCOPE,0) end
        local controllers=find("PalPlayerController") or {}
        if #controllers>self.bridge.config.limits.maxPlayers then error(SCOPE,0) end
        local result={ready=false,matchingPlayers=0}
        for _,controller in ipairs(controllers) do
            if Cadence.valid_checked(controller) and controller:IsA("/Script/Pal.PalPlayerController") then
                local controller_world=self:actor_world(controller,true)
                if controller_world and Cadence.same_checked(controller_world,scope.world) then
                    local uid=guid(self:_call("player-presence-id",controller,"GetPlayerUId"),true)
                    if not is_zero(uid) then
                        local pawn=self:_call("player-presence-character",controller,"GetDefaultPlayerCharacter")
                        if pawn~=nil and Cadence.valid_checked(pawn) and pawn:IsA("/Script/Pal.PalCharacter") then
                            local pawn_world=self:actor_world(pawn,true)
                            if pawn_world and Cadence.same_checked(pawn_world,scope.world) then
                                local initialized=self:_call("player-presence-initialized",pawn,"IsInitialized")
                                if type(initialized)~="boolean" then error(SCOPE,0) end
                                if initialized then
                                    local location=vector(self:_call("player-presence-location",pawn,"K2_GetActorLocation"))
                                    local distance=math.sqrt(distance_squared(location,scope.origin))
                                    result.nearestDistanceCm=math.min(result.nearestDistanceCm or distance,distance)
                                    if distance<=scope.range then result.matchingPlayers=result.matchingPlayers+1 end
                                end
                            end
                        end
                    end
                end
            end
        end
        result.ready=result.matchingPlayers>0
        return result
    end)
end

function Native:startup_catalog_entry(character_id)
    return self.bridge:_native_step("startup-catalog-class", function()
        if not self.qualified then self:qualify() end
        local class_path = bounties.pawn_class(character_id)
        if not class_path then error(SCOPE, 0) end
        local class = self:_class(class_path)
        local cdo = self:_call("startup-catalog-cdo", class, "GetCDO")
        if not self.a.valid(cdo) or not cdo:IsA("/Script/Pal.PalCharacter") then error(SCOPE, 0) end
        local shape, reason = self:_placement_shape(character_id)
        return { characterId = character_id, classPath = class_path, cdoAvailable = true,
            shapeQualified=shape~=nil,shapeReason=reason,capsuleRadius=shape and shape.radius,
            capsuleHalfHeight=shape and shape.halfHeight,walkableZ=shape and shape.walkableZ,
            navAgentQualified=shape~=nil and shape.navContext~=nil,
            bodyProxy=shape and shape.bodyProxy,bodyProxyReason=shape and shape.bodyProxyReason }
    end)
end

function Native:startup_trace(world, location)
    local start_point, end_point = vector(location), vector(location)
    start_point.Z, end_point.Z = start_point.Z + 500, end_point.Z - 500
    local hit, color = {}, { R=0, G=0, B=0, A=0 }
    local found = self:_call("startup-ground-trace", self.physicsLibrary, "LineTraceSingleByPalTraceType",
        world, start_point, end_point, 3, false, false, false, hit, 0, color, color, 0)
    if type(found) ~= "boolean" then error(SCOPE, 0) end
    return found
end

function Native:startup_floor(world, location, character_id)
    -- Lua references do not keep Blueprint classes/CDOs alive across streaming and GC.
    local class_path = STARTUP_PAWN
    if character_id ~= nil then
        class_path = bounties.pawn_class(character_id)
        if not class_path then error(SCOPE, 0) end
    end
    local pawn_class = self:_class(class_path)
    local cdo = self:_call("startup-floor-cdo", pawn_class, "GetCDO")
    if not self.a.valid(cdo) then error(SCOPE, 0) end
    local output = {}
    local ok = self:_call("startup-floor", self.utility, "CanAdjustLocationToFloorFromCDO",
        world, pawn_class, vector(location), 100, output, true)
    if type(ok) ~= "boolean" then error(SCOPE, 0) end
    if not ok then return nil end
    local point = vector(output)
    if distance_squared(point, location) > 500 ^ 2 then return nil end
    return point
end

function Native:startup_nav(world, location)
    local output = {}
    local ok = self:_call("startup-nav", self.navigationLibrary, "K2_ProjectPointToNavigation",
        world, vector(location), output, nil, nil, { X = 300, Y = 300, Z = 300 })
    if type(ok) ~= "boolean" then error(SCOPE, 0) end
    if not ok then return nil end
    local point = vector(output)
    if distance_squared(point, location) > 600 ^ 2 then return nil end
    return point
end

function Native:startup_identity(member)
    local record = self.records[member_key(member)]
    if not record then error(IDENTITY, 0) end
    if not record.id then return { handleAddress = self.a.address and self.a.address(record.handle) or nil } end
    return { instanceGuid = guid(record.id.InstanceId, false), playerGuid = guid(record.id.PlayerUId, true),
        actorAddress=record.actor and self.a.address and self.a.address(record.actor) or nil }
end

function Native:startup_behavior(member)
    local record = self.records[member_key(member)]
    if not record then error(IDENTITY, 0) end
    return record.mode
end

function Native:startup_damage_target(scope, actor)
    return self.bridge:_native_step("startup-damage-target", function()
        return self:_character_scope(actor, scope) == true
    end)
end

function Native:_weapon_readiness(controller)
    local weapon = self.a.unwrap(controller.WeaponHandle)
    if not self.a.valid(weapon) then return nil end
    local ready = self:_call("weapon-ready", weapon, "IsEndInitialize")
    if type(ready) ~= "boolean" then error(SCOPE, 0) end
    return weapon, ready
end

function Native:_shot_radius(weapon)
    local radius = self:_call("shot-radius", weapon, "GetSphereCastRadius")
    if not finite(radius) or radius < 0 or radius > 1000 then error(SCOPE, 0) end
    return radius
end

function Native:_line_of_sight(actor, target, radius)
    local visible = self:_call("shot-line-of-sight", self.utility, "LineTraceToTarget_ForAIAttack", actor, target, radius)
    if type(visible) ~= "boolean" then error(SCOPE, 0) end
    return visible
end

function Native:_movement_observation(state,simulation)
    if simulation and not self.simulationObservationQualified then error(SCOPE,0) end
    local movement = self.a.unwrap(state.actor.CharacterMovement)
    local result = { available = self.a.valid(movement) }
    if not result.available then return result end
    if not movement:IsA("/Script/Pal.PalCharacterMovementComponent")
        or not self.a.same(self:_call("movement-owner", movement, "GetOwner"), state.actor) then error(SCOPE, 0) end
    local root = self.a.unwrap(state.actor.RootComponent)
    result.updatedRoot = self.a.valid(root) and self.a.same(self.a.unwrap(movement.UpdatedComponent), root)
    result.mode, result.customMode = movement.MovementMode, movement.CustomMovementMode
    for _, key in ipairs({"mode","customMode"}) do
        if not util.is_integer(result[key]) or result[key] < 0 or result[key] > 255 then error(SCOPE, 0) end
    end
    for _, pair in ipairs({{"grounded","IsMovingOnGround"},{"falling","IsFalling"},{"flying","IsFlying"}}) do
        local value = self:_call("movement-" .. pair[1], movement, pair[2])
        if type(value) ~= "boolean" then error(SCOPE, 0) end
        result[pair[1]] = value
    end
    result.velocityZ = vector(self.a.unwrap(movement.Velocity)).Z
    result.accelerationZ = vector(self:_call("movement-acceleration", movement, "GetCurrentAcceleration")).Z
    result.pendingInputZ = vector(self:_call("movement-pending-input", state.actor, "GetPendingMovementInputVector")).Z
    result.lastInputZ = vector(self:_call("movement-last-input", state.actor, "GetLastMovementInputVector")).Z
    local rotation = self:_call("movement-rotation", state.actor, "K2_GetActorRotation")
    if not finite(rotation.Pitch) or not finite(rotation.Roll) then error(SCOPE, 0) end
    result.pitch, result.roll = rotation.Pitch, rotation.Roll
    result.heightFromBase = state.heightFromBase
    if simulation then
        result.active=self:_call("movement-active",movement,"IsActive")
        result.tickEnabled=self:_call("movement-tick-enabled",movement,"IsComponentTickEnabled")
        result.primaryInterval=self:_call("movement-primary-interval",movement,"GetComponentTickInterval")
        result.cacheInterval,result.reserveInterval=movement.CacheTickInterval,movement.ReserveTickInterval
        result.gravityZ=self:_call("movement-gravity",movement,"GetGravityZ")
        local location=vector(self:_call("movement-last-update-location",movement,"GetLastUpdateLocation"))
        local velocity=vector(self:_call("movement-last-update-velocity",movement,"GetLastUpdateVelocity"))
        result.lastUpdateDistanceFromActor=math.sqrt(distance_squared(location,state.location))
        result.lastUpdateHeightFromActor=location.Z-state.location.Z
        result.lastUpdateVelocityZ=velocity.Z
        if type(result.active)~="boolean" or type(result.tickEnabled)~="boolean"
            or not finite(result.primaryInterval) or result.primaryInterval<0
            or not finite(result.cacheInterval) or not finite(result.reserveInterval) or not finite(result.gravityZ) then
            error(SCOPE,0)
        end
    end
    return result
end

function Native:_simulation_component(component,actor,world,source)
    if component==nil or not Cadence.valid_checked(component) then return {available=false} end
    if not component:IsA("/Script/Engine.PrimitiveComponent")
        or not Cadence.same_checked(self:_call("simulation-component-owner",component,"GetOwner"),actor)
        or not Cadence.same_checked(self:_call("simulation-component-world",component,"GetWorld"),world) then error(SCOPE,0) end
    local result={available=true,class=self:_class_name(component),
        overlapEvents=self:_call("simulation-overlap-events",component,"GetGenerateOverlapEvents"),
        collisionEnabled=self:_call("simulation-collision-enabled",component,"GetCollisionEnabled"),
        objectType=self:_call("simulation-object-type",component,"GetCollisionObjectType")}
    if type(result.overlapEvents)~="boolean" or not util.is_integer(result.collisionEnabled)
        or result.collisionEnabled<0 or result.collisionEnabled>5
        or not util.is_integer(result.objectType) or result.objectType<0 or result.objectType>31 then error(SCOPE,0) end
    if source then
        local channel=self:_call("simulation-source-type",source,"GetCollisionObjectType")
        if not util.is_integer(channel) or channel<0 or channel>31 then error(SCOPE,0) end
        result.responseToSource=self:_call("simulation-response-to-source",component,"GetCollisionResponseToChannel",channel)
        result.sourceResponse=self:_call("simulation-source-response",source,"GetCollisionResponseToChannel",result.objectType)
        for _,key in ipairs({"responseToSource","sourceResponse"}) do
            if not util.is_integer(result[key]) or result[key]<0 or result[key]>2 then error(SCOPE,0) end
        end
        result.pairResponse=math.min(result.responseToSource,result.sourceResponse)
    end
    return result
end

function Native:_simulation_object_array(values,label)
    local ok,objects=self.bridge:_native_step(label,function()
        local result={}
        -- Function arrays contain borrowed RemoteUnrealParam slots, not direct UObject values.
        for index,slot in ipairs(values) do result[index]=slot:get() end
        return result
    end)
    if not ok then error(objects,0) end
    return objects
end

function Native:_simulation_body_parts(actor,world)
    local child_slots={}
    local children_fn=self.bridge:_static_find("/Script/Engine.Actor:GetAllChildActors")
    invoke_function(self,"simulation-child-actors",children_fn,actor,child_slots,true)
    if #child_slots>16 then return nil,"child-actor-limit" end
    local children=self:_simulation_object_array(child_slots,"simulation-child-objects")
    local actors={actor}
    local function contains(list,value)
        for _,entry in ipairs(list) do if Cadence.same_checked(entry,value) then return true end end
        return false
    end
    local parent_fn=self.bridge:_static_find("/Script/Engine.Actor:GetParentActor")
    for _,child in ipairs(children) do
        if not Cadence.valid_checked(child) or contains(actors,child) then return nil,"invalid-child-actor" end
        local current,visited,rooted=child,{},false
        for _=1,16 do
            if not Cadence.valid_checked(current) or not current:IsA("/Script/Engine.Actor")
                or not Cadence.same_checked(self:actor_world(current),world) or contains(visited,current) then
                return nil,"child-actor-scope"
            end
            visited[#visited+1]=current
            local parent=invoke_function(self,"simulation-parent-actor",parent_fn,current)
            if parent==nil or not Cadence.valid_checked(parent) then return nil,"child-actor-parent" end
            if Cadence.same_checked(parent,actor) then rooted=true; break end
            current=parent
        end
        if not rooted then return nil,"child-actor-depth" end
        actors[#actors+1]=child
    end
    local interface=self.bridge:_static_find("/Script/Pal.PalBodyPartsInterface")
    if not Cadence.valid_checked(interface) or interface:IsClass()~=true
        or interface:GetFullName()~="Class /Script/Pal.PalBodyPartsInterface" then error(SCOPE,0) end
    local fn=self.bridge:_static_find("/Script/Engine.Actor:GetComponentsByInterface")
    local parts,seen={},{}
    for _,owner in ipairs(actors) do
        local slots=invoke_function(self,"simulation-body-parts",fn,owner,interface)
        if type(slots)~="table" then error(SCOPE,0) end
        if #slots>64-#parts then return nil,"body-part-limit" end
        local values=self:_simulation_object_array(slots,"simulation-body-objects")
        for _,part in ipairs(values) do
            if not Cadence.valid_checked(part) or not part:IsA("/Script/Engine.PrimitiveComponent") then
                return nil,"invalid-body-part"
            end
            local family=false
            for _,shape in ipairs({"Sphere","Capsule","Box"}) do
                if part:IsA("/Script/Pal.PalBodyParts"..shape.."Component") then family=true; break end
            end
            if not family then return nil,"unsupported-body-family" end
            if not Cadence.same_checked(self:_call("simulation-body-owner",part,"GetOwner"),owner)
                or not Cadence.same_checked(self:_call("simulation-body-world",part,"GetWorld"),world) then error(SCOPE,0) end
            if contains(seen,part) then return nil,"duplicate-body-part" end
            seen[#seen+1]=part
            parts[#parts+1]={component=part,owner=owner}
        end
    end
    if #parts==0 then return nil,"no-qualified-body-parts" end
    return parts,nil,#children
end

function Native:_character_simulation(actor,world,source)
    if not self.simulationObservationQualified or not self.a.valid(actor)
        or not actor:IsA("/Script/Pal.PalCharacter") or not self.a.same(self:actor_world(actor),world) then error(SCOPE,0) end
    local result={available=true,bodyPartsSampled=false,
        active=self:_call("simulation-character-active",actor,"GetActiveActorFlag"),
        collisionEnabled=self:_call("simulation-actor-collision",actor,"GetActorEnableCollision"),
        tickEnabled=self:_call("simulation-actor-tick-enabled",actor,"IsActorTickEnabled"),
        tickInterval=self:_call("simulation-actor-tick-interval",actor,"GetActorTickInterval"),
        importance=actor.ImportanceType}
    for _,key in ipairs({"active","collisionEnabled","tickEnabled"}) do
        if type(result[key])~="boolean" then error(SCOPE,0) end
    end
    if not finite(result.tickInterval) or result.tickInterval<0
        or not util.is_integer(result.importance) or result.importance<0 or result.importance>255 then error(SCOPE,0) end
    local root,mesh=self.a.unwrap(actor.RootComponent),self.a.unwrap(actor.Mesh)
    result.root=self:_simulation_component(root,actor,world,source)
    result.mesh=self:_simulation_component(mesh,actor,world,source)
    if source then
        result.bodyPartsSampled=true
        local parts,reason,children=self:_simulation_body_parts(actor,world)
        result.bodyPartsComplete=parts~=nil
        result.bodyPartsReason,result.childActors=reason,children
        result.bodyParts={}
        for _,part in ipairs(parts or {}) do
            if (root==nil or not Cadence.valid_checked(root) or not Cadence.same_checked(part.component,root))
                and (mesh==nil or not Cadence.valid_checked(mesh) or not Cadence.same_checked(part.component,mesh)) then
                result.bodyParts[#result.bodyParts+1]=self:_simulation_component(part.component,part.owner,world,source)
            end
        end
    end
    return result
end

function Native:_simulation_target(scope,controller)
    local actions=self:_call("simulation-current-ai",controller,"GetAIActionComponent")
    if actions==nil or not Cadence.valid_checked(actions) then return nil,"ai-unavailable" end
    local action=self:_call("simulation-current-action",actions,"GetCurrentAction_BP")
    if action==nil or not Cadence.valid_checked(action) or not action:IsA(CLASSES.combat) then return nil,"no-combat-target" end
    local target=self.a.unwrap(action.TargetActor)
    if target==nil or not Cadence.valid_checked(target) then return nil,"target-unavailable" end
    local scoped,parameter=self:_character_scope(target,scope)
    if scoped~=true or self.a.guid(self:_call("simulation-current-target-base",parameter,"GetBaseCampId"))~=scope.baseId then
        return nil,"target-not-exact-base"
    end
    return target
end

function Native:_simulation_receiver(actor,world,scope)
    local visited={}
    local parent_fn=self.bridge:_static_find("/Script/Engine.Actor:GetParentActor")
    for _=1,16 do
        if actor==nil or not Cadence.valid_checked(actor) then return nil,"receiver-unavailable" end
        if not actor:IsA("/Script/Engine.Actor") or not Cadence.same_checked(self:actor_world(actor),world) then
            return nil,"receiver-world"
        end
        for _,previous in ipairs(visited) do
            if Cadence.same_checked(actor,previous) then return nil,"receiver-cycle" end
        end
        visited[#visited+1]=actor
        if actor:IsA("/Script/Pal.PalCharacter") then
            local scoped,parameter=self:_character_scope(actor,scope)
            if scoped~=true or self.a.guid(self:_call("simulation-receiver-base",parameter,"GetBaseCampId"))~=scope.baseId then
                return nil,"receiver-not-exact-base"
            end
            return actor
        end
        actor=invoke_function(self,"simulation-receiver-parent",parent_fn,actor)
    end
    return nil,"receiver-depth"
end

function Native:_simulation_weapon(actor,world,shooter)
    if not self.simulationObservationQualified or not Cadence.valid_checked(actor)
        or not actor:IsA("/Script/Pal.PalCharacter") or not Cadence.same_checked(self:actor_world(actor),world) then error(SCOPE,0) end
    if not shooter then
        local class=self:_class("/Script/Pal.PalShooterComponent")
        shooter=self:_call("simulation-shooter",actor,"GetComponentByClass",class)
    end
    if shooter==nil or not Cadence.valid_checked(shooter) then return nil,"shooter-unavailable" end
    if not shooter:IsA("/Script/Pal.PalShooterComponent")
        or not Cadence.same_checked(self:_call("simulation-shooter-owner",shooter,"GetOwner"),actor)
        or not Cadence.same_checked(self:_call("simulation-shooter-world",shooter,"GetWorld"),world) then error(SCOPE,0) end
    local held=self:_call("simulation-held-weapon",shooter,"GetHasWeapon")
    local npc=self.a.unwrap(shooter.NPCWeapon)
    if held==nil or npc==nil or not Cadence.valid_checked(held) or not Cadence.valid_checked(npc) then
        return nil,"held-weapon-unavailable"
    end
    if not Cadence.same_checked(held,npc) then return nil,"weapon-reference-mismatch" end
    if not npc:IsA("/Script/Pal.PalWeaponBase") or not Cadence.same_checked(self:actor_world(npc),world) then error(SCOPE,0) end
    return npc
end

function Native:_class_name(object)
    local class = object:GetClass()
    if not self.a.valid(class) then error(SCOPE,0) end
    local name = class:GetFName():ToString()
    if #name>96 or not name:match("^[A-Za-z][A-Za-z0-9_]+$") then error(SCOPE,0) end
    return name
end

function Native:_tick_observation(state, actions, action)
    local owner = self:_call("tick-owner",actions,"GetOwner")
    if not self.a.same(owner,state.controller) then error(SCOPE,0) end
    local result = {
        intervalSeconds=self:_call("tick-interval",actions,"GetComponentTickInterval"),
        enabled=self:_call("tick-enabled",actions,"IsComponentTickEnabled"),
        ownerTimeDilation=owner.CustomTimeDilation,
        minIntervalSeconds=state.controller.MinAIActionComponentTickInterval,
        importance=state.actor.ImportanceType,
        controllerActive=self:_call("tick-ai-active",state.controller,"IsActiveAI"),
    }
    for _,key in ipairs({"intervalSeconds","ownerTimeDilation","minIntervalSeconds"}) do
        if not finite(result[key]) or result[key]<0 then error(SCOPE,0) end
    end
    if type(result.enabled)~="boolean" or type(result.controllerActive)~="boolean"
        or not util.is_integer(result.importance) or result.importance<0 or result.importance>255 then error(SCOPE,0) end
    if self.a.valid(action) and action:IsA("/Script/AIModule.PawnAction") then
        local child = self.a.unwrap(action.ChildAction)
        result.childAction = self.a.valid(child)
        if result.childAction then result.childActionClass=self:_class_name(child) end
        if action:IsA("/Script/Pal.PalAIActionBase") then
            result.actionActive = self:_call("tick-action-active",action,"IsActive")
            result.actionPaused = self:_call("tick-action-paused",action,"IsPaused")
            if type(result.actionActive)~="boolean" or type(result.actionPaused)~="boolean" then error(SCOPE,0) end
        end
    end
    return result
end

function Native:startup_combat_observation(scope, member, movement_only)
    return self.bridge:_native_step("startup-combat-observation", function()
        local state = self:_owned_state(member.handle, member)
        local lease=self.cadenceLease
        local cadenced=lease and lease.record==self.records[member_key(member)]
        if cadenced and (lease.retired or not lease:check()) then
            return {phase="cadence-ended",cadence=util.deep_copy(lease.runner.state.cadence)}
        end
        if state.phase ~= "alive" and state.phase ~= "escaped" then return { phase = state.phase } end
        local result = { phase = state.phase, movement = self:_movement_observation(state,cadenced) }
        if lease then result.cadence=util.deep_copy(lease.runner.state.cadence) end
        if cadenced then
            result.simulation={actor=self:_character_simulation(state.actor,scope.world),
                target={available=false,reason="no-scoped-target"},handle={available=false},weapon={available=false}}
        end
        if movement_only or state.phase ~= "alive" then return result end
        local actions = self:_call("startup-current-ai", state.controller, "GetAIActionComponent")
        local action = self:_call("startup-current-action", actions, "GetCurrentAction_BP")
        result.tick = self:_tick_observation(state,actions,action)
        result.currentAction = "none"
        if self.a.valid(action) then
            result.currentAction = self:_class_name(action)
        end
        if result.currentAction == "BP_AIAction_NPC_Combat_Gun_C" then
            result.outerTimer, result.outerDeltaTime = action.Timer, action.tempDeltaTime
            if not finite(result.outerTimer) or not finite(result.outerDeltaTime) then error(SCOPE, 0) end
        end
        result.healthRatio = self:_call("startup-health-ratio", state.component, "GetHPRate")
        if not finite(result.healthRatio) then error(SCOPE, 0) end
        local record = self.records[member_key(member)]
        result.defenderSelection = record.defenderSelection and util.shallow_copy(record.defenderSelection) or nil
        result.encounterRequests = record.encounterRequests or 0
        if self.a.valid(record.target) then
            local target_location = vector(self:_call("startup-target-distance", record.target, "K2_GetActorLocation"))
            result.targetDistanceCm = math.sqrt(distance_squared(state.location, target_location))
        end
        local weapon, ready = self:_weapon_readiness(state.controller)
        result.weaponHandle = self.a.valid(weapon)
        result.weaponReady = ready
        if cadenced and result.weaponHandle and ready then
            result.simulation.handle={available=true,class=self:_class_name(weapon)}
        end
        if self.a.valid(action) and action:IsA(CLASSES.combat) then
            result.stopTick = action.IsStopTick
            local machine = self.a.unwrap(action.StateMachine)
            result.stateMachine = self.a.valid(machine)
            if result.stateMachine then
                local current = self:_call("startup-gun-state", machine, "GetCurrentState")
                if self.a.valid(current) then
                    local name = self:_class_name(current)
                    result.gunState = name
                    local library = self.bridge:_static_find("/Script/Engine.Default__KismetSystemLibrary")
                    if not self.a.valid(library) then error(SCOPE,0) end
                    local outer = self:_call("startup-state-outer",library,"GetOuterObject",current)
                    result.tick.stateOuterMatches = self.a.same(outer,action)
                    if name == "BP_AINPC_CombatGunState_FireMove_C" then
                        result.fireState = {}
                        for _, key in ipairs({"Timer","Interval","ShootCount","ShootAbleTimer","temp_DeltaTime"}) do
                            local value = current[key]
                            if not finite(value) then error(SCOPE, 0) end
                            result.fireState[key] = value
                        end
                    end
                end
            end
            local target = self.a.unwrap(action.TargetActor)
            result.actualTarget = self.a.valid(target)
            result.requestedTargetMatches = result.actualTarget and self.a.same(target,record.target)
            result.actionSelfMatches = self.a.same(self.a.unwrap(action.SelfActor), state.actor)
            if result.weaponReady then
                result.remainingBullets = self:_call("startup-ammo", weapon, "GetRemainingBullet")
                result.magazineEmpty = self:_call("startup-magazine-empty", weapon, "IsMagazineEmpty")
                if not util.is_integer(result.remainingBullets) or result.remainingBullets < 0
                    or type(result.magazineEmpty) ~= "boolean" then error(SCOPE, 0) end
                local scoped,target_parameter
                if result.actualTarget then scoped,target_parameter=self:_character_scope(target,scope) end
                if scoped == true then
                    if cadenced then
                        if self.a.guid(self:_call("simulation-target-base",target_parameter,"GetBaseCampId"))==scope.baseId then
                            result.simulation.target=self:_character_simulation(target,scope.world)
                        else
                            result.simulation.target={available=false,reason="target-not-exact-base"}
                        end
                    end
                    result.lineOfSight = self:_line_of_sight(state.actor, target, self:_shot_radius(weapon))
                    local location = vector(self:_call("startup-actual-target-location", target, "K2_GetActorLocation"))
                    result.actualTargetHeightDelta = location.Z - state.location.Z
                    result.actualTargetDistanceCm = math.sqrt(distance_squared(location, state.location))
                    if result.actionSelfMatches then
                        for _, pair in ipairs({{"rootFacing","InFanShap"},{"aimFacing","InFanShapAimTarget"}}) do
                            local value = self:_call("startup-" .. pair[1]:lower(), self.utility, pair[2], state.actor, target, 5)
                            if type(value) ~= "boolean" then error(SCOPE, 0) end
                            result[pair[1]] = value
                        end
                        result.cameraAttackAllowed = self:_call("startup-camera-attack", self.utility,
                            "IsAIAttackAbleByPlayerCamera", state.actor, target)
                        if type(result.cameraAttackAllowed) ~= "boolean" then error(SCOPE, 0) end
                    end
                end
            end
        end
        local shooterClass = self:_class("/Script/Pal.PalShooterComponent")
        local shooter = self:_call("startup-shooter",state.actor,"GetComponentByClass",shooterClass)
        result.shooter = self.a.valid(shooter)
        if result.weaponHandle then
            local stored = self.a.unwrap(weapon.ShooterHuman)
            result.storedShooterValid = self.a.valid(stored)
            result.storedShooterMatches = result.storedShooterValid and self.a.same(stored, state.actor)
        end
        if result.shooter then
            if cadenced then
                local equipped,reason=self:_simulation_weapon(state.actor,scope.world,shooter)
                if equipped then
                    local class=equipped:GetClass()
                    if not Cadence.valid_checked(class) then error(SCOPE,0) end
                    result.simulation.weapon={available=true,class=self:_class_name(equipped),
                        exactRifleFamily=class:GetFullName()=="BlueprintGeneratedClass /Game/Pal/Blueprint/Weapon/NPCWeapon/BP_AssaultRifle_NPC.BP_AssaultRifle_NPC_C"}
                else
                    result.simulation.weapon={available=false,reason=reason}
                end
            end
            result.equippedWeapon = self.a.valid(self:_call("startup-equipped-weapon",shooter,"GetHasWeapon"))
            result.npcWeapon = self.a.valid(self.a.unwrap(shooter.NPCWeapon))
            if result.weaponReady and result.equippedWeapon and result.npcWeapon then
                for _, pair in ipairs({{"canShoot","CanShoot"},{"canAim","CanAim"},{"shooting","IsShooting"},{"reloading","IsReloading"},
                    {"aiming","IsAiming"},{"requestAiming","IsRequestAiming"},{"shootAnimation","IsPlayShootingAnimation"}}) do
                    local value = self:_call("startup-shooter-" .. pair[1]:lower(),shooter,pair[2])
                    if type(value) ~= "boolean" then error(SCOPE,0) end
                    result[pair[1]]=value
                end
                for _, pair in ipairs({{"layerZeroAiming","IsAiming_Layered"},{"layerZeroRequest","IsRequestAiming_Layered"}}) do
                    local value = self:_call("startup-" .. pair[1]:lower(), shooter, pair[2], 0)
                    if type(value) ~= "boolean" then error(SCOPE, 0) end
                    result[pair[1]] = value
                end
            end
        end
        return result
    end)
end

function Native:prepare_base(base_id, target, world, players)
    if not self.a.valid(target.base) or not self.a.same(world, self.world) then error(SCOPE, 0) end
    local origin = vector(self.a.unwrap(target.base.Transform).Translation)
    local range = self:_call("base-range", target.base, "GetRange")
    if not finite(range) or range < 500 or range > 100000 then error(SCOPE, 0) end
    local group = self.a.guid(self:_call("base-guild", target.base, "GetGroupIdBelongTo"))
    if not group then error(SCOPE, 0) end
    local scope = { baseId = base_id, base = target.base, world = world, origin = origin,
        range = range, guildId = group, positions = {}, players = players,
        leashRadius = math.min(20000, math.max(range + 3000, self.bridge.config.customAssault.spawnRadiusCm + 2000)) }
    local count = self.bridge.config.customAssault.membersPerBase
    local radius = math.min(self.bridge.config.customAssault.spawnRadiusCm, range * 0.85)
    local rotation = tonumber(util.hash32(base_id), 16) % 360
    for slot = 1, count do
        local found
        for attempt = 1, 8 do
            local angle = math.rad(rotation + (slot - 1) * 360 / count + (attempt - 1) * 45)
            local candidate = { X = origin.X + math.cos(angle) * radius, Y = origin.Y + math.sin(angle) * radius, Z = origin.Z }
            local projected = {}
            local result = self:_call("base-placement", target.base, "TryGetRandomPositionInside", candidate, 500, projected)
            if type(result) ~= "boolean" then error(SCOPE, 0) end
            if result then
                local position = vector(projected)
                local separate = true
                for _, previous in pairs(scope.positions) do
                    if distance_squared(previous, position) < 250 * 250 then separate = false end
                end
                if separate and distance_squared(position, origin) <= (range + 500) ^ 2 and math.abs(position.Z - origin.Z) <= 3000 then
                    found = position
                    break
                end
            end
        end
        if not found and not self.bridge.config.customAssault.allowInBaseFallback then
            scope.unavailable = "No bounded base-local spawn position was available."
            return scope
        end
        scope.positions[slot] = found
    end
    return scope
end

function Native:_validate_spawn_scope(scope, member)
    if not self.a.valid(scope.base) or not self.a.same(scope.world, self.world)
        or self.a.guid(self:_call("spawn-base-id", scope.base, "GetId")) ~= member.baseId then error(SCOPE, 0) end
    if self.a.guid(self:_call("spawn-base-guild", scope.base, "GetGroupIdBelongTo")) ~= scope.guildId then error(SCOPE, 0) end
    if not util.is_integer(member.slot) or member.slot < 1 or member.slot > self.bridge.config.customAssault.membersPerBase
        or scope.unavailable then error(SCOPE, 0) end
end

function Native:_spawn_position(scope, member)
    self:_validate_spawn_scope(scope, member)
    local position = scope.positions[member.slot]
    if not position or scope.unavailable then error("Custom assault placement is unavailable", 0) end
    return vector(position)
end

function Native:_new_placement_search(scope, member)
    return PlacementSearch.new({origin=scope.origin,range=scope.range,slot=member.slot,
        rotation=tonumber(util.hash32(scope.baseId),16)%360,preferred=scope.positions[member.slot],
        allowFallback=self.bridge.config.customAssault.allowInBaseFallback})
end

function Native:_placement_shape(character_id)
    local class_path = bounties.pawn_class(character_id)
    if not class_path then error(SCOPE,0) end
    local class = self:_class(class_path)
    local cdo = self:_call("placement-cdo",class,"GetCDO")
    if not self.a.valid(cdo) or not cdo:IsA("/Script/Pal.PalCharacter") then error(SCOPE,0) end
    local capsule, movement = self.a.unwrap(cdo.CapsuleComponent), self.a.unwrap(cdo.CharacterMovement)
    if not self.a.valid(capsule) or not self.a.valid(movement)
        or not capsule:IsA("/Script/Engine.CapsuleComponent")
        or not movement:IsA("/Script/Engine.CharacterMovementComponent") then return nil,"pawn-shape-unavailable" end
    if not self.a.same(self:_call("placement-root",cdo,"K2_GetRootComponent"),capsule)
        or not self.a.same(self:_call("placement-capsule-owner",capsule,"GetOwner"),cdo)
        or not self.a.same(self:_call("placement-movement-owner",movement,"GetOwner"),cdo) then
        return nil,"pawn-shape-ownership"
    end
    local scale, offset = vector(self.a.unwrap(capsule.RelativeScale3D)), vector(self.a.unwrap(capsule.RelativeLocation))
    local rotation = self.a.unwrap(capsule.RelativeRotation)
    if not rotation or not finite(rotation.Pitch) or not finite(rotation.Roll) then error(SCOPE,0) end
    if math.abs(rotation.Pitch)>0.001 or math.abs(rotation.Roll)>0.001 then return nil,"pawn-shape-transform" end
    for _,key in ipairs({"X","Y","Z"}) do
        if math.abs(scale[key]-1)>0.001 or math.abs(offset[key])>0.001 then return nil,"pawn-shape-transform" end
    end
    local radius = self:_call("placement-capsule-radius",capsule,"GetScaledCapsuleRadius")
    local half_height = self:_call("placement-capsule-height",capsule,"GetScaledCapsuleHalfHeight")
    local walkable = movement.WalkableFloorZ
    if not finite(radius) or not finite(half_height) or not finite(walkable) then error(SCOPE,0) end
    if radius<=0 or radius>500 or half_height<radius or half_height>1000 or walkable<=0 or walkable>1 then
        return nil,"pawn-shape-dimensions"
    end
    local agent = self.a.unwrap(movement.NavAgentProps)
    local nav_context
    if agent and finite(agent.AgentRadius) and finite(agent.AgentHeight)
        and agent.AgentRadius>=radius and agent.AgentHeight>=2*half_height
        and agent.AgentRadius<=1000 and agent.AgentHeight<=4000
        and self.a.same(self:_call("placement-agent-movement",cdo,"GetMovementComponent"),movement) then
        nav_context = cdo
    end
    local shape = {cdo=cdo,capsule=capsule,radius=radius,halfHeight=half_height,walkableZ=walkable,navContext=nav_context}
    local static = self.a.unwrap(cdo.StaticCharacterParameterComponent)
    local mesh = self.a.unwrap(cdo.Mesh)
    if not self.a.valid(static) or not self.a.valid(mesh)
        or not static:IsA("/Script/Pal.PalStaticCharacterParameterComponent")
        or not mesh:IsA("/Script/Engine.SkeletalMeshComponent") then
        shape.bodyProxyReason="body-template-unavailable"
        return shape
    end
    if not self.a.same(self:_call("placement-static-owner",static,"GetOwner"),cdo)
        or not self.a.same(self:_call("placement-mesh-owner",mesh,"GetOwner"),cdo) then
        shape.bodyProxyReason="body-template-ownership"
        return shape
    end
    local body_radius,body_half = static.MeshCapsuleRadius,static.MeshCapsuleHalfHeight
    local mesh_offset,mesh_scale = vector(self.a.unwrap(mesh.RelativeLocation)),vector(self.a.unwrap(mesh.RelativeScale3D))
    local authored_offset = vector(self.a.unwrap(static.MeshRelativeLocation))
    if not finite(body_radius) or not finite(body_half) then error(SCOPE,0) end
    if body_radius<=0 or body_radius>500 or body_half<body_radius or body_half>1000 then
        shape.bodyProxyReason="body-template-dimensions"
        return shape
    end
    if math.abs(mesh_offset.X)>0.001 or math.abs(mesh_offset.Y)>0.001 or math.abs(mesh_offset.Z)>2000 then
        shape.bodyProxyReason="body-template-offset"
        return shape
    end
    for _,key in ipairs({"X","Y","Z"}) do
        if math.abs(mesh_scale[key]-1)>0.001 then shape.bodyProxyReason="body-template-scale"; return shape end
    end
    local center = mesh_offset.Z+body_half
    local low = math.min(-half_height+radius,center-body_half+body_radius)
    local high = math.max(half_height-radius,center+body_half-body_radius)
    local proxy_radius = math.max(radius,body_radius)
    shape.bodyProxy = {templateOnly=true,bodyRadius=body_radius,bodyHalfHeight=body_half,meshOffsetZ=mesh_offset.Z,
        authoredOffsetZ=authored_offset.Z,radius=proxy_radius,halfHeight=(high-low)/2+proxy_radius,
        centerOffsetZ=(low+high)/2,lowerFootOffsetZ=math.min(-half_height,mesh_offset.Z)}
    return shape
end

function Native:startup_surface_survey(scope)
    return self.bridge:_native_step("startup-surface-survey",function()
        return require("ped.surface_survey").new(self,scope):run()
    end)
end

function Native:_placement_path(scope, member, position, goal)
    local shape, reason = self:_placement_shape(member.characterId)
    if not shape then return {ready=false,reason=reason} end
    local function invoke(method, owner, receiver, ...)
        local fn = self.bridge:_static_find("/Script/NavigationSystem."..owner..":"..method)
        return invoke_function(self,"custom-placement-"..method:lower(),fn,receiver,...)
    end
    local path = invoke("FindPathToLocationSynchronously","NavigationSystemV1",self.navigationLibrary,
        scope.world,vector(position),vector(goal),shape.navContext,nil)
    if not self.a.valid(path) then return {ready=false,reason="path-unavailable"} end
    if not path:IsA("/Script/NavigationSystem.NavigationPath") then error(SCOPE,0) end
    local valid = invoke("IsValid","NavigationPath",path)
    if type(valid)~="boolean" then error(SCOPE,0) end
    if not valid then return {ready=false,reason="path-unreachable"} end
    local partial = invoke("IsPartial","NavigationPath",path)
    if type(partial)~="boolean" then error(SCOPE,0) end
    if partial then return {ready=false,reason="path-partial"} end
    local length = invoke("GetPathLength","NavigationPath",path)
    if not finite(length) then error(SCOPE,0) end
    if length<0 or length>math.min(40000,scope.leashRadius*4) then return {ready=false,reason="path-length-limit"} end
    local points = self.a.unwrap(path.PathPoints)
    if points==nil then error(SCOPE,0) end
    local count = points:GetArrayNum()
    if not util.is_integer(count) or count<2 or count>64 then return {ready=false,reason="path-point-limit"} end
    local first,last
    local extent = scope.leashRadius-shape.halfHeight
    if extent<=0 then return {ready=false,reason="path-outside-envelope"} end
    for index=1,count do
        local location = vector(self.a.unwrap(points[index]))
        if distance_squared(location,scope.origin)>extent^2 then return {ready=false,reason="path-outside-envelope"} end
        first,last = first or location,location
    end
    local tolerance = math.max(250,shape.halfHeight+100)
    if distance_squared(first,position)>tolerance^2 or distance_squared(last,goal)>tolerance^2 then
        return {ready=false,reason="path-endpoint-mismatch"}
    end
    return {ready=true,pathPoints=count,pathLength=length,defaultNavDataUsed=shape.navContext==nil}
end

function Native:collision_profile(component)
    local name=self.a.text(self:_call("collision-profile",component,"GetCollisionProfileName"))
    if type(name)~="string" or #name>96 or not name:match("^[A-Za-z][A-Za-z0-9_]*$") then error(SCOPE,0) end
    return name:lower()
end

function Native.mesh_collision_disabled(collision)
    if not collision or collision.enabled~=0 or collision.objectType~=0 or collision.profileName~="nocollision"
        or type(collision.responses)~="table" or #collision.responses~=32 then return false end
    for index=1,32 do if collision.responses[index]~=0 then return false end end
    return true
end

function Native.disabled_mesh_snapshot(mesh)
    local collision=mesh and mesh.collision
    if not Native.mesh_collision_disabled(collision) then return nil end
    local location,scale,rotation=mesh.relativeLocation,mesh.relativeScale,mesh.relativeRotation
    if not location or not scale or not rotation then return nil end
    for _,axis in ipairs({"X","Y","Z"}) do
        if not finite(location[axis]) or not finite(scale[axis]) or math.abs(scale[axis]-1)>0.001 then return nil end
    end
    if math.abs(location.X)>0.001 or math.abs(location.Y)>0.001 or math.abs(location.Z)>2000
        or not finite(rotation.Pitch) or not finite(rotation.Yaw) or not finite(rotation.Roll)
        or math.abs(rotation.Pitch)>0.001 or math.abs(rotation.Roll)>0.001 then return nil end
    return {policy="owned-main-mesh-no-collision",classPath="/Script/Engine.SkeletalMeshComponent",
        collision=util.deep_copy(collision),relativeLocation=vector(location),relativeScale=vector(scale),
        relativeRotation={Pitch=rotation.Pitch,Yaw=rotation.Yaw,Roll=rotation.Roll}}
end

function Native:placement_mesh_policy(shape)
    local actor,root=shape.cdo,shape.capsule
    if not self.a.valid(actor) or not actor:IsA("/Script/Pal.PalCharacter") or not self.a.valid(root)
        or not root:IsA("/Script/Engine.CapsuleComponent") then return nil,"mesh-policy-scope" end
    local mesh=self.a.unwrap(actor.Mesh)
    if not self.a.valid(mesh) or not mesh:IsA("/Script/Engine.SkeletalMeshComponent")
        or not self.a.same(self:_call("mesh-policy-owner",mesh,"GetOwner"),actor)
        or not self.a.same(self:_call("mesh-policy-root-owner",root,"GetOwner"),actor)
        or not self.a.same(self:_call("mesh-policy-root",actor,"K2_GetRootComponent"),root)
        or not self.a.same(self.a.unwrap(mesh.AttachParent),root) then return nil,"mesh-policy-ownership" end
    local root_scale,root_location=self.a.unwrap(root.RelativeScale3D),self.a.unwrap(root.RelativeLocation)
    local root_rotation=self.a.unwrap(root.RelativeRotation)
    if not root_scale or not root_location or not root_rotation
        or not finite(root_rotation.Pitch) or not finite(root_rotation.Roll)
        or math.abs(root_rotation.Pitch)>0.001 or math.abs(root_rotation.Roll)>0.001 then return nil,"root-policy-transform" end
    for _,axis in ipairs({"X","Y","Z"}) do
        if not finite(root_scale[axis]) or not finite(root_location[axis])
            or math.abs(root_scale[axis]-1)>0.001 or math.abs(root_location[axis])>0.001 then return nil,"root-policy-transform" end
    end
    local collision={enabled=self:_call("mesh-policy-enabled",mesh,"GetCollisionEnabled"),
        objectType=self:_call("mesh-policy-type",mesh,"GetCollisionObjectType"),profileName=self:collision_profile(mesh),responses={}}
    for channel=0,31 do
        collision.responses[channel+1]=self:_call("mesh-policy-response",mesh,"GetCollisionResponseToChannel",channel)
    end
    local policy=Native.disabled_mesh_snapshot({collision=collision,
        relativeLocation=self.a.unwrap(mesh.RelativeLocation),relativeScale=self.a.unwrap(mesh.RelativeScale3D),
        relativeRotation=self.a.unwrap(mesh.RelativeRotation)})
    if not policy then return nil,"mesh-collision-policy-unqualified" end
    return policy
end

function Native.player_pawn_collision_model(template,player_pawn)
    if not util.is_integer(player_pawn) or player_pawn<0 or player_pawn>31
        or type(template)~="table" or type(template.responses)~="table" or #template.responses~=32 then error(SCOPE,0) end
    for index=1,32 do
        local response=template.responses[index]
        if not util.is_integer(response) or response<0 or response>2 then error(SCOPE,0) end
    end
    local model=util.deep_copy(template)
    if model.responses[player_pawn+1]~=2 then model.profileName="custom" end
    model.responses[player_pawn+1]=2
    return model
end

function Native:placement_collision_model(template)
    local player_pawn=self:_call("player-pawn-channel",self.utility,"GetEngineCollisionChannelByPalObjectType",2)
    local model=Native.player_pawn_collision_model(template,player_pawn)
    return model,{policy="conservative-player-pawn-block",palObjectSelector=2,playerPawnChannel=player_pawn,
        templateResponse=template.responses[player_pawn+1],expectedResponse=2,modelOnly=true}
end

function Native:_placement_start_overlap(scope,shape,start)
    if not self.a.valid(scope.world) or not scope.world:IsA("/Script/Engine.World")
        or not self.a.same(scope.world,self.world) then error(SCOPE,0) end
    local kismet=self.bridge:_static_find("/Script/Engine.Default__KismetSystemLibrary")
    if not self.a.valid(kismet) then error(SCOPE,0) end
    local ground=self:_call("placement-ground-channel",self.utility,"GetEngineCollisionChannelByPalTraceType",3)
    if not util.is_integer(ground) or ground<0 or ground>31 then error(SCOPE,0) end
    local types,components={},{}
    for index=0,31 do types[index+1]=index end
    local before=os.clock()
    local found=self:_call("placement-start-overlap",kismet,"CapsuleOverlapComponents",
        scope.world,vector(start),shape.radius,shape.halfHeight,types,nil,{},components)
    local elapsed=os.clock()-before
    if type(found)~="boolean" or not finite(elapsed) or elapsed<0
        or getmetatable(components)~=nil then error(SCOPE,0) end
    local total,count=#components,0
    local result={ready=false,classification="UNSUPPORTED",components=total,blockers=0,unqualifiedBodies=0,
        groundChannel=ground,clockSeconds=elapsed}
    if total>128 then result.reason="support-start-overlap-over-cap"; return result end
    for key in pairs(components) do
        if not util.is_integer(key) or key<1 or key>total then error(SCOPE,0) end
        count=count+1
    end
    if count~=total or found~=(total>0) then error(SCOPE,0) end
    if elapsed>0.25 then result.reason="support-start-overlap-slow"; return result end
    for index=1,total do
        local component=self.a.unwrap(components[index])
        if not self.a.valid(component) or not component:IsA("/Script/Engine.PrimitiveComponent") then error(SCOPE,0) end
        local owner=self:_call("placement-start-owner",component,"GetOwner")
        if not self.a.valid(owner) or not owner:IsA("/Script/Engine.Actor")
            or not self.a.same(self:_call("placement-start-world",component,"GetWorld"),scope.world)
            or not self.a.same(self:actor_world(owner),scope.world) then error(SCOPE,0) end
        local enabled=self:_call("placement-start-enabled",component,"GetCollisionEnabled")
        local single_body=not component:IsA("/Script/Engine.InstancedStaticMeshComponent")
            and not component:IsA("/Script/Engine.SkinnedMeshComponent")
            and (component:IsA("/Script/Engine.ShapeComponent") or component:IsA("/Script/Engine.StaticMeshComponent"))
        if (enabled~=1 and enabled~=3) or not single_body then
            result.unqualifiedBodies=result.unqualifiedBodies+1
        else
            local response=self:_call("placement-start-response",component,"GetCollisionResponseToChannel",ground)
            if not util.is_integer(response) or response<0 or response>2 then
                result.unqualifiedBodies=result.unqualifiedBodies+1
            elseif response==2 then
                result.blockers=result.blockers+1
            end
        end
    end
    if result.unqualifiedBodies>0 then result.reason="support-start-overlap-unqualified"
    elseif result.blockers>0 then result.classification,result.reason="BLOCKED","support-penetrating"
    else result.classification,result.ready="CLEAR",true end
    return result
end

function Native.support_contact_metrics(start,finish,proposed,hit)
    local result={diagnosticOnly=true,contactExceptionEnabled=false}
    local function readable(value)
        return value and finite(value.X) and finite(value.Y) and finite(value.Z)
    end
    local function same(left,right)
        return readable(left) and readable(right) and left.X==right.X and left.Y==right.Y and left.Z==right.Z
    end
    local length=math.sqrt((finish.X-start.X)^2+(finish.Y-start.Y)^2+(finish.Z-start.Z)^2)
    if not finite(length) or length<=0 or length>20 then return result end
    result.traceLengthCm=length
    if finite(hit.Time) and hit.Time>=0 and hit.Time<=1 then result.time=hit.Time end
    if finite(hit.Distance) and hit.Distance>=0 and hit.Distance<=length+0.0001 then result.distanceCm=hit.Distance end
    result.positiveTimeDistance=result.time~=nil and result.time>0 and result.distanceCm~=nil and result.distanceCm>0
    result.traceEchoAvailable=readable(hit.TraceStart)==true and readable(hit.TraceEnd)==true
    result.traceEchoAgreement=same(hit.TraceStart,start)==true and same(hit.TraceEnd,finish)==true
    local location=hit.Location
    if readable(location) then
        local signed=proposed.Z-location.Z
        if finite(signed) and math.abs(signed)<=100 then result.signedProposedMinusHitZ=signed end
        result.sameXY=location.X==proposed.X and location.Y==proposed.Y
        result.atOrBeforeReportedTOI=result.sameXY and location.Z<=proposed.Z and proposed.Z<=start.Z
        if result.time~=nil then
            local error_squared=0
            for _,axis in ipairs({"X","Y","Z"}) do
                error_squared=error_squared+(location[axis]-(start[axis]+result.time*(finish[axis]-start[axis])))^2
            end
            local error_cm=math.sqrt(error_squared)
            if finite(error_cm) and error_cm<=100 then result.reconstructionErrorCm=error_cm end
        end
    end
    if result.time~=nil and result.distanceCm~=nil then
        result.distanceTimeErrorCm=math.abs(result.distanceCm-result.time*length)
    end
    result.reconstructionAgreement=result.reconstructionErrorCm~=nil and result.reconstructionErrorCm<=0.000001
    result.distanceTimeAgreement=result.distanceTimeErrorCm~=nil and result.distanceTimeErrorCm<=0.0001
    return result
end

function Native:_support_witness(scope,shape,point,component,observation)
    local witness={native=self,scope=scope,world=scope.world,component=component,capsule=shape.capsule,cdo=shape.cdo,
        radius=shape.radius,halfHeight=shape.halfHeight,walkableZ=shape.walkableZ,point=vector(point),traceType=3,traceComplex=false,
        groundChannel=observation.startOverlap.groundChannel,createdAt=self.bridge.clock(),
        metrics=util.deep_copy(observation.contact),startClear=observation.startOverlap.ready==true,
        upwardClear=observation.clearanceBlocked==false,qualified=false}
    if self.a.valid(shape.capsule) then
        local scale=self.a.unwrap(shape.capsule.RelativeScale3D)
        if scale and finite(scale.X) and finite(scale.Y) and finite(scale.Z) then witness.rootScale=vector(scale) end
        local rotation=self.a.unwrap(shape.capsule.RelativeRotation)
        if rotation and finite(rotation.Pitch) and finite(rotation.Yaw) and finite(rotation.Roll) then
            witness.rootRotation={Pitch=rotation.Pitch,Yaw=rotation.Yaw,Roll=rotation.Roll}
        end
    end
    local owner=self:_call("support-witness-owner",component,"GetOwner")
    if not self.a.valid(owner) or not owner:IsA("/Script/Engine.Actor") then return witness end
    witness.owner=owner
    if not self.a.same(self:_call("support-witness-world",component,"GetWorld"),scope.world)
        or not self.a.same(self:actor_world(owner),scope.world) then return witness end
    local enabled=self:_call("support-witness-enabled",component,"GetCollisionEnabled")
    local response=self:_call("support-witness-ground",component,"GetCollisionResponseToChannel",witness.groundChannel)
    witness.enabled,witness.groundResponse=enabled,response
    witness.qualified=(enabled==1 or enabled==3) and response==2 and finite(witness.createdAt)
    return witness
end

function Native:_placement_support(scope, member, position)
    local shape, reason = self:_placement_shape(member.characterId)
    if not shape then return {ready=false,reason=reason} end
    if scope.leashRadius<=shape.halfHeight
        or distance_squared(position,scope.origin)>(scope.leashRadius-shape.halfHeight)^2 then
        return {ready=false,reason="capsule-outside-envelope"}
    end
    local start, finish, hit = vector(position),vector(position),{}
    local color = {R=0,G=0,B=0,A=0}
    start.Z,finish.Z=start.Z+5,finish.Z-5
    local observation={radius=shape.radius,halfHeight=shape.halfHeight,startOffsetZ=5}
    local function outcome(ready,why) return {ready=ready,reason=why,support=observation} end
    observation.startOverlap=self:_placement_start_overlap(scope,shape,start)
    if not observation.startOverlap.ready then return outcome(false,observation.startOverlap.reason) end
    local found = self:_call("placement-support",self.physicsLibrary,"CapsuleTraceSingleByPalTraceType",
        scope.world,start,finish,shape.radius,shape.halfHeight,3,false,false,false,hit,0,color,color,0)
    if type(found)~="boolean" then error(SCOPE,0) end
    observation.found=found
    if not found then return outcome(false,"no-solid-support") end
    observation.contact=Native.support_contact_metrics(start,finish,position,hit)
    -- UE4SS 3.0.1's copied struct bools read the shared byte, not each FBoolProperty mask.
    observation.copiedHitFlags={trust="UNTRUSTED"}
    if type(hit.bBlockingHit)=="boolean" then observation.copiedHitFlags.blockingHit=hit.bBlockingHit end
    if type(hit.bStartPenetrating)=="boolean" then observation.copiedHitFlags.startPenetrating=hit.bStartPenetrating end
    local impact,contact=self.a.unwrap(hit.ImpactNormal),self.a.unwrap(hit.Location)
    if impact and finite(impact.X) and finite(impact.Y) and finite(impact.Z)
        and math.abs(impact.X)<=1 and math.abs(impact.Y)<=1 and math.abs(impact.Z)<=1 then
        observation.impactNormal=vector(impact)
    end
    -- Failed hits can contain an unset world location; only retain plausible short-sweep deltas.
    if contact and finite(contact.X) and finite(contact.Y) and finite(contact.Z) then
        local delta={X=contact.X-position.X,Y=contact.Y-position.Y,Z=contact.Z-position.Z}
        if math.abs(delta.X)<=100 and math.abs(delta.Y)<=100 and math.abs(delta.Z)<=100
            and delta.X^2+delta.Y^2+delta.Z^2<=100^2 then observation.contactDelta=delta end
    end
    local normal,location = vector(self.a.unwrap(hit.ImpactNormal)),vector(self.a.unwrap(hit.Location))
    if normal.Z<shape.walkableZ then return outcome(false,"support-not-walkable") end
    if math.abs(location.X-position.X)>10 or math.abs(location.Y-position.Y)>10 or math.abs(location.Z-position.Z)>10
        or distance_squared(location,position)>10^2 then return outcome(false,"support-moved") end
    -- The copied weak pointer already exposes Get/get; generic unwrap would resolve it twice.
    local weak = hit.Component
    if weak==nil then return outcome(false,"support-component-unavailable") end
    local resolved,component=self.bridge:_native_step("custom-support-hit-component",function() return weak:Get() end)
    if not resolved then error(component,0) end
    if not self.a.valid(component) or not component:IsA("/Script/Engine.PrimitiveComponent") then
        return outcome(false,"support-component-unavailable")
    end
    local slope = self.a.unwrap(self:_call("placement-slope",component,"GetWalkableSlopeOverride"))
    if not slope or not util.is_integer(slope.WalkableSlopeBehavior) then error(SCOPE,0) end
    if slope.WalkableSlopeBehavior~=0 then return outcome(false,"support-slope-override") end
    start,finish,hit=vector(position),vector(position),{}
    start.Z,finish.Z=start.Z+2,finish.Z+4
    local blocked = self:_call("placement-ground-clearance",self.physicsLibrary,"CapsuleTraceSingleByPalTraceType",
        scope.world,start,finish,shape.radius,shape.halfHeight,3,false,false,false,hit,0,color,color,0)
    if type(blocked)~="boolean" then error(SCOPE,0) end
    observation.clearanceBlocked=blocked
    if blocked then return outcome(false,"capsule-obstructed") end
    -- This second return is process-local evidence only, never part of the public support result.
    return outcome(true),self:_support_witness(scope,shape,position,component,observation)
end

function Native:_placement_surface(scope, member, position)
    local support=self:_placement_support(scope,member,position)
    if not support.ready then return support end
    -- A clear ground-channel sweep alone does not qualify pawn responses or water containment.
    return {ready=false,reason="dry-clearance-unqualified"}
end

function Native:_placement_candidate(scope, member, position, mode)
    local floor = self:startup_floor(scope.world, position, member.characterId)
    if not floor then return { ready = false, reason = "floor-unavailable" } end
    local nav = self:startup_nav(scope.world, floor)
    local goal = self:startup_nav(scope.world, scope.origin)
    if not nav or not goal then return { ready = false, reason = "navigation-unavailable" } end
    local corrected = self:startup_floor(scope.world, nav, member.characterId)
    if not corrected then return { ready = false, reason = "projected-floor-unavailable" } end
    if distance_squared(corrected, scope.origin) > scope.leashRadius ^ 2
        or math.abs(corrected.Z - scope.origin.Z) > (mode == "in-base" and 500 or 3000) then
        return { ready = false, reason = "placement-outside-envelope" }
    end
    if mode == "in-base" and (corrected.X-scope.origin.X)^2+(corrected.Y-scope.origin.Y)^2 > scope.range^2 then
        return { ready = false, reason = "placement-outside-base" }
    end
    for slot, previous in pairs(scope.positions) do
        if slot ~= member.slot and distance_squared(corrected, previous) < 250 ^ 2 then
            return { ready = false, reason = "placement-overlap" }
        end
    end
    local surface = self:_placement_surface(scope, member, corrected)
    if not surface.ready then return surface end
    local route = self:_placement_path(scope, member, corrected, goal)
    if not route.ready then return route end
    return { ready = true, position = vector(corrected), goal = vector(goal),
        pathPoints=route.pathPoints,pathLength=route.pathLength,defaultNavDataUsed=route.defaultNavDataUsed }
end

function Native:probe_placement(scope, character_id, slot)
    local member = {baseId=scope.baseId,characterId=character_id,slot=slot}
    self:_validate_spawn_scope(scope,member)
    scope.placementProbes = scope.placementProbes or {}
    local key = character_id .. ":" .. slot
    local search = scope.placementProbes[key] or self:_new_placement_search(scope,member)
    scope.placementProbes[key] = search
    local result = search:poll(function(position,mode) return self:_placement_candidate(scope,member,position,mode) end,2)
    if not result.pending then scope.placementProbes[key] = nil end
    return result
end

function Native:prepare_spawn(scope, member)
    return self.bridge:_native_step("custom-spawn-placement", function()
        local key = member_key(member)
        self.placements[key] = nil
        if self.records[key] then error(IDENTITY, 0) end
        self:_validate_spawn_scope(scope,member)
        local runner=self.bridge.startup_test
        if self.shapeQualification then self.shapeQualification:_validate(scope,member,true) end
        if runner and Qualification.contract(runner.state.case) then
            if next(self.records) or next(self.placements) or next(self.placementSearches) then
                error(SCOPE,0)
            end
            local experiment=self.shapeQualification or Qualification.new(self,runner,scope,member)
            self.shapeQualification=experiment
            local result=experiment:prepare(scope,member)
            if not result.ready then return result end
            scope.positions[member.slot]=vector(result.position)
            self.placements[key]={scope=scope,characterId=member.characterId,level=member.level,slot=member.slot,
                position=vector(result.position),goal=vector(result.goal),mode="in-base",shapeQualification=experiment}
            return result
        end
        local pending = self.placementSearches[key]
        if pending and (pending.scope ~= scope or pending.characterId ~= member.characterId
            or pending.slot ~= member.slot or pending.level ~= member.level) then error(SCOPE,0) end
        if not pending then
            pending = {scope=scope,characterId=member.characterId,slot=member.slot,level=member.level,
                search=self:_new_placement_search(scope,member)}
            self.placementSearches[key] = pending
        end
        local result = pending.search:poll(function(position,mode) return self:_placement_candidate(scope,member,position,mode) end,2)
        if not result.ready then return result end
        self.placementSearches[key] = nil
        scope.positions[member.slot] = vector(result.position)
        self.placements[key] = { scope = scope, characterId = member.characterId, level = member.level,
            slot = member.slot, position = vector(result.position), goal = vector(result.goal), mode = result.mode }
        return result
    end)
end

function Native:spawn(scope, member)
    return self.bridge:_native_step("custom-spawn", function()
        local key, position = member_key(member), self:_spawn_position(scope, member)
        local placement = self.placements[key]
        if self.records[key] or not placement or placement.scope ~= scope or placement.characterId ~= member.characterId
            or placement.level ~= member.level or placement.slot ~= member.slot
            or distance_squared(placement.position, position) ~= 0 then error(SCOPE, 0) end
        if placement.shapeQualification~=self.shapeQualification
            or (placement.shapeQualification and placement.shapeQualification.native~=self)
            or (self.bridge.startup_test and Qualification.contract(self.bridge.startup_test.state.case)
                and not placement.shapeQualification) then error(SCOPE,0) end
        self.placements[key] = nil
        if placement.shapeQualification then placement.shapeQualification:consume(scope,member,placement) end
        local constructor = self.a.fname()
        if not constructor then error("FName constructor unavailable", 0) end
        local angle = math.deg(math.atan(scope.origin.Y - position.Y, scope.origin.X - position.X))
        local handle = self:_call("spawn-npc", self.npcManager, "SpawnNPCForServer", {
            ControllerClass = self.controllerClass, CharacterID = constructor(member.characterId, 1),
            Level = member.level, Location = vector(position), Yaw = angle,
        }, nil)
        if not self.a.valid(handle) then error(INITIALIZATION, 0) end
        self.records[key] = { world = scope.world, characterId = member.characterId, handle = handle, scope = scope,
            spawnPosition = vector(position), goal = placement.goal and vector(placement.goal) or vector(scope.origin),
            placementMode = placement.mode, shapeQualification=placement.shapeQualification }
        return handle
    end)
end

function Native:startup_shape_observation(scope,member)
    return self.bridge:_native_step("startup-shape-observation",function()
        local record=self.records[member_key(member)]
        if not record or not record.shapeQualification then error(SCOPE,0) end
        record.shapeQualification:validate_observation(scope,member)
        if not self.a.same(member.handle,record.handle) or not record.id
            or not same_id(record.id,{InstanceId=guid(member.instanceGuid,false),PlayerUId=guid(member.playerGuid,true)}) then
            error(IDENTITY,0)
        end
        local state=self:_owned_state(member.handle,member)
        local result=record.shapeQualification:observe(state)
        record.shapeQualification:record_observation(record,state,result)
        return result
    end)
end

function Native:startup_test_stage_changed(runner,stage)
    local lease=self.cadenceLease
    if lease and lease.runner==runner and stage~="engagement" then
        lease:retire(stage)
        if self.shapeQualification then self.shapeQualification:stage_changed(stage) end
        return lease:release(stage)
    end
    if self.shapeQualification and self.shapeQualification.runner==runner then self.shapeQualification:stage_changed(stage) end
    return true
end

function Native:_qualification_identity(record,member)
    if not self.a.same(member.handle,record.handle) or not record.id
        or not same_id(record.id,{InstanceId=guid(member.instanceGuid,false),PlayerUId=guid(member.playerGuid,true)}) then
        record.shapeQualification:revoke_engagement("identity")
        error(IDENTITY,0)
    end
end

function Native:startup_arm_qualified_engagement(scope,member)
    return self.bridge:_native_step("startup-qualified-engagement-arm",function()
        local record=self.records[member_key(member)]
        if not record or not record.shapeQualification then error(SCOPE,0) end
        self:_qualification_identity(record,member)
        local start=record.shapeQualification:begin_engagement(scope,member,record)
        local state=self:_owned_state(member.handle,member)
        local result=record.shapeQualification:finish_engagement(record,state,start)
        if result.armed and record.shapeQualification.case==Cadence.CASE then
            self.cadenceLease=Cadence.new(self,record.shapeQualification,record)
        end
        return result
    end)
end

function Native:_gameplay_state(scope,member)
    local record=self.records[member_key(member)]
    local lease=self.cadenceLease
    if lease and lease.record==record and lease.retired then
        if not lease:_context() then error(SCOPE,0) end
        record.shapeQualification:_validate(scope,member,false)
        self:_qualification_identity(record,member)
        return {phase="cadence-ended"},record
    end
    if lease and lease.record==record and lease.active and record.shapeQualification.engagementPermit
        and self.bridge.clock()>=record.shapeQualification.engagementPermit.expiresAt then
        lease:retire("expired")
        record.shapeQualification:_validate(scope,member,false)
        self:_qualification_identity(record,member)
        lease:release("expired")
        return {phase="expired"},record
    end
    if record and record.shapeQualification then
        if not record.shapeQualification:validate_gameplay(scope,member,record) then
            if lease and lease.record==record then lease:release("expired") end
            return {phase="expired"},record
        end
        self:_qualification_identity(record,member)
    end
    local state=self:_owned_state(member.handle,member)
    if record and record.shapeQualification and state.phase=="alive" then
        if not record.shapeQualification:validate_gameplay(scope,member,record,state) then
            if lease and lease.record==record then lease:release("expired") end
            return {phase="expired"},record
        end
        if record.shapeQualification.case==Cadence.CASE and (not lease or lease.record~=record or not lease:check()) then
            return {phase="cadence-unavailable"},record
        end
    end
    return state,record
end

function Native:startup_qualified_damage_target(scope,member,attacker,defender)
    return self.bridge:_native_step("startup-qualified-damage-target",function()
        local record=self.records[member_key(member)]
        if not record or not record.shapeQualification or not Qualification.is_engagement(record.shapeQualification.case) then error(SCOPE,0) end
        local state=self:_gameplay_state(scope,member)
        if state.phase~="alive" then return {allowed=false,active=false,phase=state.phase} end
        if not self.a.same(attacker,state.actor) then return {allowed=false,active=true} end
        local scoped,parameter=self:_character_scope(defender,scope)
        local allowed=scoped==true and self.a.guid(self:_call("qualified-damage-base",parameter,"GetBaseCampId"))==scope.baseId
        return {allowed=allowed,active=true}
    end)
end

function Native:_cadence_acquisition_state(scope,member)
    local record=self.records[member_key(member)]
    if not record or not record.shapeQualification or record.shapeQualification.case~=Cadence.CASE
        or not self.cadenceLease or self.cadenceLease.record~=record or (record.encounterRequests or 0)~=0 then error(SCOPE,0) end
    if not record.shapeQualification:validate_gameplay(scope,member,record) then return {phase="expired"},record end
    self:_qualification_identity(record,member)
    local state=self:_owned_state(member.handle,member)
    if state.phase=="alive" and not record.shapeQualification:validate_gameplay(scope,member,record,state) then return {phase="expired"},record end
    return state,record
end

function Native:startup_acquire_cadence(scope,member)
    return self.bridge:_native_step("startup-cadence-acquire",function()
        if not self.cadenceLease then error(SCOPE,0) end
        return self.cadenceLease:acquire(scope,member)
    end)
end

function Native:_cadence_owner(lease)
    local a,record=self.a,lease.record
    if not a.valid(lease.actor) or not a.valid(lease.controller) or not a.valid(lease.component)
        or not lease.actor:IsA("/Script/Pal.PalCharacter") or not lease.controller:IsA("/Script/Pal.PalAIController")
        or not a.same(record.actor,lease.actor) or not a.same(record.parameter,lease.parameter)
        or not a.same(record.handle,lease.handle) or not same_id(record.id,lease.id) then return false,"cadence-original-identity" end
    local handle=self:_call("cadence-owned-handle",self.characterManager,"GetIndividualHandle",lease.id)
    if not a.valid(handle) or not a.same(handle,lease.handle)
        or not same_id(full_id(self:_call("cadence-owned-id",handle,"GetIndividualID")),lease.id) then return false,"cadence-handle-identity" end
    local parameter=self:_call("cadence-owned-parameter",handle,"TryGetIndividualParameter")
    local actor=self:_call("cadence-owned-actor",handle,"TryGetIndividualActor")
    if not a.same(parameter,lease.parameter) or not a.same(actor,lease.actor) or self:_captured_owner(parameter)
        or not same_id(full_id(self:_call("cadence-parameter-id",parameter,"GetPalId")),lease.id) then return false,"cadence-ownership-changed" end
    local character=self.a.text(self:_call("cadence-character",parameter,"GetCharacterID"))
    if type(character)~="string" or character:lower()~=record.characterId:lower() then return false,"cadence-character-changed" end
    if not a.same(self:actor_world(actor),lease.world) then return false,"cadence-world" end
    if self:_call("cadence-actor-destroying",actor,"IsActorBeingDestroyed")~=false
        or self:_call("cadence-actor-initialized",actor,"IsInitialized")~=true then return false,"cadence-actor-lifecycle" end
    local component=self:_call("cadence-capture-component",actor,"GetCharacterParameterComponent")
    if not a.valid(component) or self:_call("cadence-capture-state",component,"GetIsCapturedProcessing")~=false then
        return false,"cadence-capture-state"
    end
    local controller=self:_call("cadence-owned-controller",actor,"GetController")
    if not a.same(controller,lease.controller) or not a.same(self:actor_world(controller),lease.world) then return false,"cadence-controller-changed" end
    local actions=self:_call("cadence-owned-actions",controller,"GetAIActionComponent")
    if not a.same(actions,lease.component) or not actions:IsA("/Script/Pal.PalAIActionComponent")
        or not a.same(self:_call("cadence-actions-owner",actions,"GetOwner"),controller)
        or not a.same(self:_call("cadence-actions-world",actions,"GetWorld"),lease.world) then return false,"cadence-component-changed" end
    return true
end

function Native:_captured_owner(parameter)
    local save = self.a.unwrap(parameter.SaveParameter)
    if save == nil or type(save.IsPlayer) ~= "boolean" then error(OWNERSHIP, 0) end
    if save.IsPlayer or not is_zero(guid(save.OwnerPlayerUId, true)) then return true end
    local history = self.a.unwrap(save.OldOwnerPlayerUIds)
    return history ~= nil and #history > 0
end

function Native:_detached_capture(record)
    if not self.a.valid(record.actor) or not record.actor:IsA("/Script/Pal.PalCharacter")
        or not self.a.same(self:actor_world(record.actor), record.world) then return nil end
    local parameter = self:_call("detached-actor-parameter", self.utility, "GetIndividualCharacterParameterByActor", record.actor)
    if not self.a.valid(parameter) then return nil end
    local id = full_id(self:_call("detached-actor-id", parameter, "GetPalId"))
    if not same_guid(id.InstanceId, record.id.InstanceId) then return nil end
    if self:_captured_owner(parameter) then return "captured" end
    local component = self:_call("detached-capture-component", record.actor, "GetCharacterParameterComponent")
    if not self.a.valid(component) then return nil end
    local capturing = self:_call("detached-capture-processing", component, "GetIsCapturedProcessing")
    if type(capturing) ~= "boolean" then error(OWNERSHIP, 0) end
    return capturing and "capturing" or nil
end

function Native:_absent_state(record)
    if not record.initialized then return { phase = "pending" } end
    if not self.a.valid(record.actor) then return { phase = "missing" } end
    local destroying = self:_call("absent-actor-destroying", record.actor, "IsActorBeingDestroyed")
    if destroying == true then return { phase = "missing" } end
    if type(destroying) ~= "boolean" then error(OWNERSHIP, 0) end
    local capture = self:_detached_capture(record)
    if capture then return { phase = capture } end
    error(OWNERSHIP, 0)
end

function Native:_read_owned_state(handle, member)
    local record = self.records[member_key(member)]
    if not record then error(IDENTITY, 0) end
    if record.despawnRequested then return { phase = self:_despawn_status(record) } end
    local current
    if record.id then
        current = self:_call("reacquire-handle", self.characterManager, "GetIndividualHandle", record.id)
    else
        if not self.a.same(handle, record.handle) then error(IDENTITY, 0) end
        current = record.handle
    end
    if not self.a.valid(current) then
        if record.initialized then return self:_absent_state(record) end
        current = handle
    end
    if not self.a.valid(current) then return self:_absent_state(record) end
    local id = full_id(self:_call("member-id", current, "GetIndividualID"), record.id == nil)
    if not record.id then
        if is_zero(id.InstanceId) then return { phase = "pending" } end
        record.id = id
        current = self:_call("reacquire-assigned-handle", self.characterManager, "GetIndividualHandle", id)
        if not self.a.valid(current) then return { phase = "pending" } end
        if not self.a.same(current, record.handle) then error(IDENTITY, 0) end
    end
    local parameter = self:_call("member-parameter", current, "TryGetIndividualParameter")
    local actor = self:_call("member-actor", current, "TryGetIndividualActor")
    if not self.a.valid(parameter) then
        if record.initialized then error(OWNERSHIP, 0) end
        return { phase = "pending" }
    end
    if self:_captured_owner(parameter) then return { phase = "captured" } end
    if not same_id(id, record.id) then error(IDENTITY, 0) end
    local parameter_id = full_id(self:_call("parameter-id", parameter, "GetPalId"))
    if not same_id(parameter_id, record.id) then error(IDENTITY, 0) end
    local character = self.a.text(self:_call("character-id", parameter, "GetCharacterID"))
    if character:lower() ~= member.characterId:lower() then error(IDENTITY, 0) end
    if record.parameter and not self.a.same(record.parameter, parameter) then error(IDENTITY, 0) end
    if self.a.valid(actor) and record.actor and not self.a.same(record.actor, actor) then error(IDENTITY, 0) end
    local dead = self:_call("member-dead", parameter, "IsDead")
    if type(dead) ~= "boolean" then error(OWNERSHIP, 0) end
    if dead and record.initialized then
        return { phase = "dead", targetId = self.a.guid(id.InstanceId), characterId = member.characterId,
            instanceGuid = guid(id.InstanceId, false), playerGuid = guid(id.PlayerUId, true) }
    end
    if not self.a.valid(actor) then return self:_absent_state(record) end
    if not actor:IsA("/Script/Pal.PalCharacter")
        or not self.a.same(self:actor_world(actor), record.world) then error(SCOPE, 0) end
    if record.shapeQualification then record.actor,record.parameter=actor,parameter end
    local component = self:_call("parameter-component", actor, "GetCharacterParameterComponent")
    if not self.a.valid(component) then return { phase = "pending" } end
    local captured = self:_call("capture-processing", component, "GetIsCapturedProcessing")
    if type(captured) ~= "boolean" then error(OWNERSHIP, 0) end
    if captured then return { phase = "capturing" } end
    local initialized = self:_call("actor-initialized", actor, "IsInitialized")
    if type(initialized) ~= "boolean" then error(INITIALIZATION, 0) end
    if not initialized then return { phase = "pending" } end
    local active = actor.bIsPalActiveActor
    if type(dead) ~= "boolean" or type(active) ~= "boolean" then error(OWNERSHIP, 0) end
    if not active and not dead and not record.initialized then return { phase = "pending" } end
    local controller = self:_call("actor-controller", actor, "GetController")
    if active and not dead and not self.a.valid(controller) then return { phase = "pending" } end
    local actions
    if active and not dead then
        actions = self:_call("ready-ai-component", controller, "GetAIActionComponent")
        local blackboard = self:_call("ready-blackboard", controller, "GetMyPalBlackboard")
        if not self.a.valid(actions) or not self.a.valid(blackboard) then return { phase = "pending" } end
    end
    if record.actor and not self.a.same(record.actor, actor) then error(IDENTITY, 0) end
    if record.parameter and not self.a.same(record.parameter, parameter) then error(IDENTITY, 0) end
    local maximum = self:_call("maximum-health", parameter, "GetMaxHP")
    if not util.is_integer(maximum) or maximum <= 0 then error(INITIALIZATION, 0) end
    local target_id = self.a.guid(id.InstanceId)
    if not target_id then error(IDENTITY, 0) end
    local state = { phase = dead and "dead" or active and "alive" or "inactive", actor = actor, controller = controller, parameter = parameter,
        component = component, targetId = target_id, characterId = member.characterId, healthBudget = maximum,
        instanceGuid = guid(id.InstanceId, false), playerGuid = guid(id.PlayerUId, true) }
    record.actor, record.parameter, record.handle, record.initialized = actor, parameter, current, true
    if active and not dead then
        local location = vector(self:_call("actor-location", actor, "K2_GetActorLocation"))
        state.distanceFromBase = math.sqrt(distance_squared(location, record.scope.origin))
        state.heightFromBase = location.Z - record.scope.origin.Z
        if state.distanceFromBase > record.scope.leashRadius then state.phase, state.scopeReason = "escaped", "outside-leash" end
        state.location = location
        -- The experiment never dispatches gameplay, but stock AI must still remain in its base scope.
        if record.shapeQualification and record.shapeQualification.case==Qualification.CASE then
            if self:_combat_targets_scoped(actions,record.scope)==false then
                state.phase,state.scopeReason="escaped","combat-target"
            end
            return state
        end
        local scoped = self:_combat_targets_scoped(actions, record.scope)
        if scoped == false then
            state.phase, state.scopeReason = "escaped", "combat-target"
        elseif scoped == nil then
            local now = self.bridge.clock()
            if not finite(now) then error(SCOPE, 0) end
            if not record.combatPendingAt then
                record.combatPendingAt = now
                self.bridge.logger:info("Custom attacker combat scope is awaiting evidence", { member = member.index })
            end
            if now >= record.combatPendingAt + self.bridge.config.customAssault.initializationSeconds then
                state.phase, state.scopeReason = "escaped", "combat-state-timeout"
            elseif state.phase ~= "escaped" then
                state.phase = "inactive"
            end
        else
            record.combatPendingAt = nil
        end
    elseif not dead then state.location = vector(self:_call("inactive-location", actor, "K2_GetActorLocation")) end
    return state
end

function Native:_owned_state(handle,member)
    local state=self:_read_owned_state(handle,member)
    local record=self.records[member_key(member)]
    if self.cadenceLease and self.cadenceLease.record==record and self.cadenceLease.active and state.phase~="alive" then
        self.cadenceLease:retire("ownership-"..state.phase)
        if not self.cadenceLease:release("ownership-"..state.phase) then
            error(self.bridge.native_fault or "Cadence lease restoration is unresolved",0)
        end
    end
    if record and record.shapeQualification then record.shapeQualification:ownership_observed(state) end
    return state
end

function Native:inspect(handle, member)
    return self.bridge:_native_step("custom-inspect", function()
        local state = self:_owned_state(handle, member)
        local record = self.records[member_key(member)]
        if state.phase == "pending" then state.waitingOn = record and record.id and "actor-readiness" or "individual-id" end
        if record and record.id and state.phase == "pending" then
            state.instanceGuid, state.playerGuid = guid(record.id.InstanceId, false), guid(record.id.PlayerUId, true)
            state.characterId = member.characterId
        end
        if record and record.shapeQualification and state.actor then
            state.actorAddress=self.a.address(state.actor)
            if not state.actorAddress then error(OWNERSHIP,0) end
        end
        return state
    end)
end

function Native:actorKey(actor)
    if not self.a.valid(actor) then return nil end
    local ok, result = self.bridge:_native_call("custom-actor-key", self.utility, "GetIndividualIDByActor", actor)
    if not ok then error(result, 0) end
    return self.a.guid(self.a.unwrap(result).InstanceId)
end

function Native:sameActor(left, right)
    return self.a.same(left, right)
end

local function action_parameter(point, target)
    return {
        GeneralActor1 = target, GeneralVector1 = vector(point), GeneralVector2 = { X = 0, Y = 0, Z = 0 },
        GeneralIndex1 = 0, GeneralBool1 = true, GeneralInteger1 = 0, GeneralInteger2 = 0, SelfDestructWaza = 0,
    }
end

function Native:_character_scope(actor, scope)
    if not self.a.valid(actor) or not actor:IsA("/Script/Pal.PalCharacter")
        or not self.a.same(self:actor_world(actor), scope.world) then return false end
    local parameter = self:_call("defender-parameter", self.utility, "GetIndividualCharacterParameterByActor", actor)
    if not self.a.valid(parameter) then return nil end
    local location = vector(self:_call("defender-location", actor, "K2_GetActorLocation"))
    if distance_squared(location, scope.origin) > (scope.range + 1500) ^ 2 then return false end
    local base = self.a.guid(self:_call("defender-base", parameter, "GetBaseCampId"))
    local group = self.a.guid(self:_call("defender-group", parameter, "GetGroupId"))
    return base == scope.baseId or group == scope.guildId, parameter
end

function Native:_defender(actor, scope)
    local scoped, parameter = self:_character_scope(actor, scope)
    return scoped == true and actor.bIsPalActiveActor == true
        and self:_call("defender-initialized", actor, "IsInitialized") == true
        and self:_call("defender-dead", parameter, "IsDead") == false
end

function Native:_combat_targets_scoped(actions, scope)
    local current = self:_call("current-ai-action", actions, "GetCurrentAction_BP")
    if not self.a.valid(current) then return true end
    if not current:IsA("/Script/AIModule.PawnAction") then return nil end
    local uncertain = false
    local function target_allowed(target)
        if not self.a.valid(target) then return true end
        local scoped = self:_character_scope(target, scope)
        if scoped == nil then uncertain = true end
        return scoped ~= false
    end
    local function walk(action, link)
        local visited = {}
        for _ = 1, 8 do
            if not self.a.valid(action) then return true end
            if not action:IsA("/Script/AIModule.PawnAction") then return nil end
            for _, previous in ipairs(visited) do if self.a.same(previous,action) then return nil end end
            visited[#visited+1] = action
            if action:IsA(CLASSES.combat) then
                if not target_allowed(self.a.unwrap(action.TargetActor)) then return false end
                local module = self.a.unwrap(action.CombatModule)
                if self.a.valid(module) then
                    if not target_allowed(self:_call("combat-module-target",module,"GetTargetActor")) then return false end
                else
                    uncertain = true
                end
            end
            action = self.a.unwrap(action[link])
        end
        return not self.a.valid(action) and true or nil
    end
    local parents = walk(current,"ParentAction")
    if parents==false then return false end
    local children = walk(self.a.unwrap(current.ChildAction),"ChildAction")
    if children==false then return false end
    return parents and children and not uncertain and true or nil
end

function Native:_choose_defender(scope, state, record)
    local weapon, ready = self:_weapon_readiness(state.controller)
    local radius = ready and self:_shot_radius(weapon) or nil
    local observation = { eligible = 0, visibilityChecks = 0 }
    local fallback, current = nil, record.target
    local function consider(actor)
        if not self:_defender(actor, scope) then return nil end
        observation.eligible = observation.eligible + 1
        fallback = fallback or actor
        if radius == nil then return actor end
        observation.visibilityChecks = observation.visibilityChecks + 1
        if self:_line_of_sight(state.actor, actor, radius) then
            observation.visible = true
            return actor
        end
        observation.visible = false
        return nil
    end
    local function select(actor)
        observation.retained = actor ~= nil and self.a.same(actor, current)
        record.defenderSelection = observation
        return actor
    end
    if self.a.valid(current) then
        local chosen = consider(current)
        if chosen then return select(chosen) end
    end
    local workers = self.a.unwrap(scope.base.WorkerDirector)
    if self.a.valid(workers) then
        local slots = {}
        self:_call("worker-slots", workers, "GetCharacterHandleSlots", slots)
        for index = 1, math.min(#slots, 32) do
            if index > #slots then break end
            local slot = self.a.unwrap(slots[index])
            if self.a.valid(slot) then
                local handle = self:_call("worker-handle", slot, "GetHandle")
                if self.a.valid(handle) then
                    local actor = self:_call("worker-actor", handle, "TryGetIndividualActor")
                    if not self.a.same(actor, current) then
                        local chosen = consider(actor)
                        if chosen then return select(chosen) end
                    end
                end
            end
        end
    end
    for index = 1, math.min(#scope.players, self.bridge.config.limits.maxPlayers) do
        local controller = scope.players[index].controller
        if self.a.valid(controller) then
            local actor = self:_call("player-defender", controller, "GetPawn")
            if not self.a.same(actor, current) then
                local chosen = consider(actor)
                if chosen then return select(chosen) end
            end
        end
    end
    return select(fallback)
end

function Native:_action_class(key)
    local class_path = CLASSES[key]
    if not class_path then error(SCOPE, 0) end
    return self:_class(class_path)
end

function Native:_set_action(component, key, point, target)
    local class = self:_action_class(key)
    if not self.a.valid(class) or class:type() ~= "UClass" then error(SCOPE, 0) end
    local action = self:_call("ai-action", component, "SetActionClassParameter", class, action_parameter(point, target))
    if not self.a.valid(action) then error(ACTION, 0) end
end

function Native:_behavior(record, member, mode, target)
    if record.mode ~= mode then
        self.bridge.logger:info("Custom attacker behavior", { member = member.index, mode = mode, character = member.characterId })
    end
    record.target, record.mode = target, mode
end

function Native:_configure_movement(record, state, scope,member)
    if record.shapeQualification then
        if not member then error(SCOPE,0) end
        local observed,owned=self:_gameplay_state(scope,member)
        if owned~=record then error(SCOPE,0) end
        if observed.phase~="alive" then return false end
        if not self.a.same(observed.actor,state.actor) or not self.a.same(observed.controller,state.controller) then error(IDENTITY,0) end
    end
    if record.configured then return true end
    local blackboard = self:_call("ai-blackboard", state.controller, "GetMyPalBlackboard")
    if not self.a.valid(blackboard) then error(INITIALIZATION, 0) end
    blackboard.SpawnerLocation_BB, blackboard.SpawnedPosition_BB = vector(scope.origin), vector(state.location)
    blackboard.ReturnTerritoryRadius_BB, blackboard.Disable_ReturnTerritory_WildPal = scope.leashRadius, false
    local invoker = self:_call("nav-invoker", state.actor, "GetComponentByClass", self.classes.invoker)
    if not self.a.valid(invoker) then error(INITIALIZATION, 0) end
    self:_call("activate-nav", invoker, "ActivateInvoker")
    self:_call("walking-mode", self.utility, "ChangeDefaultLandMovementModeForWalking", state.actor)
    record.configured = true
    return true
end

function Native:startup_travel(scope, member)
    return self.bridge:_native_step("startup-travel", function()
        local state,record=self:_gameplay_state(scope,member)
        if state.phase~="alive" then
            if record and record.shapeQualification then return "unavailable" end
            error(INITIALIZATION,0)
        end
        if not self:_configure_movement(record,state,scope,member) then return "unavailable" end
        local actions = self:_call("startup-ai-component", state.controller, "GetAIActionComponent")
        if not self.a.valid(actions) then error(INITIALIZATION, 0) end
        self:_set_action(actions, "travel", self.records[member_key(member)].goal, nil)
        return true
    end)
end

function Native:startup_arrival(scope, member)
    return self.bridge:_native_step("startup-arrival",function()
        local state = self:_owned_state(member.handle,member)
        if state.phase~="alive" then return {arrived=false,phase=state.phase} end
        local record = self.records[member_key(member)]
        if record.scope~=scope then error(SCOPE,0) end
        local movement = self:_movement_observation(state)
        if not movement.available then return {arrived=false,movementAvailable=false} end
        local capsule = self.a.unwrap(state.actor.CapsuleComponent)
        if not self.a.valid(capsule) or not capsule:IsA("/Script/Engine.CapsuleComponent")
            or not self.a.same(capsule,self.a.unwrap(state.actor.RootComponent)) then
            return {arrived=false,movementAvailable=true,capsuleAvailable=false}
        end
        local half_height = self:_call("arrival-capsule-height",capsule,"GetScaledCapsuleHalfHeight")
        if not finite(half_height) or half_height<=0 or half_height>1000 then error(SCOPE,0) end
        local goal = record.goal
        local feet_delta = state.location.Z-half_height-goal.Z
        local distance = math.sqrt(distance_squared(state.location,goal))
        return {arrived=movement.updatedRoot and movement.grounded and not movement.falling and not movement.flying
            and distance<=1100 and math.abs(feet_delta)<=150,
            grounded=movement.grounded,falling=movement.falling,flying=movement.flying,
            feetHeightDelta=feet_delta,distanceToGoal=distance,capsuleHalfHeight=half_height}
    end)
end

function Native:engage(scope, member)
    return self.bridge:_native_step("custom-engage", function()
        local state,owned=self:_gameplay_state(scope,member)
        if state.phase~="alive" then
            if owned and owned.shapeQualification then return "unavailable" end
            error(OWNERSHIP,0)
        end
        local record, actor, controller = self.records[member_key(member)], state.actor, state.controller
        local actions = self:_call("ai-component", controller, "GetAIActionComponent")
        local blackboard = self:_call("ai-blackboard", controller, "GetMyPalBlackboard")
        if not self.a.valid(actions) or not self.a.valid(blackboard) then error(INITIALIZATION, 0) end
        if not self:_configure_movement(record,state,scope,member) then return "unavailable" end
        if not record.hostileConfigured then
            state.component.bIsAttackNonCriminal = true
            record.hostileConfigured = true
        end
        local defender = self:_choose_defender(scope, state, record)
        if defender then
            local now = self.bridge.clock()
            if not finite(now) then error(SCOPE, 0) end
            local current = self:_call("combat-action-status", actions, "GetCurrentAction_BP")
            local ended = not self.a.valid(current) and record.lastEncounterAt
                and now >= record.lastEncounterAt + self.bridge.config.customAssault.retargetSeconds
            if not record.target or not self.a.same(record.target, defender) or record.mode ~= "combat" or ended then
                local battle = self:_call("battle-manager", self.utility, "GetBattleManager", scope.world)
                if not self.a.valid(battle) then error(SCOPE, 0) end
                local player = self:_call("defender-kind", battle, "TargetIsPlayerOrPlayersOtomoPal", defender)
                if type(player) ~= "boolean" then error(SCOPE, 0) end
                self:_call("combat-target", controller, player and "AddTargetPlayer_ForEnemy" or "AddTargetNPC", defender)
                self:_call("stop-movement", controller, "StopMovement")
                self:_call("stop-travel-for-combat", actions, "TerminateCurrentActionByClass", self:_action_class("travel"))
                self:_set_action(actions, "encounter", scope.origin, defender)
                record.lastEncounterAt = now
                record.encounterRequests = (record.encounterRequests or 0) + 1
                self:_behavior(record, member, "combat", defender)
            end
            return true
        end
        local building = self:_call("enemy-building", self.utility, "GetNearestEnemyBuildObject", actor)
        if self.a.valid(building) then
            local base_id = self.a.guid(self:_call("building-base", building, "GetBaseCampIdBelongTo"))
            local location = vector(self:_call("building-location", building, "K2_GetActorLocation"))
            if base_id == scope.baseId and distance_squared(location, scope.origin) <= (scope.range + 1000) ^ 2 then
                self:_call("stop-travel-action", actions, "TerminateCurrentActionByClass", self:_action_class("travel"))
                if distance_squared(state.location, location) <= 300 * 300 then
                    self:_call("stop-at-building", controller, "StopMovement")
                    local now = self.bridge.clock()
                    local elapsed = record.lastBuildingTurnAt and now - record.lastBuildingTurnAt
                        or self.bridge.config.customAssault.retargetSeconds
                    if not finite(elapsed) or elapsed < 0 then error(SCOPE, 0) end
                    record.lastBuildingTurnAt = now
                    if elapsed > 0 then
                        self:_call("face-building", self.utility, "GeneralTurnToActor_WithMovementRotationSpeed", actor, building, math.min(elapsed, 1))
                    end
                    local in_reach = self:_call("building-melee-cone", self.utility, "InConeShapAndDitance_Actor", actor, building, 160, 300)
                    if type(in_reach) ~= "boolean" then error(ACTION, 0) end
                    local body = self:_call("body-action-component", actor, "GetActionComponent")
                    if not self.a.valid(body) then error(INITIALIZATION, 0) end
                    local idle = self:_call("body-action-idle", body, "ActionIsEmpty")
                    if type(idle) ~= "boolean" then error(ACTION, 0) end
                    if in_reach and idle then
                        local action = self:_call("attack-building", body, "PlayAction", building, self:_action_class("melee"))
                        if not self.a.valid(action) then error(ACTION, 0) end
                    end
                else
                    local result = self:_call("approach-building", controller, "PalMoveToLocation", location, 150, true, true, true, false, nil, false)
                    if result == 0 then
                        self:_behavior(record, member, "building-unreachable", building)
                        return "unavailable"
                    end
                    if result ~= 1 and result ~= 2 then error(ACTION, 0) end
                end
                self:_behavior(record, member, "building", building)
                return true
            end
        end
        if record.mode ~= "travel" then
            self:_set_action(actions, "travel", record.goal, nil)
            self:_behavior(record, member, "travel", nil)
        end
        return true
    end)
end

function Native:despawn(_, member)
    return self.bridge:_native_step("custom-despawn", function()
        local owned=self.records[member_key(member)]
        if self.cadenceLease and self.cadenceLease.record==owned and not self.cadenceLease:release("cleanup") then
            return "cadence-unresolved"
        end
        if owned and owned.shapeQualification then owned.shapeQualification:revoke_engagement("cleanup") end
        local state = self:_owned_state(member.handle, member)
        if TERMINAL[state.phase] then return state.phase end
        if state.phase == "despawning" then return "pending" end
        if state.phase == "pending" or state.phase == "capturing" then error(OWNERSHIP, 0) end
        local record = self.records[member_key(member)]
        self:_call("despawn-character", self.characterManager, "DespawnCharacterByHandle", record.handle, nil)
        record.despawnRequested = true
        local phase = self:_despawn_status(record)
        return phase == "missing" and "despawned" or (phase == "despawning" or phase == "capturing") and "pending" or phase
    end)
end

function Native:_despawn_status(record)
    local handle = self:_call("cleanup-handle", self.characterManager, "GetIndividualHandle", record.id)
    local actor
    if self.a.valid(handle) then
        local id = full_id(self:_call("cleanup-id", handle, "GetIndividualID"))
        if not same_id(id, record.id) then error(IDENTITY, 0) end
        local parameter = self:_call("cleanup-parameter", handle, "TryGetIndividualParameter")
        if self.a.valid(parameter) then
            if self:_captured_owner(parameter) then return "captured" end
            if record.parameter and not self.a.same(parameter, record.parameter) then error(IDENTITY, 0) end
            if not same_id(full_id(self:_call("cleanup-parameter-id", parameter, "GetPalId")), record.id)
                or self.a.text(self:_call("cleanup-character", parameter, "GetCharacterID")):lower() ~= record.characterId:lower() then
                error(IDENTITY, 0)
            end
        end
        actor = self:_call("cleanup-actor", handle, "TryGetIndividualActor")
        if self.a.valid(actor) then
            if not self.a.same(actor, record.actor) then error(IDENTITY, 0) end
            if not self.a.same(self:actor_world(actor), record.world) then error(SCOPE, 0) end
            local destroying = self:_call("cleanup-attached-destroying", actor, "IsActorBeingDestroyed")
            if type(destroying) ~= "boolean" then error(OWNERSHIP, 0) end
            if destroying then return "despawning" end
            local component = self:_call("cleanup-capture-component", actor, "GetCharacterParameterComponent")
            if not self.a.valid(component) then error(OWNERSHIP, 0) end
            local capture = self:_call("cleanup-capture", component, "GetIsCapturedProcessing")
            if type(capture) ~= "boolean" then error(OWNERSHIP, 0) end
            if capture then return "capturing" end
            return "despawning"
        end
    end
    if not self.a.valid(record.actor) then return "missing" end
    local destroying = self:_call("cleanup-original-destroying", record.actor, "IsActorBeingDestroyed")
    if type(destroying) ~= "boolean" then error(OWNERSHIP, 0) end
    if destroying then return "missing" end
    return self:_detached_capture(record) or "despawning"
end

function Native:cleanup_recovered(members, on_outcome)
    return self.bridge:_native_step("custom-recovery-cleanup", function()
        if type(on_outcome) ~= "function" then error(OWNERSHIP, 0) end
        self.recoveryPending = true
        local keys = util.sorted_keys(members)
        if #keys > self.bridge.config.limits.maxTargets then error(OWNERSHIP, 0) end
        if not self.recoveryStartedAt then
            if not self.a.valid(self.world) then
                local players = self.bridge:list_online_players()
                if #players == 0 then error("Custom assault recovery requires a live world context", 0) end
                self:prepare(players[1].world)
            end
            self.recoveryStartedAt = self.bridge.clock()
            self.recoveryCursor, self.recoveryCompleted = 1, {}
        end
        if not self.a.valid(self.world) then error(SCOPE, 0) end
        for _ = 1, math.min(#keys, self.bridge.config.customAssault.pollBatchSize) do
            local key = keys[self.recoveryCursor]
            self.recoveryCursor = self.recoveryCursor % #keys + 1
            local member, pending, outcome = members[key], false, nil
            if not self.recoveryCompleted[key] then
                local phase = member.phase or member.status
                local returned = member.outcome
                if TERMINAL[phase] or phase == "despawned" or phase == "cancelled" then
                    outcome = phase
                elseif TERMINAL[returned] or returned == "despawned" or returned == "cancelled" then
                    outcome = returned
                elseif member.spawnRequested or (member.lastTransition and member.lastTransition ~= "custom_placement_intent"
                    and member.lastTransition ~= "custom_placement_observed") then
                    if not member.instanceGuid or not member.playerGuid then
                        error("Custom assault recovery has an unidentified spawn outcome", 0)
                    end
                    local id = { PlayerUId = guid(member.playerGuid, true), InstanceId = guid(member.instanceGuid, false), DebugName = "" }
                    local handle = self:_call("recover-handle", self.characterManager, "GetIndividualHandle", id)
                    local retained = self.records[member_key(member)]
                    if retained and retained.despawnRequested then
                        outcome = self:_despawn_status(retained)
                        pending = outcome == "despawning" or outcome == "capturing"
                    elseif self.a.valid(handle) then
                        local scope = { world = self.world, origin = { X = 0, Y = 0, Z = 0 }, leashRadius = math.huge }
                        if not self.records[member_key(member)] then
                            self.records[member_key(member)] = { id = id, world = self.world, characterId = member.characterId, scope = scope }
                        end
                        local ok
                        ok, outcome = self:despawn(scope, {
                            index = member.index, baseId = member.baseId, groupId = member.groupId,
                            characterId = member.characterId, handle = handle,
                        })
                        if not ok then error(outcome, 0) end
                        pending = outcome == "pending"
                    elseif retained and retained.initialized then
                        outcome = self:_absent_state(retained).phase
                        pending = outcome == "capturing"
                    else
                        pending = true
                    end
                else
                    outcome = "cancelled"
                end
                if not pending then
                    if on_outcome(member.index, outcome) ~= true then
                        error("Custom assault recovery outcome could not be persisted", 0)
                    end
                    self.recoveryCompleted[key] = true
                end
            end
        end
        self.recoveryPending = util.count(self.recoveryCompleted) < #keys
        local timeout = self.bridge.config.customAssault.initializationSeconds
            + math.ceil(#keys / self.bridge.config.customAssault.pollBatchSize) * self.bridge.config.runtime.pollIntervalMs / 1000
        if self.recoveryPending and self.bridge.clock() >= self.recoveryStartedAt + timeout then
            error("Custom assault despawn did not complete", 0)
        end
        return self.recoveryPending and "pending" or "complete"
    end)
end

return Native
