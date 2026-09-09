local util = require("ped.util")

local Survey = {}
Survey.__index = Survey

local ERROR = "Custom assault scope is invalid"
local WORLD_PACKAGE = "/Game/Pal/Maps/MainWorld_5/PL_MainWorld5"
local WATER_CLASS = "/Game/Others/FluidInteractionTool/Blueprints/NotNeeded/BP_SimpleWater.BP_SimpleWater_C"
local WATER_MESH = "/Game/Others/FluidInteractionTool/Meshes/S_WaterMesh.S_WaterMesh"
local COLUMN_HALF_HEIGHT = 100010000

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

local function vector(value)
    if value==nil or not finite(value.X) or not finite(value.Y) or not finite(value.Z) then error(ERROR,0) end
    return {X=value.X,Y=value.Y,Z=value.Z}
end

local function channel(value)
    if not util.is_integer(value) or value<0 or value>31 then error(ERROR,0) end
    return value
end

local function count(values,maximum)
    if type(values)~="table" or getmetatable(values)~=nil then error(ERROR,0) end
    local n,total=#values,0
    if n>maximum then return nil end
    for key in pairs(values) do
        if not util.is_integer(key) or key<1 or key>n then error(ERROR,0) end
        total=total+1
    end
    if total~=n then error(ERROR,0) end
    return n
end

function Survey.new(native,scope,options)
    return setmetatable({native=native,a=native.a,bridge=native.bridge,scope=scope,world=scope.world,
        clock=options and options.clock or os.clock,
        result={complete=false,spawnQualified=false,templateOnly=true,queries=0},waters={}},Survey)
end

function Survey:_call(label,owner,method,...)
    return self.native:_call("survey-"..label,owner,method,...)
end

function Survey:_stop(code)
    self.result.code=code
    return self.result
end

function Survey:_qualify()
    local n=self.native
    for _,entry in ipairs({
        {"/Script/Engine.KismetSystemLibrary:BoxOverlapComponents",{
            WorldContextObject={"ObjectProperty",0},BoxPos={"StructProperty",8},Extent={"StructProperty",32},
            ObjectTypes={"ArrayProperty",56},ComponentClassFilter={"ClassProperty",72},
            ActorsToIgnore={"ArrayProperty",80},OutComponents={"ArrayProperty",96},ReturnValue={"BoolProperty",112}}},
        {"/Script/Engine.KismetSystemLibrary:CapsuleOverlapComponents",{
            WorldContextObject={"ObjectProperty",0},CapsulePos={"StructProperty",8},Radius={"FloatProperty",32},
            HalfHeight={"FloatProperty",36},ObjectTypes={"ArrayProperty",40},ComponentClassFilter={"ClassProperty",56},
            ActorsToIgnore={"ArrayProperty",64},OutComponents={"ArrayProperty",80},ReturnValue={"BoolProperty",96}}},
        {"/Script/Engine.KismetSystemLibrary:GetComponentBounds",{
            Component={"ObjectProperty",0},Origin={"StructProperty",8},BoxExtent={"StructProperty",32},SphereRadius={"FloatProperty",56}}},
        {"/Script/Engine.GameplayStatics:GetAllActorsOfClass",{
            WorldContextObject={"ObjectProperty",0},ActorClass={"ClassProperty",8},OutActors={"ArrayProperty",16}}},
        {"/Script/Engine.GameplayStatics:GetWorldOriginLocation",{
            WorldContextObject={"ObjectProperty",0},ReturnValue={"StructProperty",8}}},
        {"/Script/Pal.PalUtility:GetWorldOceanPlaneZ",{WorldContextObject={"ObjectProperty",0},ReturnValue={"FloatProperty",8}}},
        {"/Script/Pal.PalUtility:GetPalGameStateInGame",{WorldContextObject={"ObjectProperty",0},ReturnValue={"ObjectProperty",8}}},
        {"/Script/Pal.PalUtility:GetEngineCollisionChannelByPalTraceType",{type={"EnumProperty",0},ReturnValue={"ByteProperty",1}}},
        {"/Script/Engine.PrimitiveComponent:GetCollisionEnabled",{ReturnValue={"ByteProperty",0}}},
        {"/Script/Engine.PrimitiveComponent:GetCollisionObjectType",{ReturnValue={"ByteProperty",0}}},
        {"/Script/Engine.PrimitiveComponent:GetCollisionResponseToChannel",{Channel={"ByteProperty",0},ReturnValue={"ByteProperty",1}}},
        {"/Script/Engine.InstancedStaticMeshComponent:GetInstanceCount",{ReturnValue={"IntProperty",0}}},
    }) do n:_signature(entry[1],entry[2]) end
    self.kismet=self.bridge:_static_find("/Script/Engine.Default__KismetSystemLibrary")
    self.gameplay=self.bridge:_static_find("/Script/Engine.Default__GameplayStatics")
    self.mesh=self.bridge:_static_find(WATER_MESH)
    if not self.a.valid(self.kismet) or not self.a.valid(self.gameplay) or not self.a.valid(self.mesh) then error(ERROR,0) end
