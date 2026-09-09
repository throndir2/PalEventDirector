local util = require("ped.util")
local bounties = require("ped.bounties")
local Survey = require("ped.surface_survey")

local Shape = {}
Shape.__index = Shape
Shape.CASE = "shape-qualification"
Shape.CONTRACT = "hunter-level30-one-instance-v1"
Shape.PREMISE = "Authored proxies are the controlled test envelope, not a universal final-shape or dry-placement certificate."

local ERROR = "Custom assault scope is invalid"
local CHARACTER = "BOSS_Hunter_Rifle"
local AXES = {"X","Y","Z"}

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

local function vector(value,keys)
    if value==nil then return nil end
    local copy={}
    for _,key in ipairs(keys or AXES) do
        if not finite(value[key]) then return nil end
        copy[key]=value[key]
    end
    return copy
end

local function distance(a,b)
    return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)
end

local function close(a,b,tolerance)
    return finite(a) and finite(b) and math.abs(a-b)<=tolerance
end

local function same_vector(a,b,tolerance,keys)
    if not a or not b then return false end
    for _,key in ipairs(keys or AXES) do
        if not close(a[key],b[key],tolerance) then return false end
    end
    return true
end

local function dimensions(radius,half)
    return finite(radius) and finite(half) and radius>0 and radius<=500 and half>=radius and half<=1000
end

function Shape.new(native,runner,scope,member)
    local state=runner.state
    local self=setmetatable({native=native,a=native.a,runner=runner,scope=scope,member=member,
        runId=state.runId,artifact=state.artifactSha256,source=state.sourceRevision,
        base=scope.base,world=scope.world,baseId=scope.baseId,guildId=scope.guildId,
        origin=vector(scope.origin),range=scope.range,leashRadius=scope.leashRadius},Shape)
    self:_validate(scope,member,true)
    return self
end

function Shape:_validate(scope,member,spawning)
    local n,runner=self.native,self.runner
    local state=runner.state
    if n.bridge.startup_test~=runner or runner.engine~=n or runner.stopped or state.status~="running"
        or state.case~=Shape.CASE or state.experiment~=Shape.CONTRACT
        or state.runId~=self.runId or state.artifactSha256~=self.artifact or state.sourceRevision~=self.source
        or n.bridge.delivery_profile~="laboratory-native-test" or n.bridge.config.mode~="laboratory"
        or n.bridge.config.capabilities.startAllInvasions~=true
        or os.getenv("COMPUTERNAME")~="IMOUTO" or os.getenv("PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN")~=self.runId
        or os.getenv("PAL_EVENT_DIRECTOR_SOURCE_REVISION")~=self.source
        or os.getenv("PAL_EVENT_DIRECTOR_ARTIFACT_SHA256")~=self.artifact
        or os.getenv("PAL_EVENT_DIRECTOR_SERVER_BUILD_ID")~="25080279"
        or os.getenv("PAL_EVENT_DIRECTOR_UE4SS_TAG")~="2281fa31"
        or os.getenv("PAL_EVENT_DIRECTOR_UE4SS_API_VERSION")~="3.0.1"
        or scope~=self.scope or scope.base~=self.base or scope.world~=self.world
        or scope.baseId~=self.baseId or scope.guildId~=self.guildId
        or scope.range~=self.range or scope.leashRadius~=self.leashRadius
        or not same_vector(scope.origin,self.origin,0) or #runner.scopes~=1 or runner.scopes[1]~=scope
        or #state.members~=1 or state.members[1]~=self.member
        or member.index~=1 or member.slot~=1 or member.baseId~=self.baseId
        or member.groupId~="startup:"..self.runId or member.characterId~=CHARACTER or member.level~=30
        or self.member.characterId~=CHARACTER or self.member.level~=30
        or self.member.groupId~=member.groupId or self.member.slot~=member.slot or self.member.index~=member.index
        or state.moved~=0 or state.helpersCreated~=1 or state.helpersCleaned~=0
        or not runner.support or runner.support.native~=n or not state.helpers[1]
        or state.helpers[1].phase~="configured" or state.helpers[1].cleanupRequested then error(ERROR,0) end
    if spawning and (state.stage~="spawn" or member~=self.member or state.spawned~=0 or state.initialized~=0
        or member.cleanupRequested or member.instanceGuid) then error(ERROR,0) end
