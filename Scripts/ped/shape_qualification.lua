local util = require("ped.util")
local bounties = require("ped.bounties")
local Survey = require("ped.surface_survey")

local Shape = {}
Shape.__index = Shape
Shape.CASE = "shape-qualification"
Shape.CONTRACT = "hunter-level30-one-instance-v1"
Shape.ENGAGEMENT_CASE = "qualified-engagement"
Shape.ENGAGEMENT_CONTRACT = "hunter-level30-qualified-engagement-v1"
Shape.PREMISE = "Authored proxies are the controlled test envelope, not a universal final-shape or dry-placement certificate."
local CONTRACTS = {[Shape.CASE]=Shape.CONTRACT,[Shape.ENGAGEMENT_CASE]=Shape.ENGAGEMENT_CONTRACT}

function Shape.contract(case)
    return CONTRACTS[case]
end

local ERROR = "Custom assault scope is invalid"
local CHARACTER = "BOSS_Hunter_Rifle"
local AXES = {"X","Y","Z"}
local NO_CACHED_PLANE = 3.4028234663852886e38

local function float32(value)
    return (string.unpack("<f",string.pack("<f",value)))
end

local function floor_z(angle)
    return float32(math.cos(float32(float32(angle)*float32(math.pi/180))))
end

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

local function seen(points,position)
    for _,previous in ipairs(points) do if distance(previous,position)<=1 then return true end end
    return false
end

function Shape.new(native,runner,scope,member)
    local state=runner.state
    local self=setmetatable({native=native,a=native.a,runner=runner,scope=scope,member=member,
        case=state.case,contract=CONTRACTS[state.case],receipts={},
        baseOrdinal=state.baseOrdinal,
        runId=state.runId,artifact=state.artifactSha256,source=state.sourceRevision,
        base=scope.base,world=scope.world,baseId=scope.baseId,guildId=scope.guildId,
        origin=vector(scope.origin),range=scope.range,leashRadius=scope.leashRadius,
        allowFallback=native.bridge.config.customAssault.allowInBaseFallback,
        visited={candidates={},floors={},navigation={},sites={}},rejections={},duplicates=0},Shape)
    self:_validate(scope,member,true)
    self.search=native:_new_placement_search(scope,member)
    return self
end

function Shape:_validate(scope,member,spawning)
    local n,runner=self.native,self.runner
    local state=runner.state
    if n.bridge.startup_test~=runner or runner.engine~=n or runner.stopped or state.status~="running"
        or not self.contract or state.case~=self.case or state.experiment~=self.contract
        or state.runId~=self.runId or state.artifactSha256~=self.artifact or state.sourceRevision~=self.source
        or state.baseOrdinal~=self.baseOrdinal
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
        or n.bridge.config.customAssault.allowInBaseFallback~=self.allowFallback
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
    self.native:_signature("/Script/Engine.PrimitiveComponent:GetCollisionProfileName",{ReturnValue={"NameProperty",0}})
    self.native:_signature("/Script/Pal.PalUtility:GetEngineCollisionChannelByPalObjectType",{
        type={"EnumProperty",0},ReturnValue={"ByteProperty",1}})
    self.native:_signature("/Script/Pal.PalUtility:IsWildNPC",{Actor={"ObjectProperty",0},ReturnValue={"BoolProperty",8}})
    for _,method in ipairs({"GetWalkableFloorAngleByPriority","GetInWaterRate"}) do
        self.native:_signature("/Script/Pal.PalCharacterMovementComponent:"..method,{ReturnValue={"FloatProperty",0}})
    end
    self.native:_signature("/Script/Engine.PrimitiveComponent:GetCollisionResponseToChannel",{
        Channel={"ByteProperty",0},ReturnValue={"ByteProperty",1}})
end