end

function Survey:_response(component,to_channel)
    local value=self:_call("response",component,"GetCollisionResponseToChannel",channel(to_channel))
    if not util.is_integer(value) or value<0 or value>2 then error(ERROR,0) end
    return value
end

function Survey:_component(component)
    if not self.a.valid(component) or not component:IsA("/Script/Engine.PrimitiveComponent") then error(ERROR,0) end
    local owner=self:_call("owner",component,"GetOwner")
    if not self.a.valid(owner) or not self.a.same(self:_call("component-world",component,"GetWorld"),self.world)
        or not self.a.same(self:_call("owner-world",owner,"GetWorld"),self.world) then error(ERROR,0) end
    local enabled=self:_call("collision-enabled",component,"GetCollisionEnabled")
    if enabled~=1 and enabled~=3 then return nil,"query-state-unqualified" end
    return {owner=owner,objectType=channel(self:_call("object-type",component,"GetCollisionObjectType"))}
end

function Survey:_bounds(component)
    if not finite(component.BoundsScale) or component.BoundsScale<1 then return nil end
    local center,extent,sphere={},{},{}
    self:_call("bounds",self.kismet,"GetComponentBounds",component,center,extent,sphere)
    center,extent=vector(center),vector(extent)
    if extent.X<0 or extent.Y<0 or extent.Z<0 or not finite(sphere.SphereRadius) or sphere.SphereRadius<0 then error(ERROR,0) end
    if math.abs(center.Z)+extent.Z>COLUMN_HALF_HEIGHT then return nil end
    return {center=center,extent=extent,top=center.Z+extent.Z}
end

function Survey:_water(component)
    for _,entry in ipairs(self.waters) do
        if self.a.same(component,entry.volume) then return "volume",entry end
    end
    if self:_response(component,self.waterChannel)~=2 then return nil end
    if not component:IsA("/Script/Engine.StaticMeshComponent")
        or not self.a.same(self.a.unwrap(component.StaticMesh),self.mesh) then return "unsupported" end
    local bounds=self:_bounds(component)
    if not bounds or bounds.extent.Z>1 then return "unsupported" end
    for _,entry in ipairs(self.waters) do
        if self.a.same(component,entry.surface) then return "surface",entry,bounds end
    end
    return "surface",nil,bounds
end