end

function Shape:_field(object,name)
    if self.a.property then return self.a.property(object,name) end
    if object==nil then return nil end
    return self.a.unwrap(object[name])
end

function Shape:_call(label,object,method,...)
    return self.native:_call("shape-"..label,object,method,...)
end

function Shape:_qualify()
    for _,method in ipairs({"K2_GetComponentLocation","K2_GetComponentRotation","K2_GetComponentScale"}) do
        local fields=self.native:_signature("/Script/Engine.SceneComponent:"..method,{ReturnValue={"StructProperty",0}})
        local rotation=method=="K2_GetComponentRotation"
        self.native:_struct(fields.ReturnValue.field,rotation and "Rotator" or "Vector",rotation and {
            Pitch={"DoubleProperty",0},Yaw={"DoubleProperty",8},Roll={"DoubleProperty",16},
        } or {X={"DoubleProperty",0},Y={"DoubleProperty",8},Z={"DoubleProperty",16}})
    end
    self.native:_signature("/Script/Pal.PalCharacterParameterComponent:GetCapsuleRadius",{ReturnValue={"FloatProperty",0}})
    self.native:_signature("/Script/Engine.PrimitiveComponent:GetCollisionEnabled",{ReturnValue={"ByteProperty",0}})
    self.native:_signature("/Script/Engine.PrimitiveComponent:GetCollisionObjectType",{ReturnValue={"ByteProperty",0}})
    self.native:_signature("/Script/Engine.PrimitiveComponent:GetCollisionResponseToChannel",{
        Channel={"ByteProperty",0},ReturnValue={"ByteProperty",1}})
end

function Shape:_collision(component)
    local result={enabled=self:_call("collision-enabled",component,"GetCollisionEnabled"),
        objectType=self:_call("collision-type",component,"GetCollisionObjectType"),responses={}}
    if not util.is_integer(result.enabled) or result.enabled<0 or result.enabled>3
        or not util.is_integer(result.objectType) or result.objectType<0 or result.objectType>31 then return nil end
    for channel=0,31 do
        local response=self:_call("collision-response",component,"GetCollisionResponseToChannel",channel)
        if not util.is_integer(response) or response<0 or response>2 then return nil end
        result.responses[channel+1]=response
    end
    return result
end

