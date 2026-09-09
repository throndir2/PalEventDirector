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
        requestedPoint=options and options.point and vector(options.point),
        supportWitness=options and options.supportWitness,
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

function Survey:_qualify_local()
    local n=self.native
    for _,entry in ipairs({
        {"/Script/Engine.KismetSystemLibrary:CapsuleOverlapComponents",{
            WorldContextObject={"ObjectProperty",0},CapsulePos={"StructProperty",8},Radius={"FloatProperty",32},
            HalfHeight={"FloatProperty",36},ObjectTypes={"ArrayProperty",40},ComponentClassFilter={"ClassProperty",56},
            ActorsToIgnore={"ArrayProperty",64},OutComponents={"ArrayProperty",80},ReturnValue={"BoolProperty",96}}},
        {"/Script/Engine.Actor:GetLevel",{ReturnValue={"ObjectProperty",0}}},
        {"/Script/Engine.Actor:K2_GetRootComponent",{ReturnValue={"ObjectProperty",0}}},
        {"/Script/Engine.ActorComponent:GetOwner",{ReturnValue={"ObjectProperty",0}}},
        {"/Script/Engine.CapsuleComponent:GetScaledCapsuleRadius",{ReturnValue={"FloatProperty",0}}},
        {"/Script/Engine.CapsuleComponent:GetScaledCapsuleHalfHeight",{ReturnValue={"FloatProperty",0}}},
        {"/Script/Pal.PalUtility:GetEngineCollisionChannelByPalTraceType",{type={"EnumProperty",0},ReturnValue={"ByteProperty",1}}},
        {"/Script/Engine.PrimitiveComponent:GetCollisionEnabled",{ReturnValue={"ByteProperty",0}}},
        {"/Script/Engine.PrimitiveComponent:GetCollisionObjectType",{ReturnValue={"ByteProperty",0}}},
        {"/Script/Engine.PrimitiveComponent:GetCollisionProfileName",{ReturnValue={"NameProperty",0}}},
        {"/Script/Pal.PalUtility:GetEngineCollisionChannelByPalObjectType",{type={"EnumProperty",0},ReturnValue={"ByteProperty",1}}},
        {"/Script/Engine.PrimitiveComponent:GetCollisionResponseToChannel",{Channel={"ByteProperty",0},ReturnValue={"ByteProperty",1}}},
    }) do n:_signature(entry[1],entry[2]) end
    self.kismet=self.bridge:_static_find("/Script/Engine.Default__KismetSystemLibrary")
    self.mesh=self.bridge:_static_find(WATER_MESH)
    if not self.a.valid(self.kismet) or not self.a.valid(self.mesh) then error(ERROR,0) end
end

function Survey:_qualify()
    self:_qualify_local()
    for _,entry in ipairs({
        {"/Script/Engine.KismetSystemLibrary:BoxOverlapComponents",{
            WorldContextObject={"ObjectProperty",0},BoxPos={"StructProperty",8},Extent={"StructProperty",32},
            ObjectTypes={"ArrayProperty",56},ComponentClassFilter={"ClassProperty",72},
            ActorsToIgnore={"ArrayProperty",80},OutComponents={"ArrayProperty",96},ReturnValue={"BoolProperty",112}}},
        {"/Script/Engine.KismetSystemLibrary:GetComponentBounds",{
            Component={"ObjectProperty",0},Origin={"StructProperty",8},BoxExtent={"StructProperty",32},SphereRadius={"FloatProperty",56}}},
        {"/Script/Engine.GameplayStatics:GetAllActorsOfClass",{
            WorldContextObject={"ObjectProperty",0},ActorClass={"ClassProperty",8},OutActors={"ArrayProperty",16}}},
        {"/Script/Engine.GameplayStatics:GetWorldOriginLocation",{
            WorldContextObject={"ObjectProperty",0},ReturnValue={"StructProperty",8}}},
        {"/Script/Pal.PalUtility:GetWorldOceanPlaneZ",{WorldContextObject={"ObjectProperty",0},ReturnValue={"FloatProperty",8}}},
        {"/Script/Pal.PalUtility:GetPalGameStateInGame",{WorldContextObject={"ObjectProperty",0},ReturnValue={"ObjectProperty",8}}},
        {"/Script/Engine.InstancedStaticMeshComponent:GetInstanceCount",{ReturnValue={"IntProperty",0}}},
    }) do self.native:_signature(entry[1],entry[2]) end
    self.gameplay=self.bridge:_static_find("/Script/Engine.Default__GameplayStatics")
    if not self.a.valid(self.gameplay) then error(ERROR,0) end