function Shape:_collision(component)
    local result={enabled=self:_call("collision-enabled",component,"GetCollisionEnabled"),
        objectType=self:_call("collision-type",component,"GetCollisionObjectType"),
        profileName=self.native:collision_profile(component),responses={}}
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
    if actual and not self.a.same(movement:GetClass(),self.native:_class("/Script/Pal.PalCharacterMovementComponent")) then
        return nil,"movement-policy-class"
    end
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
    result.nav.walkableAngle=self:_field(movement,"WalkableFloorAngle")
    if type(result.nav.updateFromCollision)~="boolean" or not finite(result.nav.walkableZ) then
        result.nav.updateFromCollision,result.nav.walkableZ=nil,nil
        return nil,"nav-agent-properties",result
    end
    if not finite(result.nav.walkableAngle) then result.nav.walkableAngle=nil; return nil,"nav-angle-unreadable",result end
    local configured=self:_field(movement,"InWaterRate")
    if not finite(configured) or configured<0 or configured>1 then return nil,"water-configuration-unreadable",result end
    result.water={configuredImmersionTarget=configured}
    result.updatedRoot=self.a.same(self:_field(movement,"UpdatedComponent"),capsule)
    return result,movement
end

local function same_collision(a,b)
    if not a or not b or a.enabled~=b.enabled or a.objectType~=b.objectType or a.profileName~=b.profileName
        or #a.responses~=32 or #b.responses~=32 then return false end
    for index=1,32 do if a.responses[index]~=b.responses[index] then return false end end
    return true
end