function Shape:_geometry(actor,actual)
    if not self.a.valid(actor) or not actor:IsA(bounties.pawn_class(CHARACTER)) then return nil,"actor-class" end
    local capsule=self:_field(actor,"CapsuleComponent")
    local mesh=self:_field(actor,"Mesh")
    local static=self:_field(actor,"StaticCharacterParameterComponent")
    local movement=self:_field(actor,"CharacterMovement")
    for _,pair in ipairs({{capsule,"/Script/Engine.CapsuleComponent"},{mesh,"/Script/Engine.SkeletalMeshComponent"},
        {static,"/Script/Pal.PalStaticCharacterParameterComponent"},
        {movement,actual and "/Script/Pal.PalCharacterMovementComponent" or "/Script/Engine.CharacterMovementComponent"}}) do
        if not self.a.valid(pair[1]) or not pair[1]:IsA(pair[2]) then return nil,"component-class" end
        if not self.a.same(self:_call("component-owner",pair[1],"GetOwner"),actor) then return nil,"component-owner" end
        if actual and not self.a.same(self:_call("component-world",pair[1],"GetWorld"),self.world) then
            return nil,"component-world"
        end
    end
    if not self.a.same(self:_call("root",actor,"K2_GetRootComponent"),capsule)
        or not self.a.same(self:_call("movement",actor,"GetMovementComponent"),movement)
        or self.a.valid(self:_field(capsule,"AttachParent"))
        or not self.a.same(self:_field(mesh,"AttachParent"),capsule) then return nil,"component-attachment" end
    local result={root={},mesh={},body={},nav={}}
    for _,pair in ipairs({{capsule,result.root},{mesh,result.mesh}}) do
        local component,out=pair[1],pair[2]
        out.relativeLocation=vector(self:_field(component,"RelativeLocation"))
        out.relativeScale=vector(self:_field(component,"RelativeScale3D"))
        out.relativeRotation=vector(self:_field(component,"RelativeRotation"),{"Pitch","Yaw","Roll"})
        if not out.relativeLocation or not out.relativeScale or not out.relativeRotation then return nil,"component-transform",result end
        out.collision=self:_collision(component)
        if not out.collision then return nil,"component-collision",result end
        if actual then
            out.worldScale=vector(self:_call("world-scale",component,"K2_GetComponentScale"))
            out.worldLocation=vector(self:_call("world-location",component,"K2_GetComponentLocation"))
            out.worldRotation=vector(self:_call("world-rotation",component,"K2_GetComponentRotation"),{"Pitch","Yaw","Roll"})
            if not out.worldScale or not out.worldLocation or not out.worldRotation then return nil,"component-world-transform",result end
        end
    end
    result.root.radius,result.root.halfHeight=self:_field(capsule,"CapsuleRadius"),self:_field(capsule,"CapsuleHalfHeight")
    result.root.scaledRadius=self:_call("scaled-radius",capsule,"GetScaledCapsuleRadius")
    result.root.scaledHalfHeight=self:_call("scaled-half-height",capsule,"GetScaledCapsuleHalfHeight")
    result.body.radius,result.body.halfHeight=self:_field(static,"MeshCapsuleRadius"),self:_field(static,"MeshCapsuleHalfHeight")
    result.body.authoredOffset=vector(self:_field(static,"MeshRelativeLocation"))
    for _,part in ipairs({"root","body"}) do
        for _,field in ipairs({"radius","halfHeight","scaledRadius","scaledHalfHeight"}) do
            if not finite(result[part][field]) then result[part][field]=nil end
        end
    end
    if not dimensions(result.root.radius,result.root.halfHeight) or not dimensions(result.root.scaledRadius,result.root.scaledHalfHeight)
        or not dimensions(result.body.radius,result.body.halfHeight) or not result.body.authoredOffset then return nil,"component-dimensions",result end
    local agent=self:_field(movement,"NavAgentProps")
    for _,pair in ipairs({{"radius","AgentRadius"},{"height","AgentHeight"},{"stepHeight","AgentStepHeight"}}) do
        result.nav[pair[1]]=self:_field(agent,pair[2])
        if not finite(result.nav[pair[1]]) then
            result.nav[pair[1]]=nil
            return nil,"nav-agent-properties",result
        end
    end
    result.nav.updateFromCollision=self:_field(movement,"bUpdateNavAgentWithOwnersCollision")
    result.nav.walkableZ=self:_field(movement,"WalkableFloorZ")
    if type(result.nav.updateFromCollision)~="boolean" or not finite(result.nav.walkableZ) then
        result.nav.updateFromCollision,result.nav.walkableZ=nil,nil
        return nil,"nav-agent-properties",result
    end
    result.updatedRoot=self.a.same(self:_field(movement,"UpdatedComponent"),capsule)
    return result,movement
end

local function same_collision(a,b)
    if not a or not b or a.enabled~=b.enabled or a.objectType~=b.objectType or #a.responses~=32 or #b.responses~=32 then return false end
    for index=1,32 do if a.responses[index]~=b.responses[index] then return false end end
    return true
end