end

function Survey:_response(component,to_channel)
    local value=self:_call("response",component,"GetCollisionResponseToChannel",channel(to_channel))
    if not util.is_integer(value) or value<0 or value>2 then error(ERROR,0) end
    return value
end

function Survey:_component(component)
    if not self.a.valid(component) or not component:IsA("/Script/Engine.PrimitiveComponent") then error(ERROR,0) end
    local owner=self:_call("owner",component,"GetOwner")
    if not self.a.valid(owner) or not owner:IsA("/Script/Engine.Actor")
        or not self.a.same(self:_call("component-world",component,"GetWorld"),self.world)
        or not self.a.same(self.native:actor_world(owner),self.world) then error(ERROR,0) end
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

function Survey:_water(component,owner,contact_only)
    for _,entry in ipairs(self.waters) do
        if self.a.same(component,entry.volume) then return "volume",entry end
    end
    if owner and owner:IsA(WATER_CLASS) then
        local volume=self.a.unwrap(owner.SwimmingVolume)
        if not self.a.valid(volume) or not volume:IsA("/Script/Engine.BoxComponent") then return "unsupported" end
        if self.a.same(component,volume) then
            return contact_only and "volume" or "unsupported"
        end
    end
    if self:_response(component,self.waterChannel)~=2 then return nil end
    if not component:IsA("/Script/Engine.StaticMeshComponent")
        or not self.a.same(self.a.unwrap(component.StaticMesh),self.mesh) then return "unsupported" end
    -- Any identified local water contact is a veto; no water-top/flatness certificate is needed to reject it.
    if contact_only then return "surface" end
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
        or not self.a.same(self.native:actor_world(game_state),self.world) then
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
    local persistent_count,other_count,ocean_count,foreign_count,worldless_count=0,0,0,0,0
    local levels={}
    for index=1,total do
        local actor=self.a.unwrap(actors[index])
        if not self.a.valid(actor) or not actor:IsA(WATER_CLASS) then return false,"water-cohort-scope" end
        local actor_world,level=self.native:actor_world(actor)
        levels[index]=level
        if not self.a.valid(actor_world) then
            worldless_count=worldless_count+1
        elseif not self.a.same(actor_world,self.world) then
            foreign_count=foreign_count+1
        else
            if self.a.same(level,persistent) then persistent_count=persistent_count+1
            else other_count=other_count+1 end
            if type(actor.bWorldOceanPlane)~="boolean" then error(ERROR,0) end
            if actor.bWorldOceanPlane then ocean_count=ocean_count+1 end
        end
    end
    self.result.persistentWaterActors,self.result.otherLevelWaterActors,self.result.oceanActors=persistent_count,other_count,ocean_count
    self.result.foreignWorldWaterActors,self.result.worldlessWaterActors=foreign_count,worldless_count
    if foreign_count>0 or worldless_count>0 then return false,"water-cohort-world-mismatch" end
    if persistent_count~=10 then return false,"water-cohort-incomplete" end
    self.waterChannel=channel(self:_call("water-channel",self.native.utility,"GetEngineCollisionChannelByPalTraceType",4))
    local oceans,persistent_oceans,instance_counts=0,0,{}
    for index=1,total do
        local actor=self.a.unwrap(actors[index])
        if not self.a.valid(actor) or not actor:IsA(WATER_CLASS) then
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
        if self.a.same(levels[index],persistent) then instance_counts[instances]=(instance_counts[instances] or 0)+1 end
        local ocean=actor.bWorldOceanPlane
        if type(ocean)~="boolean" then error(ERROR,0) end
        if ocean then
            oceans=oceans+1
            if self.a.same(levels[index],persistent) then persistent_oceans=persistent_oceans+1 end
            local location=vector(self:_call("ocean-location",actor,"K2_GetActorLocation"))
            if math.abs(location.Z-ocean_z)>1 or math.abs(sb.center.Z-ocean_z)>1 then return false,"ocean-witness-mismatch" end
        end
        self.waters[#self.waters+1]={actor=actor,volume=volume,surface=surface,ocean=ocean,volumeBounds=vb,surfaceBounds=sb}
    end
    if oceans<1 or persistent_oceans~=1 or instance_counts[1]~=2 or instance_counts[4]~=6
        or instance_counts[1681]~=1 or instance_counts[356]~=1 then
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
    local reason_prefix=label:gsub("(%u)","-%1"):lower()
    local found=self:_call(reason_prefix,self.kismet,method,self.world,table.unpack(args,1,args.n))
    local elapsed=self.clock()-before
    if type(found)~="boolean" or not finite(elapsed) or elapsed<0 then error(ERROR,0) end
    self.result.queries=self.result.queries+1
    self.result[label.."ClockSeconds"]=elapsed
    local total=count(output,128)
    self.result[label.."Components"]=#output
    if not total then return nil,reason_prefix.."-over-cap" end
    if found~=(total>0) then error(ERROR,0) end
    if elapsed>0.25 then return nil,reason_prefix.."-slow" end
    return output
end

function Survey:_proxy(shape)
    local proxy=shape and shape.bodyProxy
    if not proxy or proxy.templateOnly~=true or not finite(proxy.radius) or not finite(proxy.halfHeight)
        or not finite(proxy.centerOffsetZ) or not finite(proxy.lowerFootOffsetZ)
        or proxy.radius<=0 or proxy.halfHeight<proxy.radius or proxy.radius>1000 or proxy.halfHeight>2000
        or math.abs(proxy.centerOffsetZ)>proxy.halfHeight then return nil end
    return proxy
end

local function component_category(component)
    if component:IsA("/Script/Engine.InstancedStaticMeshComponent") then return "instancedMesh" end
    if component:IsA("/Script/Engine.SkinnedMeshComponent") then return "skinnedMesh" end
    if component:IsA("/Script/Engine.StaticMeshComponent") then return "staticMesh" end
    if component:IsA("/Script/Engine.ShapeComponent") then return "shape" end
    return "other"
end

function Survey:_physical_policy(shape)
    if not shape or not finite(shape.radius) or not finite(shape.halfHeight) or shape.radius<=0
        or shape.radius>500 or shape.halfHeight<shape.radius or shape.halfHeight>1000 then
        return nil,"root-capsule-unqualified"
    end
    local mesh,reason=self.native:placement_mesh_policy(shape)
    if not mesh then return nil,reason end
    local radius=self:_call("root-policy-radius",shape.capsule,"GetScaledCapsuleRadius")
    local half=self:_call("root-policy-height",shape.capsule,"GetScaledCapsuleHalfHeight")
    if not finite(radius) or not finite(half) or math.abs(radius-shape.radius)>0.001 or math.abs(half-shape.halfHeight)>0.001 then
        return nil,"root-capsule-policy-changed"
    end
    if not shape.bodyProxy or not finite(shape.bodyProxy.meshOffsetZ)
        or math.abs(mesh.relativeLocation.Z-shape.bodyProxy.meshOffsetZ)>0.001 then return nil,"mesh-policy-transform" end
    return {policy="physical-root-and-water-only-mesh-envelope",
        rootCapsule={radius=shape.radius,halfHeight=shape.halfHeight,centerOffsetZ=0},mesh=mesh}
end

function Survey:_support_association(point,shape)
    self.associationComponent=nil
    local result={diagnosticOnly=true,contactExceptionEnabled=false,bodyScopeQualified=false,witnessQualified=false,
        label="SUPPORT_WITNESS_UNAVAILABLE",matchingSupportBlockers=0,otherBlockers=0,unassociatedBlockers=0}
    local witness=self.supportWitness
    if not witness then return result end
    local now=self.native.bridge.clock()
    if not finite(now) or not finite(witness.createdAt) or now<witness.createdAt or now>witness.createdAt+2 then
        result.label="STALE_SUPPORT_WITNESS"; return result
    end
    result.label="UNQUALIFIED_SUPPORT_WITNESS"
    if witness.native~=self.native or witness.scope~=self.scope or not self.a.same(witness.world,self.world)
        or not self.a.same(witness.cdo,shape.cdo) or not self.a.same(witness.capsule,shape.capsule)
        or witness.radius~=shape.radius or witness.halfHeight~=shape.halfHeight
        or not finite(witness.walkableZ) or witness.walkableZ~=shape.walkableZ
        or witness.qualified~=true
        or witness.traceType~=3 or witness.traceComplex~=false or not witness.startClear or not witness.upwardClear then return result end
    local scale,rotation=shape.capsule.RelativeScale3D,shape.capsule.RelativeRotation
    if not scale or not rotation then return result end
    for _,axis in ipairs({"X","Y","Z"}) do
        if not witness.point or witness.point[axis]~=point[axis] or not witness.rootScale
            or witness.rootScale[axis]~=scale[axis] then return result end
    end
    for _,axis in ipairs({"Pitch","Yaw","Roll"}) do
        if not witness.rootRotation or witness.rootRotation[axis]~=rotation[axis] then return result end
    end
    local component=witness.component
    if not self.a.valid(component) or not component:IsA("/Script/Engine.PrimitiveComponent") or not self.a.valid(witness.owner) then return result end
    local owner=self:_call("support-association-owner",component,"GetOwner")
    if not self.a.same(owner,witness.owner) or not owner:IsA("/Script/Engine.Actor")
        or not self.a.same(self:_call("support-association-world",component,"GetWorld"),self.world)
        or not self.a.same(self.native:actor_world(owner),self.world) then return result end
    local ground=self:_call("support-association-ground-channel",self.native.utility,"GetEngineCollisionChannelByPalTraceType",3)
    if ground~=witness.groundChannel or not util.is_integer(ground) or ground<0 or ground>31 then return result end
    local enabled=self:_call("support-association-enabled",component,"GetCollisionEnabled")
    local response=self:_call("support-association-ground-response",component,"GetCollisionResponseToChannel",ground)
    if enabled~=witness.enabled or (enabled~=1 and enabled~=3) or response~=2 or witness.groundResponse~=2 then return result end
    result.witnessQualified=true
    result.trace={}
    for _,key in ipairs({"time","distanceCm","traceLengthCm","reconstructionErrorCm","distanceTimeErrorCm","signedProposedMinusHitZ"}) do
        local value=witness.metrics and witness.metrics[key]
        if finite(value) and math.abs(value)<=100 then result.trace[key]=value end
    end
    for _,key in ipairs({"positiveTimeDistance","traceEchoAvailable","traceEchoAgreement","reconstructionAgreement",
        "distanceTimeAgreement","sameXY","atOrBeforeReportedTOI"}) do
        local value=witness.metrics and witness.metrics[key]
        if type(value)=="boolean" then result.trace[key]=value end
    end
    self.associationComponent=component
    return result
end

function Survey:_classify_contacts(components,physical,association)
    local contacts,blockers,unknown,unsupported=0,0,0,nil
    local result={components=#components,componentCategories={},nonWaterContacts=0,distinctComponents=0,distinctMutualBlockers=0}
    local seen_components,seen_blockers={},{}
    local function first(values,component)
        for _,previous in ipairs(values) do if self.a.same(previous,component) then return false end end
        values[#values+1]=component
        return true
    end
    for _,wrapped in ipairs(components) do
        local component=self.a.unwrap(wrapped)
        local info,why=self:_component(component)
        local category=component_category(component)
        local counts=result.componentCategories[category] or
            {components=0,waterContacts=0,mutualBlockers=0,unqualifiedBodies=0,nonWaterContacts=0,
                distinctComponents=0,distinctMutualBlockers=0,matchingSupportBlockers=0,otherBlockers=0}
        result.componentCategories[category]=counts
        counts.components=counts.components+1
        if first(seen_components,component) then
            result.distinctComponents=result.distinctComponents+1
            counts.distinctComponents=counts.distinctComponents+1
        end
        local kind=info and self:_water(component,info.owner,true)
        if not info or kind=="unsupported" then
            unknown,counts.unqualifiedBodies=unknown+1,counts.unqualifiedBodies+1
            unsupported=unsupported or why or "water-representation-unqualified"
        else
            if kind then contacts,counts.waterContacts=contacts+1,counts.waterContacts+1 end
            if not kind then
                result.nonWaterContacts=result.nonWaterContacts+1
                counts.nonWaterContacts=counts.nonWaterContacts+1
            end
            if category~="shape" and category~="staticMesh" then
                if not kind then unknown,counts.unqualifiedBodies=unknown+1,counts.unqualifiedBodies+1 end
            elseif physical and self.effectiveSourceCollision.responses[info.objectType+1]==2
                and self:_response(component,self.sourceCollision.objectType)==2 then
                blockers,counts.mutualBlockers=blockers+1,counts.mutualBlockers+1
                if first(seen_blockers,component) then
                    result.distinctMutualBlockers=result.distinctMutualBlockers+1
                    counts.distinctMutualBlockers=counts.distinctMutualBlockers+1
                    if association then
                        if not association.witnessQualified then
                            association.unassociatedBlockers=association.unassociatedBlockers+1
                        elseif self.a.same(component,self.associationComponent) then
                            association.matchingSupportBlockers=association.matchingSupportBlockers+1
                            counts.matchingSupportBlockers=counts.matchingSupportBlockers+1
                        else
                            association.otherBlockers=association.otherBlockers+1
                            counts.otherBlockers=counts.otherBlockers+1
                        end
                    end
                end
            end
        end
    end
    result.waterContacts,result.mutualBlockers,result.unqualifiedBodies=contacts,blockers,unknown
    result.duplicateComponents=result.components-result.distinctComponents
    result.duplicateMutualBlockers=result.mutualBlockers-result.distinctMutualBlockers
    if association then
        if association.witnessQualified then
            local now=self.native.bridge.clock()
            if not finite(now) or now<self.supportWitness.createdAt or now>self.supportWitness.createdAt+2 then
                association.witnessQualified=false
                association.label="STALE_SUPPORT_WITNESS"
            end
        end
        if association.witnessQualified then
            local trace=association.trace
            if association.otherBlockers>0 then association.label="OTHER_BLOCKERS"
            elseif association.matchingSupportBlockers==0 then association.label="NO_ROOT_BLOCKERS"
            elseif trace.signedProposedMinusHitZ and trace.signedProposedMinusHitZ<0 then association.label="PAST_TOI_AMBIGUOUS"
            elseif trace.positiveTimeDistance and trace.traceEchoAgreement and trace.reconstructionAgreement
                and trace.distanceTimeAgreement and trace.atOrBeforeReportedTOI then association.label="CONTACT_CANDIDATE"
            else association.label="UNQUALIFIED_CONTACT_DATA" end
        end
        result.supportAssociation=association
    end
    return result,unsupported
end

function Survey:_local_proxy(point,shape)
    local proxy=self:_proxy(shape)
    if not proxy then return self:_stop("survey-proxy-limit") end
    self.result.bodyProxy=util.deep_copy(proxy)
    local policy,reason=self:_physical_policy(shape)
    if not policy then self.result.classification="unsupported"; return self:_stop(reason) end
    self.result.physicalPolicy=policy
    local source=self:_call("source-enabled",shape.capsule,"GetCollisionEnabled")
    if source~=1 and source~=3 then return self:_stop("source-response-unqualified") end
    local source_type=channel(self:_call("source-type",shape.capsule,"GetCollisionObjectType"))
    self.sourceCollision={enabled=source,objectType=source_type,profileName=self.native:collision_profile(shape.capsule),responses={}}
    for to=0,31 do self.sourceCollision.responses[to+1]=self:_response(shape.capsule,to) end
    self.effectiveSourceCollision,self.result.collisionPolicy=self.native:placement_collision_model(self.sourceCollision)
    policy.rootCollision=util.deep_copy(self.sourceCollision)
    policy.expectedRootCollision=util.deep_copy(self.effectiveSourceCollision)
    local queries,center={},vector(point)
    for index=0,31 do queries[index+1]=index end
    local roots
    roots,reason=self:_query("CapsuleOverlapComponents","rootCapsule",point,shape.radius,shape.halfHeight,queries,nil,{})
    if not roots then return self:_stop(reason) end
    local root_reason,proxy_reason
    local association=self:_support_association(point,shape)
    self.result.rootClearance,root_reason=self:_classify_contacts(roots,true,association)
    center.Z=center.Z+proxy.centerOffsetZ
    local components
    components,reason=self:_query("CapsuleOverlapComponents","waterProxy",center,proxy.radius,proxy.halfHeight,queries,nil,{})
    if not components then return self:_stop(reason) end
    self.result.waterProxy,proxy_reason=self:_classify_contacts(components,false)
    self.result.waterContacts=self.result.rootClearance.waterContacts+self.result.waterProxy.waterContacts
    self.result.mutualBlockers=self.result.rootClearance.mutualBlockers
    self.result.unqualifiedBodies=self.result.rootClearance.unqualifiedBodies+self.result.waterProxy.unqualifiedBodies
    self.result.classification=self.result.waterContacts>0 and "wet" or self.result.mutualBlockers>0 and "blocked"
        or self.result.unqualifiedBodies>0 and "unsupported" or "proxy-clear"
    if root_reason or proxy_reason then return self:_stop(root_reason or proxy_reason) end
    self.result.complete=true
    self.result.code="local-proxy-observed"
    return self.result
end

function Survey:local_proxy(point,shape)
    if self.used then error(ERROR,0) end
    self.used=true
    self.result.localOnly=true
    if not self.a.valid(self.world) or not self.world:IsA("/Script/Engine.World") then error(ERROR,0) end
    self:_qualify_local()
    self.waterChannel=channel(self:_call("water-channel",self.native.utility,"GetEngineCollisionChannelByPalTraceType",4))
    return self:_local_proxy(point,shape)
end

function Survey:run()
    if self.used then error(ERROR,0) end
    self.used=true
    self:_qualify()
    local shape,shape_reason=self.native:_placement_shape("BOSS_Hunter_Rifle")
    self.result.bodyProxy=shape and shape.bodyProxy and util.deep_copy(shape.bodyProxy)
    self.result.bodyProxyReason=shape_reason or (shape and shape.bodyProxyReason)
    local ready,reason=self:_environment()
    if not ready then return self:_stop(reason) end
    if not shape or not shape.bodyProxy then return self:_stop(self.result.bodyProxyReason or "body-proxy-unavailable") end
    local candidate=self.requestedPoint or self.scope.positions[1] or self.scope.origin
    local point=self.native:startup_floor(self.world,candidate,"BOSS_Hunter_Rifle")
    if not point and not self.requestedPoint then point=self.native:startup_floor(self.world,self.scope.origin,"BOSS_Hunter_Rifle") end
    if not point then return self:_stop("survey-floor-unavailable") end
    if self.requestedPoint then
        for _,key in ipairs({"X","Y","Z"}) do
            if math.abs(point[key]-self.requestedPoint[key])>0.1 then return self:_stop("survey-floor-moved") end
        end
    end
    local proxy=self:_proxy(shape)
    if not proxy then return self:_stop("survey-proxy-limit") end
    local policy,policy_reason=self:_physical_policy(shape)
    if not policy then self.result.classification="unsupported"; return self:_stop(policy_reason) end
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
        local kind,water,bounds=self:_water(component,info.owner)
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
    self:_local_proxy(point,shape)
    if not self.result.complete then return self.result end
    if self.result.footAboveWaterCm<=10 then self.result.classification="wet" end
    self.result.code="proxy-survey-observed"
    -- Private, same-call inputs for the one-instance experiment; never serialized as a spawn certificate.
    self.point,self.shape=vector(point),shape
    return self.result
end

return Survey