function Shape:_candidate(position)
    local n,scope,member=self.native,self.scope,self.member
    local function rejected(reason) return {ready=false,reason=reason} end
    local function duplicate()
        self.duplicates=self.duplicates+1
        return rejected("shape-duplicate-site")
    end
    if seen(self.visited.candidates,position) or seen(self.visited.sites,position) then return duplicate() end
    self.visited.candidates[#self.visited.candidates+1]=vector(position)
    local floor=n:startup_floor(scope.world,position,CHARACTER)
    if not floor then return rejected("shape-floor-unavailable") end
    if seen(self.visited.floors,floor) or seen(self.visited.sites,floor) then return duplicate() end
    self.visited.floors[#self.visited.floors+1]=vector(floor)
    local nav=n:startup_nav(scope.world,floor)
    if not nav then return rejected("shape-navigation-unavailable") end
    if seen(self.visited.navigation,nav) then return duplicate() end
    self.visited.navigation[#self.visited.navigation+1]=vector(nav)
    local goal=n:startup_nav(scope.world,scope.origin)
    if not goal then return rejected("shape-navigation-unavailable") end
    local point=n:startup_floor(scope.world,nav,CHARACTER)
    if not point then return rejected("shape-projected-floor-unavailable") end
    if seen(self.visited.sites,point) then return duplicate() end
    self.visited.sites[#self.visited.sites+1]=vector(point)
    local shape,reason=n:_placement_shape(CHARACTER)
    if not shape or not shape.bodyProxy then return rejected(reason or (shape and shape.bodyProxyReason) or "shape-template-unavailable") end
    local proxy=shape.bodyProxy
    local envelope=proxy.halfHeight+math.abs(proxy.centerOffsetZ)
    if scope.range<=envelope or distance(point,scope.origin)>math.min(scope.range,9000)-envelope
        or math.abs(point.Z-scope.origin.Z)+envelope>500 then return rejected("shape-outside-base-envelope") end
    local support=n:_placement_support(scope,member,point)
    if not support.ready then return support end
    local path_scope=util.shallow_copy(scope)
    path_scope.leashRadius=math.min(scope.leashRadius,scope.range,9000)-envelope
    local route=n:_placement_path(path_scope,member,point,goal)
    if not route.ready then return {ready=false,reason=route.reason,support=support.support} end
    if self:_expired() then return rejected("spawn-placement-timeout") end
    shape,reason=n:_placement_shape(CHARACTER)
    if not shape or not same_vector(shape.bodyProxy,proxy,0.001,{"radius","halfHeight","centerOffsetZ","lowerFootOffsetZ"}) then
        return rejected(reason or "shape-template-changed")
    end
    local local_probe=Survey.new(n,scope,{point=point})
    local clearance=local_probe:local_proxy(point,shape)
    if type(clearance)~="table" or clearance.spawnQualified~=false or clearance.templateOnly~=true
        or clearance.localOnly~=true or type(clearance.complete)~="boolean" then error(ERROR,0) end
    if not clearance.complete or clearance.classification~="proxy-clear" then
        return {ready=false,reason="shape-local-proxy-"..(clearance.complete and clearance.classification or clearance.code or "unavailable"),
            support=support.support,localProxy=clearance}
    end
    return {ready=true,position=vector(point),goal=vector(goal),proxy=util.deep_copy(proxy),localProxy=clearance,
        pathPoints=route.pathPoints,pathLength=route.pathLength,defaultNavDataUsed=route.defaultNavDataUsed}
end

function Shape:_selection()
    return {candidateLimit=#self.search.candidates,candidatesVisited=self.search.attempts,
        uniqueCandidates=#self.visited.candidates,projectedSites=#self.visited.sites,duplicates=self.duplicates,
        rejections=util.deep_copy(self.rejections),selectedCandidate=self.selectedCandidate,selectedMode=self.selectedMode,
        selectedLocalProxy=util.deep_copy(self.selectedLocalProxy)}
end

function Shape:_expired()
    local now=self.native.bridge.clock()
    if not finite(now) or now<self.preparationStartedAt then error(ERROR,0) end
    return now>=self.preparationStartedAt+120
end

function Shape:prepare(scope,member)
    self:_validate(scope,member,true)
    if self.attempted or self.selectionClosed then error(ERROR,0) end
    self.preparationStartedAt=self.preparationStartedAt or self.native.bridge.clock()
    local function blocked(reason,survey)
        return {ready=false,pending=false,reason=reason,mode="in-base",attempts=self.search.attempts,
            fallbackReason=self.search.fallbackReason,selection=self:_selection(),
            experiment=self.contract,premise=Shape.PREMISE,spawnQualified=false,surfaceSurvey=survey}
    end
    if self:_expired() then self.selectionClosed=true; return blocked("spawn-placement-timeout") end
    if not self.layoutsQualified then self:_qualify(); self.layoutsQualified=true end
    local ok,residency=self.runner.support:residency(1)
    if not ok then error(residency,0) end
    if self:_expired() then self.selectionClosed=true; return blocked("spawn-placement-timeout") end
    if not residency.enabled or not residency.streamingComplete then
        local pending=blocked("shape-residency-pending")
        pending.pending,pending.residency=true,residency
        return pending
    end
    local site=self.search:poll(function(position,mode)
        local result=self:_expired() and {ready=false,reason="spawn-placement-timeout"} or self:_candidate(position)
        if not result.ready then
            self.rejections[#self.rejections+1]={candidate=self.search.attempts,mode=mode,reason=result.reason,
                support=util.deep_copy(result.support),localProxy=util.deep_copy(result.localProxy)}
        end
        return result
    end,2)
    if self:_expired() then self.selectionClosed=true; return blocked("spawn-placement-timeout") end
    if not site.ready then
        local result=blocked(site.pending and "shape-site-search-pending" or "shape-sites-exhausted")
        result.pending=site.pending==true
        if not result.pending then self.selectionClosed=true end
        return result
    end
    self.selectedCandidate,self.selectedMode=site.attempts,site.mode
    self.selectedLocalProxy=site.localProxy
    self.attempted=true
    local n,point,goal,proxy=self.native,site.position,site.goal,site.proxy
    local shape,reason=n:_placement_shape(CHARACTER)
    if not shape then return blocked(reason or "shape-template-unavailable") end
    local planned,why=self:_geometry(shape.cdo,false)
    if not planned then return blocked("shape-template-"..why) end
    if planned.root.collision.profileName=="pawn_nodamageflypal" or planned.root.collision.profileName=="pawnparts_nonblock" then
        return blocked("shape-template-profile-excluded")
    end
    local collision_model,collision_policy=n:placement_collision_model(planned.root.collision)
    planned.initialization={placementCollisionPolicy=collision_policy,placementRootCollision=collision_model}
    local unit,zero={X=1,Y=1,Z=1},{X=0,Y=0,Z=0}
    if not same_vector(planned.root.relativeScale,unit,0.001) or not same_vector(planned.mesh.relativeScale,unit,0.001)
        or not same_vector(planned.root.relativeLocation,zero,0.001)
        or not close(planned.root.radius,planned.root.scaledRadius,0.001)
        or not close(planned.root.halfHeight,planned.root.scaledHalfHeight,0.001)
        or not close(planned.mesh.relativeLocation.X,0,0.001) or not close(planned.mesh.relativeLocation.Y,0,0.001)
        or not close(planned.mesh.relativeRotation.Pitch,0,0.1) or not close(planned.mesh.relativeRotation.Roll,0,0.1) then
        return blocked("shape-template-transform")
    end
    if self:_expired() then return blocked("spawn-placement-timeout") end
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
        or not same_collision(collision_model,survey.effectiveSourceCollision)
        or not result.collisionPolicy or result.collisionPolicy.playerPawnChannel~=collision_policy.playerPawnChannel
        or not self.selectedLocalProxy.collisionPolicy
        or self.selectedLocalProxy.collisionPolicy.playerPawnChannel~=collision_policy.playerPawnChannel
        or not close(planned.root.scaledRadius,survey.shape.radius,0.001)
        or not close(planned.root.scaledHalfHeight,survey.shape.halfHeight,0.001)
        or not close(planned.body.radius,proxy.bodyRadius,0.001)
        or not close(planned.body.halfHeight,proxy.bodyHalfHeight,0.001)
        or not close(planned.mesh.relativeLocation.Z,proxy.meshOffsetZ,0.001)
        or not close(planned.body.authoredOffset.Z,proxy.authoredOffsetZ,0.001) then
        return blocked("shape-template-changed",result)
    end
    self.point,self.goal,self.planned=vector(point),vector(goal),planned
    self.drySceneQualified=result.complete==true and result.columnOceanWitness==true
        and finite(result.footAboveWaterCm) and result.footAboveWaterCm>10
        and result.waterContacts==0 and result.mutualBlockers==0 and result.unqualifiedBodies==0
    if not self.drySceneQualified then return blocked("shape-water-evidence-unavailable",result) end
    self.proxy=util.deep_copy(proxy)
    self.preparedAt=n.bridge.clock()
    if not finite(self.preparedAt) then error(ERROR,0) end
    if self:_expired() then return blocked("spawn-placement-timeout",result) end
    return {ready=true,pending=false,mode="in-base",attempts=site.attempts,position=vector(point),goal=vector(goal),
        fallbackReason=site.fallbackReason,selection=self:_selection(),
        experiment=self.contract,premise=Shape.PREMISE,spawnQualified=false,surfaceSurvey=result,
        plannedGeometry=util.deep_copy(planned),pathPoints=site.pathPoints,pathLength=site.pathLength,
        defaultNavDataUsed=site.defaultNavDataUsed,templateOnly=true}
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

function Shape:revoke_engagement(reason)
    self.engagementRevoked=self.engagementRevoked or reason
    self.engagementPermit=nil
end

function Shape:stage_changed(stage)
    if #self.receipts==0 and not self.engagementArmAttempted then return end
    if stage=="engagement" and self.case==Shape.ENGAGEMENT_CASE
        and self.runner.state.stage=="shape-observe" and #self.receipts==2 and not self.engagementArmAttempted then return end
    self:revoke_engagement("stage-change")
end

function Shape:ownership_observed(state)
    if self.case==Shape.ENGAGEMENT_CASE and (#self.receipts>0 or self.engagementArmAttempted) and state.phase~="alive" then
        self:revoke_engagement("ownership-"..state.phase)
    end
end

function Shape:record_observation(record,state,result)
    if self.case~=Shape.ENGAGEMENT_CASE then return end
    if result.comparison~="MATCH" or state.phase~="alive" then
        self:revoke_engagement("shape-not-matched")
        return
    end
    local now=self.native.bridge.clock()
    local index=#self.receipts+1
    local start=self.runner.state.stageStartedAt
    if self.engagementRevoked or index>2 or not finite(now) or not finite(start) or now<start or now>start+10 then error(ERROR,0) end
    local previous=self.receipts[index-1]
    if previous and (now<previous.at+1 or not self.a.same(previous.actor,state.actor)
        or not self.a.same(previous.parameter,state.parameter) or not self.a.same(previous.controller,state.controller)
        or not self.a.same(previous.handle,record.handle) or previous.id~=record.id) then
        self:revoke_engagement("shape-receipt-identity")
        error(ERROR,0)
    end
    result.receipt={sample=index,runId=self.runId,case=self.case,experiment=self.contract,artifactSha256=self.artifact,
        memberIndex=1,actorAddress=self.a.address(state.actor),observedAt=now}
    self.receipts[index]={at=now,actor=state.actor,parameter=state.parameter,controller=state.controller,
        handle=record.handle,id=record.id,record=record,result=result}
end

function Shape:_engagement_receipts(record)
    local samples=self.runner.state.shapeObservations
    if #self.receipts~=2 or type(samples)~="table" or #samples~=2 then error(ERROR,0) end
    for index,receipt in ipairs(self.receipts) do
        if receipt.record~=record or receipt.id~=record.id or receipt.result~=samples[index]
            or receipt.result.comparison~="MATCH" or receipt.result.instanceOnly~=true or receipt.result.spawnQualified~=false
            or not self.a.same(receipt.actor,record.actor) or not self.a.same(receipt.parameter,record.parameter)
            or not self.a.same(receipt.handle,record.handle) then error(ERROR,0) end
    end
end

function Shape:begin_engagement(scope,member,record)
    self:_validate(scope,member,false)
    if self.case~=Shape.ENGAGEMENT_CASE or self.contract~=Shape.ENGAGEMENT_CONTRACT
        or self.engagementRevoked or self.engagementArmAttempted or not self.consumed
        or self.runner.state.stage~="engagement" or self.runner.state.spawned~=1 or self.runner.state.initialized~=1
        or member.cleanupRequested or self.member.cleanupRequested or record.despawnRequested then error(ERROR,0) end
    self.engagementArmAttempted=true
    self:_engagement_receipts(record)
    local now,start=self.native.bridge.clock(),self.runner.state.stageStartedAt
    if not finite(now) or not finite(start) or now<start or now>start+5
        or self.receipts[2].at>start or self.receipts[2].at<start-2 then error(ERROR,0) end
    return start
end

function Shape:finish_engagement(record,state,start)
    self:_validate(self.scope,self.member,false)
    local now=self.native.bridge.clock()
    if self.engagementRevoked or state.phase~="alive" or self.runner.state.stage~="engagement"
        or self.runner.state.stageStartedAt~=start or not finite(now) or now<start or now>start+5 then
        self:revoke_engagement("arm-ownership-unavailable")
        return {armed=false,reason="engagement-ownership-unavailable"}
    end
    for _,receipt in ipairs(self.receipts) do
        if not self.a.same(receipt.actor,state.actor) or not self.a.same(receipt.parameter,state.parameter)
            or not self.a.same(receipt.controller,state.controller) then error(ERROR,0) end
    end
    local authorization={armed=true,case=self.case,experiment=self.contract,runId=self.runId,artifactSha256=self.artifact,
        memberIndex=1,baseId=self.baseId,actorAddress=self.a.address(state.actor),samples=2,stageStartedAt=start,expiresAt=start+60}
    self.engagementPermit={record=record,stageStartedAt=start,expiresAt=start+60,authorization=authorization}
    return authorization
end

function Shape:validate_gameplay(scope,member,record,owned)
    self:_validate(scope,member,false)
    local permit=self.engagementPermit
    local state=self.runner.state
    local now=self.native.bridge.clock()
    if permit and permit.record==record and state.stage=="engagement" and state.stageStartedAt==permit.stageStartedAt
        and finite(now) and now>=permit.expiresAt then
        self:revoke_engagement("expired")
        return false
    end
    if self.case~=Shape.ENGAGEMENT_CASE or self.contract~=Shape.ENGAGEMENT_CONTRACT or self.engagementRevoked
        or not self.consumed or not self.engagementArmAttempted or self.native.bridge.native_fault
        or not permit or permit.record~=record or state.stage~="engagement"
        or state.qualifiedEngagementArmed~=true or state.engagementAuthorization~=permit.authorization
        or state.stageStartedAt~=permit.stageStartedAt or not finite(now) or now<permit.stageStartedAt or now>=permit.expiresAt
        or state.failure or state.spawned~=1 or state.initialized~=1
        or member.cleanupRequested or self.member.cleanupRequested or record.despawnRequested then
        self:revoke_engagement("gameplay-scope-ended")
        error(ERROR,0)
    end
    self:_engagement_receipts(record)
    if owned then
        for _,receipt in ipairs(self.receipts) do
            if not self.a.same(receipt.actor,owned.actor) or not self.a.same(receipt.parameter,owned.parameter)
                or not self.a.same(receipt.controller,owned.controller) then
                self:revoke_engagement("gameplay-owner-changed")
                error(ERROR,0)
            end
        end
    end
    return true
end

function Shape.reconcile(planned,actual)
    local policy=actual.initializationPolicy
    local original_profile=planned.root.collision.profileName
    if not policy or policy.isWildNPC~=true or policy.nativeNPC~=true or policy.rootProfileExcluded~=false
        or original_profile=="pawn_nodamageflypal" or original_profile=="pawnparts_nonblock" then
        return "UNSUPPORTED",{"wild-npc-response-policy-unqualified"}
    end
    if planned.nav.updateFromCollision~=true then return "UNSUPPORTED",{"custom-nav-agent-policy"} end
    if not finite(policy.selectedWalkableAngle) or policy.selectedWalkableAngle<0 or policy.selectedWalkableAngle>90 then
        return "UNSUPPORTED",{"selected-slope-policy-unavailable"}
    end
    if policy.drySceneQualified~=true then return "UNSUPPORTED",{"independent-dry-scene-unqualified"} end
    local expected_root=require("ped.custom_assault_native").player_pawn_collision_model(planned.root.collision,policy.playerPawnChannel)
    local expected_z=floor_z(policy.selectedWalkableAngle)
    local expected={
        nav={policy="collision-derived-initialization",templateRadius=planned.nav.radius,templateHeight=planned.nav.height,
            radius=actual.root.scaledRadius,height=2*actual.root.scaledHalfHeight,stepHeight=planned.nav.stepHeight},
        rootResponse={policy="eligible-wild-npc-player-pawn-block",palObjectSelector=2,playerPawnChannel=policy.playerPawnChannel,
            templateResponse=planned.root.collision.responses[policy.playerPawnChannel+1],expectedResponse=2,
            templateProfile=original_profile,expectedProfile=expected_root.profileName,
            profileBookkeeping=expected_root.profileName~=original_profile and "EXPECTED_PROFILE_CUSTOMIZATION" or "UNCHANGED"},
        slope={policy="active-priority-selected-angle",selectedAngleDegrees=policy.selectedWalkableAngle,
            templateFloorZ=planned.nav.walkableZ,expectedFloorZ=expected_z},
        water={configuredImmersionTarget=planned.water.configuredImmersionTarget,computedWhenNoEnteredFlags=0},
    }
    if actual.water.enteredFlag~=0 and not actual.water.cachedPlaneAvailable then
        return "UNSUPPORTED",{"entered-water-without-cached-plane"},expected
    end
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
        check(same_collision(part=="root" and expected_root or planned[part].collision,actual[part].collision),part.."-collision")
    end
    check(same_vector(planned.mesh.relativeLocation,actual.mesh.relativeLocation,0.1),"mesh-relative-location")
    check(same_vector(planned.mesh.relativeRotation,actual.mesh.relativeRotation,0.1,{"Pitch","Yaw","Roll"}),"mesh-relative-rotation")
    for _,field in ipairs({"radius","halfHeight"}) do check(close(planned.body[field],actual.body[field],0.1),"body-"..field) end
    check(same_vector(planned.body.authoredOffset,actual.body.authoredOffset,0.1),"body-authored-offset")
    check(actual.nav.radius>0 and close(expected.nav.radius,actual.nav.radius,0.01),"nav-radius-from-collision")
    check(actual.nav.height>0 and close(expected.nav.height,actual.nav.height,0.01),"nav-height-from-collision")
    check(close(planned.nav.stepHeight,actual.nav.stepHeight,0.001),"nav-stepHeight")
    check(close(policy.selectedWalkableAngle,actual.nav.walkableAngle,0.0001),"nav-selected-walkable-angle")
    check(close(expected_z,actual.nav.walkableZ,0.0000002),"nav-selected-walkableZ")
    check(planned.nav.updateFromCollision==actual.nav.updateFromCollision,"nav-update-from-collision")
    check(policy.playerPawnChannel==planned.initialization.placementCollisionPolicy.playerPawnChannel,"player-pawn-channel-mapping")
    check(actual.updatedRoot==true,"movement-updated-root")
    check(close(actual.root.worldRotation.Pitch,0,0.1) and close(actual.root.worldRotation.Roll,0,0.1),"root-upright")
    check(same_vector(actual.root.relativeLocation,actual.root.worldLocation,0.1),"root-relative-world")
    check(same_vector(actual.root.worldLocation,actual.actorLocation,0.1),"root-actor-location")
    check(actual.displacementCm<=5,"spawn-displacement")
    check(close(actual.parameterRadius,planned.body.radius,0.1),"initialized-parameter-radius")
    check(actual.movement.grounded and not actual.movement.falling and not actual.movement.flying,"grounded")
    check(close(planned.water.configuredImmersionTarget,actual.water.configuredImmersionTarget,0.000001),"configured-immersion-target")
    check(actual.water.enteredFlag==0 and actual.water.computedImmersionRate==0,"actual-water-state")
    if #differences>0 then return "MISMATCH",differences,expected end
    if actual.currentActionPresent then return "UNSUPPORTED",{"stock-action-present"},expected end
    return "MATCH",differences,expected
end

function Shape:observe(state)
    local result={comparison="UNSUPPORTED",phase=state.phase,instanceOnly=true,spawnQualified=false,
        premise=Shape.PREMISE,experiment=self.contract}
    if state.phase~="alive" then result.reasons={"member-"..state.phase}; return result end
    local actual,movement,partial=self:_geometry(state.actor,true)
    if not actual then result.actual=partial; result.reasons={movement}; return result end
    result.actual=actual
    actual.actorLocation=vector(state.location)
    if not actual.actorLocation then result.reasons={"actor-location"}; return result end
    actual.displacementCm=distance(actual.actorLocation,self.point)
    actual.movement=self.native:_movement_observation(state)
    if not self.a.same(self:_field(movement,"CharacterOwner"),state.actor) then
        result.reasons={"movement-character-owner"}; return result
    end
    local entered,plane=self:_field(movement,"EnteredWaterFlag"),self:_field(movement,"WaterPlaneZ")
    actual.water.cachedInstanceObservation=true
    if not util.is_integer(entered) or entered<0 or entered>255 or not finite(plane) then
        result.reasons={"instance-water-cache-unreadable"}; return result
    end
    actual.water.enteredFlag=entered
    actual.water.cachedPlaneAvailable=plane~=NO_CACHED_PLANE
    actual.water.cachedPlaneStatus=actual.water.cachedPlaneAvailable and "AVAILABLE" or "NO_CACHED_PLANE"
    if actual.water.cachedPlaneAvailable then actual.water.cachedPlaneZ=plane end
    local rate=self:_call("computed-immersion",movement,"GetInWaterRate")
    if not finite(rate) or rate<0 or rate>1 then result.reasons={"computed-immersion-unavailable"}; return result end
    actual.water.computedImmersionRate=rate
    local _,mapping=self.native:placement_collision_model(self.planned.root.collision)
    local wild=self:_call("wild-npc",self.native.utility,"IsWildNPC",state.actor)
    local angle=self:_call("selected-slope",movement,"GetWalkableFloorAngleByPriority")
    if type(wild)~="boolean" or not finite(angle) then result.reasons={"initialization-policy-unreadable"}; return result end
    local profile=actual.root.collision.profileName
    actual.initializationPolicy={isWildNPC=wild,nativeNPC=state.actor:IsA("/Script/Pal.PalNPC"),
        rootProfileExcluded=profile=="pawn_nodamageflypal" or profile=="pawnparts_nonblock",
        playerPawnChannel=mapping.playerPawnChannel,selectedWalkableAngle=angle,drySceneQualified=self.drySceneQualified==true}
    if not self.a.valid(state.component) or not state.component:IsA("/Script/Pal.PalCharacterParameterComponent")
        or not self.a.same(self:_call("parameter-owner",state.component,"GetOwner"),state.actor) then
        result.reasons={"initialized-parameter-owner"}; return result
    end
    actual.parameterRadius=self:_call("parameter-radius",state.component,"GetCapsuleRadius")
    if not finite(actual.parameterRadius) then actual.parameterRadius=nil; result.reasons={"initialized-parameter-radius"}; return result end
    local actions=self:_call("ai-component",state.controller,"GetAIActionComponent")
    if not self.a.valid(actions) then result.reasons={"ai-observation-unavailable"}; return result end
    actual.currentActionPresent=self.a.valid(self:_call("current-action",actions,"GetCurrentAction_BP"))
    result.comparison,result.reasons,result.expectedInitialization=Shape.reconcile(self.planned,actual)
    if result.comparison=="MATCH" then
        if self.firstSelectedAngle and not close(self.firstSelectedAngle,angle,0.0001) then
            result.comparison,result.reasons="MISMATCH",{"initialized-slope-policy-changed"}
        else
            self.firstSelectedAngle=angle
        end
    end
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