function Shape:prepare()
    self:_validate(self.scope,self.member,true)
    if self.attempted then error(ERROR,0) end
    if not self.layoutsQualified then self:_qualify(); self.layoutsQualified=true end
    local function blocked(reason,survey)
        return {ready=false,pending=false,reason=reason,mode="in-base",attempts=1,
            experiment=Shape.CONTRACT,premise=Shape.PREMISE,spawnQualified=false,surfaceSurvey=survey}
    end
    local ok,residency=self.runner.support:poll(1)
    if not ok then error(residency,0) end
    if not residency.ready or not residency.enabled or not residency.streamingComplete then
        local pending=blocked("shape-residency-pending")
        pending.pending,pending.residency=true,residency
        return pending
    end
    self.attempted=true
    local n,scope,member=self.native,self.scope,self.member
    local candidate=scope.positions[1] or scope.origin
    local floor=n:startup_floor(scope.world,candidate,CHARACTER)
    if not floor and candidate~=scope.origin then floor=n:startup_floor(scope.world,scope.origin,CHARACTER) end
    if not floor then return blocked("shape-floor-unavailable") end
    local nav,goal=n:startup_nav(scope.world,floor),n:startup_nav(scope.world,scope.origin)
    if not nav or not goal then return blocked("shape-navigation-unavailable") end
    local point=n:startup_floor(scope.world,nav,CHARACTER)
    if not point then return blocked("shape-projected-floor-unavailable") end
    local shape,reason=n:_placement_shape(CHARACTER)
    if not shape or not shape.bodyProxy then return blocked(reason or (shape and shape.bodyProxyReason) or "shape-template-unavailable") end
    local proxy=shape.bodyProxy
    local envelope=proxy.halfHeight+math.abs(proxy.centerOffsetZ)
    if scope.range<=envelope or distance(point,scope.origin)>math.min(scope.range,9000)-envelope
        or math.abs(point.Z-scope.origin.Z)+envelope>500 then return blocked("shape-outside-base-envelope") end
    local support=n:_placement_support(scope,member,point)
    if not support.ready then return blocked(support.reason) end
    local path_scope=util.shallow_copy(scope)
    path_scope.leashRadius=math.min(scope.leashRadius,scope.range,9000)-envelope
    local route=n:_placement_path(path_scope,member,point,goal)
    if not route.ready then return blocked(route.reason) end
    shape,reason=n:_placement_shape(CHARACTER)
    if not shape then return blocked(reason or "shape-template-unavailable") end
    local planned,why=self:_geometry(shape.cdo,false)
    if not planned then return blocked("shape-template-"..why) end
    local unit,zero={X=1,Y=1,Z=1},{X=0,Y=0,Z=0}
    if not same_vector(planned.root.relativeScale,unit,0.001) or not same_vector(planned.mesh.relativeScale,unit,0.001)
        or not same_vector(planned.root.relativeLocation,zero,0.001)
        or not close(planned.root.radius,planned.root.scaledRadius,0.001)
        or not close(planned.root.halfHeight,planned.root.scaledHalfHeight,0.001)
        or not close(planned.mesh.relativeLocation.X,0,0.001) or not close(planned.mesh.relativeLocation.Y,0,0.001)
        or not close(planned.mesh.relativeRotation.Pitch,0,0.1) or not close(planned.mesh.relativeRotation.Roll,0,0.1) then
        return blocked("shape-template-transform")
    end
    local survey=Survey.new(n,scope,{point=point})
    local result=survey:run()
    if result.complete and result.classification~="proxy-clear" then
        return blocked("shape-survey-"..(result.classification or "unsupported"),result)
    end
    if not result.complete or result.spawnQualified~=false or result.templateOnly~=true
        or not survey.point or not same_vector(survey.point,point,0.1) or not survey.shape then
        return blocked("shape-"..(result.code or "survey-unavailable"),result)
    end
    if not same_vector(survey.shape.bodyProxy,proxy,0.001,{"radius","halfHeight","centerOffsetZ","lowerFootOffsetZ"}) then
        return blocked("shape-template-changed",result)
    end
    if not same_collision(planned.root.collision,survey.sourceCollision)
        or not close(planned.root.scaledRadius,survey.shape.radius,0.001)
        or not close(planned.root.scaledHalfHeight,survey.shape.halfHeight,0.001)
        or not close(planned.body.radius,proxy.bodyRadius,0.001)
        or not close(planned.body.halfHeight,proxy.bodyHalfHeight,0.001)
        or not close(planned.mesh.relativeLocation.Z,proxy.meshOffsetZ,0.001)
        or not close(planned.body.authoredOffset.Z,proxy.authoredOffsetZ,0.001) then
        return blocked("shape-template-changed",result)
    end
    self.point,self.goal,self.planned=vector(point),vector(goal),planned
    self.proxy=util.deep_copy(proxy)
    self.preparedAt=n.bridge.clock()
    if not finite(self.preparedAt) then error(ERROR,0) end
    return {ready=true,pending=false,mode="in-base",attempts=1,position=vector(point),goal=vector(goal),
        experiment=Shape.CONTRACT,premise=Shape.PREMISE,spawnQualified=false,surfaceSurvey=result,
        plannedGeometry=util.deep_copy(planned),pathPoints=route.pathPoints,pathLength=route.pathLength,
        defaultNavDataUsed=route.defaultNavDataUsed,templateOnly=true}