function Survey:_environment()
    if not self.a.valid(self.world) or not self.world:IsA("/Script/Engine.World") then error(ERROR,0) end
    local package=self.world:GetOuter()
    if not self.a.valid(package) or package:GetFName():ToString():lower()~=WORLD_PACKAGE:lower() then
        return false,"world-certificate-mismatch"
    end
    local origin=vector(self:_call("world-origin",self.gameplay,"GetWorldOriginLocation",self.world))
    if origin.X~=0 or origin.Y~=0 or origin.Z~=0 then return false,"world-origin-unqualified" end
    local persistent=self.a.unwrap(self.world.PersistentLevel)
    if not self.a.valid(persistent) then return false,"persistent-level-unavailable" end
    local game_state=self:_call("game-state",self.native.utility,"GetPalGameStateInGame",self.world)
    if not self.a.valid(game_state) or not game_state:IsA("/Script/Pal.PalGameStateInGame")
        or not self.a.same(self:_call("game-state-world",game_state,"GetWorld"),self.world) then
        return false,"game-state-unavailable"
    end
    local ocean_z=self:_call("ocean-height",self.native.utility,"GetWorldOceanPlaneZ",self.world)
    if not finite(ocean_z) or math.abs(ocean_z)>=COLUMN_HALF_HEIGHT then error(ERROR,0) end
    local actors={}
    local water_class=self.native:_class(WATER_CLASS)
    self:_call("water-cohort",self.gameplay,"GetAllActorsOfClass",self.world,water_class,actors)
    local total=count(actors,64)
    if not total then return false,"water-cohort-over-cap" end
    self.result.waterActors=total
    local persistent_count,other_count,ocean_count=0,0,0
    for index=1,total do
        local actor=self.a.unwrap(actors[index])
        if not self.a.valid(actor) or not actor:IsA(WATER_CLASS)
            or not self.a.same(self:_call("cohort-world",actor,"GetWorld"),self.world) then
            return false,"water-cohort-scope"
        end
        if self.a.same(actor:GetOuter(),persistent) then persistent_count=persistent_count+1
        else other_count=other_count+1 end
        if type(actor.bWorldOceanPlane)~="boolean" then error(ERROR,0) end
        if actor.bWorldOceanPlane then ocean_count=ocean_count+1 end
    end
    self.result.persistentWaterActors,self.result.otherLevelWaterActors,self.result.oceanActors=persistent_count,other_count,ocean_count
    if total~=10 or persistent_count~=10 then return false,"water-cohort-incomplete" end
    self.waterChannel=channel(self:_call("water-channel",self.native.utility,"GetEngineCollisionChannelByPalTraceType",4))
    local oceans,instance_counts=0,{}
    for index=1,total do
        local actor=self.a.unwrap(actors[index])
        if not self.a.valid(actor) or not actor:IsA(WATER_CLASS) or not self.a.same(actor:GetOuter(),persistent) then
            return false,"water-cohort-scope"
        end
        for _,entry in ipairs(self.waters) do if self.a.same(entry.actor,actor) then return false,"water-cohort-duplicate" end end
        local volume,surface=self.a.unwrap(actor.SwimmingVolume),self.a.unwrap(actor.HierarchicalInstancedStaticMesh)
        if not self.a.valid(volume) or not volume:IsA("/Script/Engine.BoxComponent")
            or not self.a.valid(surface) or not surface:IsA("/Script/Engine.InstancedStaticMeshComponent") then
            return false,"water-shape-unavailable"
        end
        local vi,si=self:_component(volume),self:_component(surface)
        if not vi or not si or not self.a.same(vi.owner,actor) or not self.a.same(si.owner,actor)
            or not self.a.same(self.a.unwrap(surface.StaticMesh),self.mesh) then return false,"water-shape-scope" end
        local vb,sb=self:_bounds(volume),self:_bounds(surface)
        if not vb or not sb or sb.extent.Z>1 or self:_response(surface,self.waterChannel)~=2 then
            return false,"water-bounds-unqualified"
        end
        local instances=self:_call("water-instances",surface,"GetInstanceCount")
        if not util.is_integer(instances) or instances<1 or instances>2000 then return false,"water-instances-unqualified" end
        instance_counts[instances]=(instance_counts[instances] or 0)+1
        local ocean=actor.bWorldOceanPlane
        if type(ocean)~="boolean" then error(ERROR,0) end
        if ocean then
            oceans=oceans+1
            local location=vector(self:_call("ocean-location",actor,"K2_GetActorLocation"))
            if math.abs(location.Z-ocean_z)>1 or math.abs(sb.center.Z-ocean_z)>1 then return false,"ocean-witness-mismatch" end
        end
        self.waters[#self.waters+1]={actor=actor,volume=volume,surface=surface,ocean=ocean,volumeBounds=vb,surfaceBounds=sb}
    end
    if oceans~=1 or instance_counts[1]~=2 or instance_counts[4]~=6 or instance_counts[1681]~=1 or instance_counts[356]~=1 then
        return false,"water-cohort-geometry"
    end
    self.result.oceanWitness=true
    return true
end

function Survey:_query(method,label,...)
    local output={}
    local before=self.clock()
    local args=table.pack(...)
    args.n=args.n+1
    args[args.n]=output
    local found=self:_call(label,self.kismet,method,self.world,table.unpack(args,1,args.n))
    local elapsed=self.clock()-before
    if type(found)~="boolean" or not finite(elapsed) or elapsed<0 then error(ERROR,0) end
    self.result.queries=self.result.queries+1
    self.result[label.."ClockSeconds"]=elapsed
    local total=count(output,128)
    if not total then return nil,label.."-over-cap" end
    if found~=(total>0) then error(ERROR,0) end
    if elapsed>0.25 then return nil,label.."-slow" end
    self.result[label.."Components"]=total
    return output
end

function Survey:run()
    self:_qualify()
    local shape,shape_reason=self.native:_placement_shape("BOSS_Hunter_Rifle")
    self.result.bodyProxy=shape and shape.bodyProxy and util.deep_copy(shape.bodyProxy)
    self.result.bodyProxyReason=shape_reason or (shape and shape.bodyProxyReason)
    local ready,reason=self:_environment()
    if not ready then return self:_stop(reason) end
    if not shape or not shape.bodyProxy then return self:_stop(self.result.bodyProxyReason or "body-proxy-unavailable") end
    local candidate=self.scope.positions[1] or self.scope.origin
    local point=self.native:startup_floor(self.world,candidate,"BOSS_Hunter_Rifle")
    if not point then point=self.native:startup_floor(self.world,self.scope.origin,"BOSS_Hunter_Rifle") end
    if not point then return self:_stop("survey-floor-unavailable") end
    local proxy=shape.bodyProxy
    if proxy.radius>1000 or proxy.halfHeight>2000 then return self:_stop("survey-proxy-limit") end
    local queries={}
    for index=0,31 do queries[index+1]=index end
    local center=vector(point)
    center.Z=center.Z+proxy.centerOffsetZ
    local lower_foot=math.min(center.Z-proxy.halfHeight,point.Z+proxy.lowerFootOffsetZ)
    local components
    components,reason=self:_query("BoxOverlapComponents","column",
        {X=point.X,Y=point.Y,Z=0},{X=proxy.radius+10,Y=proxy.radius+10,Z=COLUMN_HALF_HEIGHT},queries,nil,{})
    if not components then return self:_stop(reason) end
    local ocean_surface,ocean_volume,water_count,top=false,false,0,nil
    for _,wrapped in ipairs(components) do
        local component=self.a.unwrap(wrapped)
        local info,why=self:_component(component)
        if not info then return self:_stop(why) end
        local kind,water,bounds=self:_water(component)
        if kind=="unsupported" then return self:_stop("water-representation-unqualified") end
        if kind then
            water_count=water_count+1
            bounds=bounds or water.volumeBounds
            top=math.max(top or bounds.top,bounds.top)
            if water and water.ocean then
                ocean_surface=ocean_surface or kind=="surface"
                ocean_volume=ocean_volume or kind=="volume"
            end
        end
    end
    self.result.columnWaterComponents=water_count
    self.result.columnOceanWitness=ocean_surface and ocean_volume
    if not self.result.columnOceanWitness or top==nil then return self:_stop("column-water-witness-missing") end
    self.result.footAboveWaterCm=lower_foot-top
    local source=self:_call("source-enabled",shape.capsule,"GetCollisionEnabled")
    if source~=1 and source~=3 then return self:_stop("source-response-unqualified") end
    local source_type=channel(self:_call("source-type",shape.capsule,"GetCollisionObjectType"))
    local responses={}
    for to=0,31 do responses[to]=self:_response(shape.capsule,to) end
    components,reason=self:_query("CapsuleOverlapComponents","capsule",center,proxy.radius,proxy.halfHeight,queries,nil,{})
    if not components then return self:_stop(reason) end
    local contacts,blockers,unknown=0,0,0
    for _,wrapped in ipairs(components) do
        local component=self.a.unwrap(wrapped)
        local info,why=self:_component(component)
        if not info then return self:_stop(why) end
        local kind=self:_water(component)
        if kind=="unsupported" then return self:_stop("water-representation-unqualified") end
        if kind then contacts=contacts+1 end
        if component:IsA("/Script/Engine.InstancedStaticMeshComponent") or component:IsA("/Script/Engine.SkinnedMeshComponent") then
            if not kind then unknown=unknown+1 end
        elseif responses[info.objectType]==2 and self:_response(component,source_type)==2 then
            blockers=blockers+1
        end
    end
    self.result.waterContacts,self.result.mutualBlockers,self.result.unqualifiedBodies=contacts,blockers,unknown
    self.result.classification=(contacts>0 or self.result.footAboveWaterCm<=10) and "wet"
        or blockers>0 and "blocked" or unknown>0 and "unsupported" or "proxy-clear"
    self.result.complete=true
    self.result.code="proxy-survey-observed"
    return self.result
end

return Survey