end

function Shape:consume(scope,member,placement)
    if self.consumed then error(ERROR,0) end
    self.consumed=true
    self:_validate(scope,member,true)
    local now=self.native.bridge.clock()
    if not self.preparedAt or not finite(now) or now<self.preparedAt or now>self.preparedAt+2
        or member.spawnRequested~=true or member.phase~="requested"
        or placement.shapeQualification~=self or not same_vector(placement.position,self.point,0)
        or not same_vector(placement.goal,self.goal,0) then error(ERROR,0) end
end

function Shape:validate_observation(scope,member)
    self:_validate(scope,member,false)
    if not self.consumed or self.runner.state.stage~="shape-observe" or self.runner.state.spawned~=1
        or not member.instanceGuid or not member.playerGuid then error(ERROR,0) end
end

function Shape.reconcile(planned,actual)
    local differences={}
    local function check(ok,field) if not ok then differences[#differences+1]=field end end
    for _,field in ipairs({"radius","halfHeight","scaledRadius","scaledHalfHeight"}) do
        check(close(planned.root[field],actual.root[field],0.1),"root-"..field)
    end
    for _,part in ipairs({"root","mesh"}) do
        check(same_vector(planned[part].relativeScale,actual[part].relativeScale,0.001),part.."-relative-scale")
        local world_scale={}
        for _,key in ipairs(AXES) do
            world_scale[key]=planned.root.relativeScale[key]*(part=="mesh" and planned.mesh.relativeScale[key] or 1)
        end
        check(same_vector(world_scale,actual[part].worldScale,0.001),part.."-world-scale")
        check(same_collision(planned[part].collision,actual[part].collision),part.."-collision")
    end
    check(same_vector(planned.mesh.relativeLocation,actual.mesh.relativeLocation,0.1),"mesh-relative-location")
    check(same_vector(planned.mesh.relativeRotation,actual.mesh.relativeRotation,0.1,{"Pitch","Yaw","Roll"}),"mesh-relative-rotation")
    for _,field in ipairs({"radius","halfHeight"}) do check(close(planned.body[field],actual.body[field],0.1),"body-"..field) end
    check(same_vector(planned.body.authoredOffset,actual.body.authoredOffset,0.1),"body-authored-offset")
    for _,field in ipairs({"radius","height","stepHeight"}) do
        check(close(planned.nav[field],actual.nav[field],0.1),"nav-"..field)
    end
    check(close(planned.nav.walkableZ,actual.nav.walkableZ,0.001),"nav-walkableZ")
    check(planned.nav.updateFromCollision==actual.nav.updateFromCollision,"nav-update-from-collision")
    check(actual.updatedRoot==true,"movement-updated-root")
    check(close(actual.root.worldRotation.Pitch,0,0.1) and close(actual.root.worldRotation.Roll,0,0.1),"root-upright")
    check(same_vector(actual.root.relativeLocation,actual.root.worldLocation,0.1),"root-relative-world")
    check(same_vector(actual.root.worldLocation,actual.actorLocation,0.1),"root-actor-location")
    check(actual.displacementCm<=5,"spawn-displacement")
    check(close(actual.parameterRadius,planned.body.radius,0.1),"initialized-parameter-radius")
    check(actual.movement.grounded and not actual.movement.falling and not actual.movement.flying,"grounded")
    check(actual.water.enteredFlag==0 and actual.water.inWaterRate==0,"actual-water-cache")
    if #differences>0 then return "MISMATCH",differences end
    if actual.currentActionPresent then return "UNSUPPORTED",{"stock-action-present"} end
    return "MATCH",differences
end

function Shape:observe(state)
    local result={comparison="UNSUPPORTED",phase=state.phase,instanceOnly=true,spawnQualified=false,
        premise=Shape.PREMISE,experiment=Shape.CONTRACT}
    if state.phase~="alive" then result.reasons={"member-"..state.phase}; return result end
    local actual,movement,partial=self:_geometry(state.actor,true)
    if not actual then result.actual=partial; result.reasons={movement}; return result end
    result.actual=actual
    actual.actorLocation=vector(state.location)
    if not actual.actorLocation then result.reasons={"actor-location"}; return result end
    actual.displacementCm=distance(actual.actorLocation,self.point)
    actual.movement=self.native:_movement_observation(state)
    local entered,rate,plane=self:_field(movement,"EnteredWaterFlag"),self:_field(movement,"InWaterRate"),self:_field(movement,"WaterPlaneZ")
    actual.water={cachedInstanceObservation=true}
    if not util.is_integer(entered) or entered<0 or entered>255 or not finite(rate) or not finite(plane) then
        result.reasons={"instance-water-cache-unreadable"}; return result
    end
    actual.water.enteredFlag,actual.water.inWaterRate,actual.water.planeZ=entered,rate,plane
    if not self.a.valid(state.component) or not state.component:IsA("/Script/Pal.PalCharacterParameterComponent")
        or not self.a.same(self:_call("parameter-owner",state.component,"GetOwner"),state.actor) then
        result.reasons={"initialized-parameter-owner"}; return result
    end
    actual.parameterRadius=self:_call("parameter-radius",state.component,"GetCapsuleRadius")
    if not finite(actual.parameterRadius) then actual.parameterRadius=nil; result.reasons={"initialized-parameter-radius"}; return result end
    local actions=self:_call("ai-component",state.controller,"GetAIActionComponent")
    if not self.a.valid(actions) then result.reasons={"ai-observation-unavailable"}; return result end
    actual.currentActionPresent=self.a.valid(self:_call("current-action",actions,"GetCurrentAction_BP"))
    result.comparison,result.reasons=Shape.reconcile(self.planned,actual)
    result.proxy=util.deep_copy(self.proxy)
    local unit={X=1,Y=1,Z=1}
    if same_vector(actual.root.worldScale,unit,0.001) and same_vector(actual.mesh.worldScale,unit,0.001)
        and close(actual.root.worldRotation.Pitch,0,0.1) and close(actual.root.worldRotation.Roll,0,0.1)
        and close(actual.mesh.relativeRotation.Pitch,0,0.1) and close(actual.mesh.relativeRotation.Roll,0,0.1)
        and close(actual.mesh.relativeLocation.X,0,0.1) and close(actual.mesh.relativeLocation.Y,0,0.1) then
        local root,body=actual.root,actual.body
        local center=actual.mesh.relativeLocation.Z+body.halfHeight
        local low=math.min(-root.scaledHalfHeight+root.scaledRadius,center-body.halfHeight+body.radius)
        local high=math.max(root.scaledHalfHeight-root.scaledRadius,center+body.halfHeight-body.radius)
        local radius=math.max(root.scaledRadius,body.radius)
        actual.measuredProxy={radius=radius,halfHeight=(high-low)/2+radius,centerOffsetZ=(low+high)/2,
            lowerFootOffsetZ=math.min(-root.scaledHalfHeight,actual.mesh.relativeLocation.Z),instanceMeasurementsOnly=true}
    end
    return result
end

return Shape
