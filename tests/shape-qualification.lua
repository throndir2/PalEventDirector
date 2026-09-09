return function(test,equal,truthy)
    local Native=require("ped.custom_assault_native")
    local Shape=require("ped.shape_qualification")
    local Survey=require("ped.surface_survey")
    local Config=require("ped.config")
    local util=require("ped.util")
    local function fixture(callback,case)
        local f={now=1000,spawns=0,despawns=0,surveys=0,calls={},signatures={},
            floorQueries={},navQueries={},supportPoints={},pathPoints={},residencies=0,prefilters=0}
        local next_address=0
        local function object(values)
            next_address=next_address+1
            values=values or {}
            values.address=tostring(next_address)
            values.IsValid=function() return true end
            return values
        end
        local function id(value)
            if value==nil or not value.A or (value.A==0 and value.B==0 and value.C==0 and value.D==0) then return nil end
            return table.concat({value.A,value.B,value.C,value.D},"-")
        end
        local zero={A=0,B=0,C=0,D=0}
        local identity={PlayerUId=util.deep_copy(zero),InstanceId={A=1,B=2,C=3,D=4},DebugName=""}
        local world=object({IsA=function() return true end})
        f.movementClass=object()
        local function character(cdo)
            local actor=object({IsA=function(_,path)
                return path=="/Script/Pal.PalCharacter" or path=="/Script/Pal.PalNPC"
                    or path==require("ped.bounties").pawn_class("BOSS_Hunter_Rifle")
            end})
            local function component(kind,values)
                local value=object(values)
                value.GetOwner=function() return actor end
                value.GetWorld=function() return world end
                value.IsA=function(_,path)
                    return path==kind or path=="/Script/Engine.PrimitiveComponent"
                        or (kind=="/Script/Pal.PalCharacterMovementComponent" and path=="/Script/Engine.CharacterMovementComponent")
                end
                return value
            end
            local function primitive(kind,z)
                local value=component(kind,{
                    RelativeLocation={X=0,Y=0,Z=z},RelativeScale3D={X=1,Y=1,Z=1},RelativeRotation={Pitch=0,Yaw=0,Roll=0},
                    collisionEnabled=3,objectType=2,responses={},
                    profileName="Pawn",
                })
                for index=1,32 do value.responses[index]=2 end
                value.GetCollisionEnabled=function(self) return self.collisionEnabled end
                value.GetCollisionObjectType=function(self) return self.objectType end
                value.GetCollisionProfileName=function(self) return self.profileName end
                value.GetCollisionResponseToChannel=function(self,channel)
                    truthy(channel>=0 and channel<=31)
                    return self.responses[channel+1]
                end
                value.K2_GetComponentScale=function(self) return self.worldScale or self.RelativeScale3D end
                value.K2_GetComponentRotation=function(self) return self.RelativeRotation end
                value.K2_GetComponentLocation=function(self)
                    if self==actor.CapsuleComponent then return self.RelativeLocation end
                    local root=actor.CapsuleComponent.RelativeLocation
                    return {X=root.X+self.RelativeLocation.X,Y=root.Y+self.RelativeLocation.Y,Z=root.Z+self.RelativeLocation.Z}
                end
                return value
            end
            local root=primitive("/Script/Engine.CapsuleComponent",0)
            root.CapsuleRadius,root.CapsuleHalfHeight=30,30
            root.responses[17]=cdo and 0 or 2
            if not cdo then root.profileName="Custom" end
            root.GetScaledCapsuleRadius=function(self) return self.CapsuleRadius*self.RelativeScale3D.X end
            root.GetScaledCapsuleHalfHeight=function(self) return self.CapsuleHalfHeight*self.RelativeScale3D.Z end
            actor.CapsuleComponent,actor.RootComponent=root,root
            actor.Mesh=primitive("/Script/Engine.SkeletalMeshComponent",-33)
            actor.Mesh.AttachParent=root
            actor.Mesh.collisionEnabled,actor.Mesh.objectType,actor.Mesh.profileName=0,0,"NoCollision"
            for index=1,32 do actor.Mesh.responses[index]=0 end
            actor.StaticCharacterParameterComponent=component("/Script/Pal.PalStaticCharacterParameterComponent",{
                MeshCapsuleRadius=30,MeshCapsuleHalfHeight=95,MeshRelativeLocation={X=0,Y=0,Z=-97},
            })
            actor.CharacterMovement=component("/Script/Pal.PalCharacterMovementComponent",{
                NavAgentProps={AgentRadius=cdo and -1 or 30,AgentHeight=cdo and -1 or 60,AgentStepHeight=-1},
                WalkableFloorZ=cdo and 0.7071067690849304 or 0.017452383413910866,WalkableFloorAngle=cdo and 45 or 89,
                bUpdateNavAgentWithOwnersCollision=true,UpdatedComponent=root,CharacterOwner=actor,MovementMode=1,CustomMovementMode=0,
                EnteredWaterFlag=0,WaterPlaneZ=3.4028234663852886e38,InWaterRate=0.6499999761581421,Velocity={X=0,Y=0,Z=0},
                GetClass=function() return f.movementClass end,
                GetWalkableFloorAngleByPriority=function() return f.selectedAngle or 89 end,
                GetInWaterRate=function() return f.computedImmersion or 0 end,
                IsMovingOnGround=function() return true end,IsFalling=function() return false end,IsFlying=function() return false end,
                GetCurrentAcceleration=function() return {X=0,Y=0,Z=0} end,
            })
            actor.K2_GetRootComponent=function() return root end
            actor.GetMovementComponent=function() return actor.CharacterMovement end
            actor.K2_GetActorLocation=function() return root.RelativeLocation end
            actor.K2_GetActorRotation=function() return root.RelativeRotation end
            actor.GetPendingMovementInputVector=function() return {X=0,Y=0,Z=0} end
            actor.GetLastMovementInputVector=function() return {X=0,Y=0,Z=0} end
            actor.GetCharacterParameterComponent=function() return actor.parameterComponent end
            actor.parameterComponent=component("/Script/Pal.PalCharacterParameterComponent",{
                GetIsCapturedProcessing=function() return f.capturing==true end,
                GetCapsuleRadius=function() return 30 end,
            })
            actor.GetController=function() return f.controller end
            actor.IsInitialized=function() return not f.initializing end
            actor.bIsPalActiveActor=true
            actor.IsActorBeingDestroyed=function() return not cdo and f.destroyed==true end
            return actor
        end
        f.cdo,f.actor=character(true),character(false)
        local actions=object({
            GetCurrentAction_BP=function() return f.action end,
            TerminateCurrentActionByClass=function() end,
            SetActionClassParameter=function()
                f.dispatched=(f.dispatched or 0)+1
                f.action=object({IsA=function(_,path) return path=="/Script/AIModule.PawnAction" end})
                return f.action
            end,
        })
        f.controller=object({GetAIActionComponent=function() return actions end,GetMyPalBlackboard=function() return object() end,
            AddTargetNPC=function(_,target) equal(target,f.defender); f.targets=(f.targets or 0)+1 end,
            StopMovement=function() f.stops=(f.stops or 0)+1 end})
        local parameter=object({
            SaveParameter={IsPlayer=false,OwnerPlayerUId=util.deep_copy(zero),OldOwnerPlayerUIds={}},
            GetPalId=function() return identity end,GetCharacterID=function() return "BOSS_Hunter_Rifle" end,
            GetMaxHP=function() return 1000 end,IsDead=function() return f.dead==true end,
        })
        local handle=object({
            GetIndividualID=function() return f.id_pending and {PlayerUId=zero,InstanceId=zero} or identity end,
            TryGetIndividualParameter=function() return parameter end,
            TryGetIndividualActor=function() return not f.missing and f.actor or nil end,
        })
        local bridge={config=Config.defaults(),clock=function() return f.now end,
            logger={info=function() end},delivery_profile="laboratory-native-test"}
        bridge.config.mode="laboratory"
        bridge.config.capabilities.startAllInvasions=true
        function bridge:_native_step(_,operation)
            if self.native_fault then return false,self.native_fault end
            local ok,result=pcall(operation)
            if not ok then self.native_fault=result end
            return ok,result
        end
        function bridge:_native_call(_,owner,method,...)
            if self.native_fault then return false,self.native_fault end
            f.calls[#f.calls+1]=method
            if f.fail_method==method then self.native_fault="fixture-native-fault"; return false,self.native_fault end
            local args=table.pack(...)
            return self:_native_step(method,function() return owner[method](owner,table.unpack(args,1,args.n)) end)
        end
        local engine=Native.new(bridge,{
            valid=function(value) return type(value)=="table" and type(value.IsValid)=="function" and value:IsValid() end,
            unwrap=function(value) return value end,same=function(a,b) return a~=nil and a==b end,
            address=function(value) return value and value.address end,guid=id,text=function(value) return value end,
            fname=function() return function(value) return value end end,
        })
        engine.world,engine.utility=world,object({
            GetEngineCollisionChannelByPalObjectType=function(_,selector) equal(selector,2); return f.playerPawnChannel or 16 end,
            IsWildNPC=function(_,actor) equal(actor,f.actor); return f.wildNPC~=false end,
            ChangeDefaultLandMovementModeForWalking=function() f.walking=(f.walking or 0)+1 end,
            GetBattleManager=function() return object({TargetIsPlayerOrPlayersOtomoPal=function() return false end}) end,
            GetIndividualCharacterParameterByActor=function(_,actor) return actor.parameter end,
        })
        engine.controllerClass=object()
        engine.classes.invoker=object()
        f.actor.GetComponentByClass=function() return object({ActivateInvoker=function() f.invokers=(f.invokers or 0)+1 end}) end
        engine._action_class=function() return object({type=function() return "UClass" end}) end
        engine._choose_defender=function() return f.defender end
        engine.characterManager=object({
            GetIndividualHandle=function(_,value)
                equal(id(value.InstanceId),id(identity.InstanceId)); equal(value.DebugName,"")
                return not f.missing and handle or nil
            end,
            DespawnCharacterByHandle=function(_,which,delegate)
                equal(which,handle); equal(delegate,nil)
                f.despawns=f.despawns+1
                f.missing,f.destroyed=true,true
            end,
        })
        engine.npcManager=object({SpawnNPCForServer=function(_,info,delegate)
            equal(info.CharacterID,"BOSS_Hunter_Rifle"); equal(info.Level,30); equal(info.Squad,nil); equal(delegate,nil)
            equal(info.ControllerClass,engine.controllerClass)
            f.spawns=f.spawns+1
            f.actor.CapsuleComponent.RelativeLocation=util.shallow_copy(info.Location)
            return handle
        end})
        engine.actor_world=function() return world end
        engine._class=function(_,path)
            if path=="/Script/Pal.PalCharacterMovementComponent" then return f.movementClass end
            return object({GetCDO=function() return f.cdo end})
        end
        engine._signature=function(_,name,expected)
            f.signatures[name]=expected
            return {ReturnValue={field={}}}
        end
        engine._struct=function(_,_,name,fields)
            truthy(name=="Vector" or name=="Rotator")
            local count=0
            for _,field in pairs(fields) do equal(field[1],"DoubleProperty"); truthy(field[2]<=16); count=count+1 end
            equal(count,3)
        end
        engine.startup_floor=function(_,actual,point,character_id)
            equal(actual,world); equal(character_id,"BOSS_Hunter_Rifle")
            f.floorQueries[#f.floorQueries+1]=util.shallow_copy(point)
            if f.floor_projection then return f.floor_projection(point,#f.floorQueries) end
            return not f.floor_missing and util.shallow_copy(point) or nil
        end
        engine.startup_nav=function(_,actual,point)
            equal(actual,world)
            f.navQueries[#f.navQueries+1]=util.shallow_copy(point)
            if f.nav_projection then return f.nav_projection(point) end
            return not f.nav_missing and util.shallow_copy(point) or nil
        end
        engine._placement_support=function(_,_,_,point)
            f.supportPoints[#f.supportPoints+1]=util.shallow_copy(point)
            if f.support_result then return f.support_result(point,#f.supportPoints) end
            return {ready=not f.support_missing,reason="support-fixture-missing"}
        end
        engine._placement_path=function(_,scope,_,point,goal)
            truthy(scope.leashRadius<=4000)
            f.pathPoints[#f.pathPoints+1]={point=util.shallow_copy(point),goal=util.shallow_copy(goal)}
            if f.path_result then return f.path_result(point,goal,#f.pathPoints) end
            return {ready=not f.path_missing,reason="path-fixture-missing",pathPoints=2,pathLength=500,defaultNavDataUsed=true}
        end
        local scope={world=world,baseId="9-0-0-0",guildId="8-0-0-0",origin={X=0,Y=0,Z=1000},range=2000,leashRadius=4000,
            positions={{X=500,Y=0,Z=1000}},players={},base=object({
                GetId=function() return {A=9,B=0,C=0,D=0} end,
                GetGroupIdBelongTo=function() return {A=8,B=0,C=0,D=0} end,
            })}
        local member={index=1,slot=1,groupId="startup:shape-fixture",baseId=scope.baseId,characterId="BOSS_Hunter_Rifle",
            level=30,phase="planned"}
        local runner={engine=engine,scopes={scope},state={case=case or Shape.CASE,experiment=Shape.contract(case or Shape.CASE),
            runId="shape-fixture",artifactSha256=string.rep("2",64),sourceRevision=string.rep("1",40),
            status="running",stage="spawn",members={member},spawned=0,initialized=0,moved=0,
            helpersCreated=1,helpersCleaned=0,helpers={{phase="configured"}}}}
        runner.support={native=engine,residency=function()
            f.residencies=f.residencies+1
            return true,{ready=false,physicalQueried=false,enabled=true,streamingComplete=not f.residency_missing}
        end}
        bridge.startup_test=runner
        f.engine,f.scope,f.member,f.runner=engine,scope,member,runner
        function f:defender_at(base,guild)
            return object({IsA=function(_,path) return path=="/Script/Pal.PalCharacter" end,
                K2_GetActorLocation=function() return {X=100,Y=0,Z=1000} end,
                parameter=object({GetBaseCampId=function() return {A=base or 9,B=0,C=0,D=0} end,
                    GetGroupId=function() return {A=guild or 8,B=0,C=0,D=0} end}),
            })
        end
        f.defender=f:defender_at()
        f.environment={COMPUTERNAME="IMOUTO",PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN="shape-fixture",
            PAL_EVENT_DIRECTOR_SOURCE_REVISION=runner.state.sourceRevision,PAL_EVENT_DIRECTOR_ARTIFACT_SHA256=runner.state.artifactSha256,
            PAL_EVENT_DIRECTOR_SERVER_BUILD_ID="25080279",PAL_EVENT_DIRECTOR_UE4SS_TAG="2281fa31",PAL_EVENT_DIRECTOR_UE4SS_API_VERSION="3.0.1"}
        local previous_getenv,previous_survey=os.getenv,Survey.new
        os.getenv=function(name) return f.environment[name] end
        Survey.new=function(actual,actual_scope,options)
            equal(actual,engine); equal(actual_scope,scope)
            local probe={point=util.shallow_copy(options.point)}
            local function template_collision()
                return {enabled=f.cdo.CapsuleComponent.collisionEnabled,objectType=f.cdo.CapsuleComponent.objectType,
                    profileName=f.cdo.CapsuleComponent.profileName:lower(),responses=util.deep_copy(f.cdo.CapsuleComponent.responses)}
            end
            local function physical_policy()
                local root_collision=template_collision()
                local expected=engine:placement_collision_model(root_collision)
                local mesh=f.cdo.Mesh
                local mesh_policy=Native.disabled_mesh_snapshot({collision={enabled=mesh.collisionEnabled,objectType=mesh.objectType,
                    profileName=mesh.profileName:lower(),responses=util.deep_copy(mesh.responses)},
                    relativeLocation=mesh.RelativeLocation,relativeScale=mesh.RelativeScale3D,relativeRotation=mesh.RelativeRotation})
                return {policy="physical-root-and-water-only-mesh-envelope",
                    rootCapsule={radius=f.cdo.CapsuleComponent.CapsuleRadius,halfHeight=f.cdo.CapsuleComponent.CapsuleHalfHeight,centerOffsetZ=0},
                    rootCollision=root_collision,expectedRootCollision=expected,mesh=mesh_policy}
            end
            function probe:local_proxy(point,shape)
                f.prefilters=f.prefilters+1
                local result=f.local_proxy_result and f.local_proxy_result(point,shape,f.prefilters)
                    or {complete=true,classification="proxy-clear",spawnQualified=false,templateOnly=true,localOnly=true}
                local _,policy=engine:placement_collision_model(template_collision())
                result.collisionPolicy=result.collisionPolicy or policy
                result.physicalPolicy=result.physicalPolicy or physical_policy()
                return result
            end
            function probe:run()
                f.surveys=f.surveys+1
                if f.on_survey then f.on_survey() end
                local measured=engine:_placement_shape("BOSS_Hunter_Rifle")
                self.shape,self.sourceCollision=measured,template_collision()
                local policy
                self.effectiveSourceCollision,policy=engine:placement_collision_model(self.sourceCollision)
                return {complete=true,classification=f.survey_classification or "proxy-clear",
                    spawnQualified=false,templateOnly=true,bodyProxy=util.deep_copy(measured.bodyProxy),collisionPolicy=policy,
                    physicalPolicy=physical_policy(),
                    columnOceanWitness=true,footAboveWaterCm=967,waterContacts=0,mutualBlockers=0,unqualifiedBodies=0}
            end
            return probe
        end
        function f:prepare()
            local ok,result=engine:prepare_spawn(scope,member)
            truthy(ok,result); self.placement=result
            return result
        end
        function f:search_all()
            local result
            for _=1,9 do
                result=self:prepare()
                if not result.pending then return result end
            end
            error("site search did not finish within its candidate budget")
        end
        function f:spawn()
            member.spawnRequested,member.phase=true,"requested"
            local ok,result=engine:spawn(scope,member)
            if ok then
                member.handle=result
                runner.state.spawned,runner.state.stage=1,"initialize"
            end
            return ok,result
        end
        function f:ready()
            local ok,result=engine:inspect(member.handle,member)
            truthy(ok,result)
            local assigned=engine:startup_identity(member)
            member.instanceGuid,member.playerGuid=assigned.instanceGuid,assigned.playerGuid
            member.phase,member.actorAddress=result.phase,result.actorAddress
            if result.phase=="alive" then
                runner.state.initialized,runner.state.stage,runner.state.stageStartedAt=1,"shape-observe",self.now
            end
            return result
        end
        function f:observe()
            local plan=util.shallow_copy(member)
            local ok,result=engine:startup_shape_observation(scope,plan)
            if ok and runner.state.case==Shape.ENGAGEMENT_CASE then
                runner.state.shapeObservations=runner.state.shapeObservations or {}
                runner.state.shapeObservations[#runner.state.shapeObservations+1]=result
            end
            return ok,result
        end
        function f:arm()
            engine:startup_test_stage_changed(runner,"engagement")
            runner.state.stage,runner.state.stageStartedAt="engagement",self.now
            local ok,result=engine:startup_arm_qualified_engagement(scope,member)
            if ok and result.armed then
                runner.state.qualifiedEngagementArmed,runner.state.engagementAuthorization=true,result
            end
            return ok,result
        end
        function f:qualify_engagement()
            truthy(self:prepare().ready); truthy(self:spawn()); equal(self:ready().phase,"alive")
            local ok,result=self:observe()
            truthy(ok,result); equal(result.comparison,"MATCH")
            self.now=self.now+1
            ok,result=self:observe()
            truthy(ok,result); equal(result.comparison,"MATCH")
            ok,result=self:arm()
            truthy(ok,result); equal(result.armed,true)
        end
        local ok,why=xpcall(function() callback(f,object) end,debug.traceback)
        os.getenv,Survey.new=previous_getenv,previous_survey
        assert(ok,why)
    end

    test("one-instance proof binds the exact fresh survey without promoting its template result",function()
        fixture(function(f)
            local result=f:prepare()
            truthy(result.ready); equal(result.spawnQualified,false); equal(result.surfaceSurvey.spawnQualified,false)
            equal(result.defaultNavDataUsed,true); equal(result.templateOnly,true); equal(f.surveys,1)
            equal(result.plannedGeometry.root.halfHeight,30); equal(result.plannedGeometry.body.halfHeight,95)
            equal(result.plannedGeometry.mesh.relativeLocation.Z,-33); equal(result.plannedGeometry.body.authoredOffset.Z,-97)
            equal(result.surfaceSurvey.bodyProxy.centerOffsetZ,62)
            truthy(f:spawn()); equal(f.spawns,1)
            equal(f.engine:spawn(f.scope,f.member),false); equal(f.spawns,1)
        end)
    end)

    test("ordinary and combat startup cases retain the dry-clearance gate with no laboratory proof",function()
        for _,case in ipairs({"spawn-cleanup","engagement","surface-survey","movement"}) do
            fixture(function(f)
                f.runner.state.case,f.runner.state.experiment=case,nil
                local result=f:prepare()
                equal(result.ready,false); equal(result.reason,"dry-clearance-unqualified"); equal(f.surveys,0)
                equal(f:spawn(),false); equal(f.spawns,0)
            end)
        end
        fixture(function(f)
            f.engine.bridge.startup_test=nil
            local result=f:prepare()
            equal(result.ready,false); equal(result.reason,"dry-clearance-unqualified"); equal(f.surveys,0)
        end)
    end)

    test("shape admission refuses a wrong run artifact runtime contract or member before surveying",function()
        for _,change in ipairs({
            function(f) f.environment.PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN="another-run" end,
            function(f) f.environment.PAL_EVENT_DIRECTOR_ARTIFACT_SHA256=string.rep("3",64) end,
            function(f) f.environment.PAL_EVENT_DIRECTOR_UE4SS_TAG="unqualified" end,
            function(f) f.runner.state.experiment=nil end,
            function(f) f.member.characterId="BOSS_Ninja" end,
            function(f) f.member.level=31 end,
            function(f) f.runner.state.helpersCleaned=1 end,
            function(f) f.runner.state.members[2]=util.shallow_copy(f.member) end,
        }) do
            fixture(function(f)
                change(f)
                equal(f.engine:prepare_spawn(f.scope,f.member),false)
                equal(f.surveys,0); equal(f.spawns,0)
            end)
        end
    end)

    test("shape proof cannot be reused copied to another member or consumed by another run or case",function()
        for _,change in ipairs({
            function(f) f.member=util.shallow_copy(f.member) end,
            function(f) f.member.index=2 end,
            function(f) f.member.characterId="BOSS_Ninja" end,
            function(f) f.member.level=31 end,
            function(f) f.runner.state.runId="another-run" end,
            function(f) f.runner.state.artifactSha256=string.rep("3",64) end,
            function(f) f.runner.state.case="engagement" end,
            function(f) f.scope=util.shallow_copy(f.scope) end,
            function(f) f.scope.positions[1].X=f.scope.positions[1].X+1 end,
        }) do
            fixture(function(f)
                truthy(f:prepare().ready)
                f.member.spawnRequested,f.member.phase=true,"requested"
                change(f)
                equal(f.engine:spawn(f.scope,f.member),false)
                equal(f.spawns,0)
                equal(f.engine:spawn(f.scope,f.member),false); equal(f.spawns,0); equal(f.surveys,1)
            end)
        end
    end)

    test("shape proof is single-attempt expires promptly and never replays a failed native request",function()
        fixture(function(f)
            truthy(f:prepare().ready)
            equal(f.engine:prepare_spawn(f.scope,f.member),false); equal(f.surveys,1); equal(f.spawns,0)
        end)
        fixture(function(f)
            truthy(f:prepare().ready); f.now=f.now+3
            equal(f:spawn(),false); equal(f.spawns,0)
        end)
        fixture(function(f)
            truthy(f:prepare().ready); f.fail_method="SpawnNPCForServer"
            equal(f:spawn(),false)
            local count=#f.calls
            equal(f:spawn(),false); equal(f.engine:prepare_spawn(f.scope,f.member),false)
            equal(#f.calls,count); equal(f.surveys,1)
            equal(f.engine.placements["startup:shape-fixture:1"],nil)
        end)
    end)

    test("experimental proof cannot be laundered into ordinary placement or another native adapter",function()
        fixture(function(f)
            truthy(f:prepare().ready)
            f.engine.placements["startup:shape-fixture:1"].shapeQualification=nil
            f.runner.state.case="engagement"
            equal(f:spawn(),false); equal(f.spawns,0)
        end)
        fixture(function(f)
            truthy(f:prepare().ready)
            local other=Native.new(f.engine.bridge,f.engine.a)
            other.world,other.npcManager,other.characterManager=f.engine.world,f.engine.npcManager,f.engine.characterManager
            other.controllerClass=f.engine.controllerClass
            other.placements["startup:shape-fixture:1"]=f.engine.placements["startup:shape-fixture:1"]
            f.member.spawnRequested,f.member.phase=true,"requested"
            equal(other:spawn(f.scope,f.member),false); equal(f.spawns,0)
        end)
    end)

    test("shape qualification requires current residency support floor navigation path and a dry proxy scene",function()
        for _,field in ipairs({"residency_missing","floor_missing","nav_missing","path_missing","support_missing"}) do
            fixture(function(f)
                f[field]=true
                equal(f:prepare().ready,false); equal(f.spawns,0); equal(f.surveys,0)
            end)
        end
        for _,classification in ipairs({"wet","blocked","unsupported"}) do
            fixture(function(f)
                f.survey_classification=classification
                local result=f:prepare()
                equal(result.ready,false); equal(result.spawnQualified,false); equal(f.spawns,0)
                equal(result.reason,"shape-survey-"..classification)
            end)
        end
        fixture(function(f)
            f.engine.bridge.config.customAssault.allowInBaseFallback=false
            f.scope.positions[1].Z=1400
            equal(f:prepare().ready,false); equal(f.surveys,0)
        end)
    end)

    test("shape admission waits for transient streaming readiness before consuming its single attempt",function()
        fixture(function(f)
            f.residency_missing=true
            local result=f:prepare()
            equal(result.ready,false); equal(result.pending,true); equal(result.reason,"shape-residency-pending")
            equal(f.surveys,0); equal(f.spawns,0)
            f.residency_missing=false
            result=f:prepare()
            equal(result.ready,true); equal(result.pending,false); equal(f.surveys,1)
            equal(f.engine:prepare_spawn(f.scope,f.member),false)
            equal(f.surveys,1)
        end)
    end)

    test("shape search skips a penetrating approach and consumes only the first passing distinct site",function()
        fixture(function(f)
            f.support_result=function(_,index)
                return {ready=index>2,reason="support-penetrating",support={
                    startOverlap={classification=index<=2 and "BLOCKED" or "CLEAR",blockers=index<=2 and 1 or 0}}}
            end
            local result=f:prepare()
            equal(result.ready,false); equal(result.pending,true); equal(result.reason,"shape-site-search-pending")
            equal(result.attempts,2); equal(f.surveys,0); equal(f.spawns,0)
            equal(f.engine.shapeQualification.attempted,nil)
            equal(f.scope.positions[1].X,500)
            equal(#result.selection.rejections,2); equal(result.selection.rejections[1].support.startOverlap.classification,"BLOCKED")
            result=f:prepare()
            equal(result.ready,true); equal(result.attempts,3); equal(f.surveys,1); equal(#f.supportPoints,3)
            equal(result.fallbackReason,"support-penetrating"); equal(result.selection.selectedMode,"in-base")
            equal(result.selection.selectedCandidate,3); equal(#f.pathPoints,1)
            for _,axis in ipairs({"X","Y","Z"}) do equal(result.position[axis],f.supportPoints[3][axis]) end
            truthy(f:spawn()); equal(f.spawns,1)
        end)
    end)

    test("independent start-overlap queries stay inside the two-site budget before the one-shot survey",function()
        fixture(function(f,object)
            local overlaps,sweeps=0,0
            local owner=object({IsA=function(_,path) return path=="/Script/Engine.Actor" end})
            local component=object({
                IsA=function(_,path)
                    return path=="/Script/Engine.PrimitiveComponent" or path=="/Script/Engine.ShapeComponent"
                end,
                GetOwner=function() return owner end,GetWorld=function() return f.scope.world end,
                GetCollisionEnabled=function() return 3 end,
                GetCollisionResponseToChannel=function(_,channel) equal(channel,12); return 2 end,
                GetWalkableSlopeOverride=function() return {WalkableSlopeBehavior=0} end,
            })
            local kismet=object({CapsuleOverlapComponents=function(_,world,point,radius,half,types,filter,ignored,output)
                equal(world,f.scope.world); equal(radius,30); equal(half,30); equal(#types,32)
                equal(filter,nil); equal(#ignored,0); equal(#output,0)
                equal(point.Z,f.scope.origin.Z+5)
                overlaps=overlaps+1
                if overlaps<=2 then output[1]=component; return true end
                return false
            end})
            f.engine.bridge._static_find=function(_,path)
                equal(path,"/Script/Engine.Default__KismetSystemLibrary")
                return kismet
            end
            f.engine.utility.GetEngineCollisionChannelByPalTraceType=function(_,kind) equal(kind,3); return 12 end
            f.engine.physicsLibrary={CapsuleTraceSingleByPalTraceType=function(_,world,start,finish,radius,half,kind,_,_,_,hit)
                equal(world,f.scope.world); equal(radius,30); equal(half,30); equal(kind,3)
                if finish.Z>start.Z then return false end
                sweeps=sweeps+1
                hit.bBlockingHit,hit.bStartPenetrating=true,true
                hit.ImpactNormal={X=0,Y=0,Z=1}
                hit.Location={X=start.X,Y=start.Y,Z=start.Z-5}
                hit.Component={Get=function() return component end}
                return true
            end}
            f.engine._placement_support=Native._placement_support
            local result=f:prepare()
            equal(result.ready,false); equal(result.pending,true); equal(result.attempts,2)
            equal(overlaps,2); equal(sweeps,0); equal(f.surveys,0); equal(f.spawns,0)
            equal(result.selection.rejections[1].support.startOverlap.classification,"BLOCKED")
            result=f:prepare()
            equal(result.ready,true); equal(result.attempts,3); equal(overlaps,3); equal(sweeps,1)
            equal(f.surveys,1); equal(f.spawns,0); equal(result.spawnQualified,false)
        end)
    end)

    test("physically blocked preferred site yields to a locally clear in-base site before the single full survey",function()
        fixture(function(f)
            f.local_proxy_result=function(point,shape,index)
                equal(point.Z,1000); equal(shape.bodyProxy.radius,30)
                equal(shape.bodyProxy.halfHeight,95); equal(shape.bodyProxy.centerOffsetZ,62)
                return {complete=true,localOnly=true,templateOnly=true,spawnQualified=false,
                    classification=index==1 and "blocked" or "proxy-clear",mutualBlockers=index==1 and 1 or 0,
                    componentCategories={staticMesh={components=index==1 and 1 or 0,mutualBlockers=index==1 and 1 or 0}}}
            end
            f.on_survey=function() equal(f.prefilters,2) end
            local result=f:prepare()
            equal(result.ready,true); equal(result.attempts,2); equal(f.prefilters,2); equal(f.surveys,1)
            equal(result.selection.selectedMode,"in-base"); equal(result.fallbackReason,"shape-local-proxy-blocked")
            equal(result.selection.rejections[1].localProxy.componentCategories.staticMesh.mutualBlockers,1)
            equal(result.selection.selectedLocalProxy.classification,"proxy-clear")
            for _,axis in ipairs({"X","Y","Z"}) do equal(result.position[axis],f.pathPoints[2].point[axis]) end
            equal(f.spawns,0); truthy(f:spawn()); equal(f.spawns,1)
            equal(f.engine:prepare_spawn(f.scope,f.member),false); equal(f.surveys,1)
        end)
    end)

    test("root and disabled-mesh policy drift before the final survey cannot mint a spawn proof",function()
        for _,change in ipairs({
            function(f) f.cdo.CapsuleComponent.responses[18]=0 end,
            function(f) f.cdo.Mesh.collisionEnabled=1 end,
            function(f) f.cdo.Mesh.responses[1]=2 end,
            function(f) f.cdo.Mesh.RelativeRotation.Yaw=90 end,
        }) do
            fixture(function(f)
                f.on_survey=function() change(f) end
                local result=f:prepare()
                equal(result.ready,false); equal(result.reason,"shape-template-changed")
                equal(f.surveys,1); equal(f.spawns,0)
                equal(f.engine:spawn(f.scope,f.member),false); equal(f.spawns,0)
            end)
        end
        fixture(function(f)
            f.local_proxy_result=function()
                return {complete=true,localOnly=true,templateOnly=true,spawnQualified=false,classification="proxy-clear",
                    physicalPolicy={policy="unmodelled-extra-physical-body"}}
            end
            local result=f:prepare()
            equal(result.ready,false); equal(result.reason,"shape-template-changed"); equal(f.spawns,0)
        end)
    end)

    test("initialized mesh collision must remain the matched disabled policy before engagement",function()
        for _,change in ipairs({
            function(f) f.actor.Mesh.collisionEnabled=1 end,
            function(f) f.actor.Mesh.objectType=2 end,
            function(f) f.actor.Mesh.profileName="Custom" end,
            function(f) f.actor.Mesh.responses[1]=2 end,
        }) do
            fixture(function(f)
                truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
                change(f)
                local ok,result=f:observe()
                truthy(ok,result); equal(result.comparison,"UNSUPPORTED")
                equal(result.reasons[1],"mesh-collision-policy-unqualified")
                equal(f:arm(),false)
                equal(f.dispatched,nil); equal(f.walking,nil)
            end,Shape.ENGAGEMENT_CASE)
        end
    end)

    test("unsupported local proxies exhaust bounded sites without consuming the full survey attempt",function()
        fixture(function(f)
            f.local_proxy_result=function()
                return {complete=true,localOnly=true,templateOnly=true,spawnQualified=false,
                    classification="unsupported",unqualifiedBodies=1,componentCategories={other={components=1,unqualifiedBodies=1}}}
            end
            local result=f:search_all()
            equal(result.ready,false); equal(result.reason,"shape-sites-exhausted")
            equal(result.attempts,17); equal(f.prefilters,17); equal(f.surveys,0); equal(f.spawns,0)
            equal(f.engine.shapeQualification.attempted,nil)
            equal(#result.selection.rejections,17)
            equal(result.selection.rejections[1].localProxy.unqualifiedBodies,1)
        end)
    end)

    test("local proxy failures and forged qualification claims never repeat or authorize a spawn",function()
        for _,kind in ipairs({"native-fault","spawn-claim"}) do
            fixture(function(f)
                f.local_proxy_result=function()
                    if kind=="native-fault" then error("fixture local proxy native fault") end
                    return {complete=true,localOnly=true,templateOnly=true,spawnQualified=true,classification="proxy-clear"}
                end
                equal(f.engine:prepare_spawn(f.scope,f.member),false)
                equal(f.engine:prepare_spawn(f.scope,f.member),false)
                equal(f.prefilters,1); equal(f.surveys,0); equal(f.spawns,0)
            end)
        end
    end)

    test("a blocked final full survey is not reopened after local proxy clearance",function()
        fixture(function(f)
            f.survey_classification="blocked"
            local result=f:prepare()
            equal(result.ready,false); equal(result.reason,"shape-survey-blocked")
            equal(f.prefilters,1); equal(f.surveys,1); equal(f.engine.shapeQualification.attempted,true)
            equal(f.engine:prepare_spawn(f.scope,f.member),false)
            equal(f.prefilters,1); equal(f.surveys,1); equal(f.spawns,0)
        end)
    end)

    test("shape search tests a complete same-base path for every supported candidate",function()
        fixture(function(f)
            f.path_result=function(point,goal,index)
                equal(point.Z,1000); equal(goal.Z,1000)
                return {ready=index>2,reason="path-unreachable",pathPoints=2,pathLength=500,defaultNavDataUsed=true}
            end
            local result=f:prepare()
            equal(result.ready,false); equal(result.attempts,2); equal(f.surveys,0); equal(#f.supportPoints,2)
            equal(result.selection.rejections[1].reason,"path-unreachable")
            result=f:prepare()
            equal(result.ready,true); equal(#f.pathPoints,3); equal(#f.supportPoints,3)
            equal(result.fallbackReason,"path-unreachable"); equal(f.surveys,1)
        end)
    end)

    test("shape search exhausts seventeen same-height sites two per poll without a survey or spawn",function()
        fixture(function(f)
            f.scope.positions[1]={X=137,Y=251,Z=1000}
            f.support_missing=true
            local result
            for poll=1,9 do
                local before=#f.supportPoints
                result=f:prepare()
                truthy(#f.supportPoints-before<=2)
                equal(result.pending,poll<9); equal(result.ready,false)
            end
            equal(result.reason,"shape-sites-exhausted"); equal(result.attempts,17)
            equal(result.selection.candidateLimit,17); equal(result.selection.uniqueCandidates,17)
            equal(result.selection.projectedSites,17); equal(#result.selection.rejections,17)
            equal(#f.floorQueries,34); equal(#f.supportPoints,17); equal(#f.pathPoints,0)
            for index,point in ipairs(f.supportPoints) do
                equal(point.Z,1000)
                for previous=1,index-1 do
                    local other=f.supportPoints[previous]
                    truthy((point.X-other.X)^2+(point.Y-other.Y)^2+(point.Z-other.Z)^2>1)
                end
            end
            equal(f.surveys,0); equal(f.spawns,0); equal(f.engine.shapeQualification.attempted,nil)
            equal(f.engine:prepare_spawn(f.scope,f.member),false); equal(#f.supportPoints,17)
        end)
    end)

    test("shape site selection honors disabled fallback and never substitutes the origin after a floor miss",function()
        fixture(function(f)
            f.engine.bridge.config.customAssault.allowInBaseFallback=false
            f.floor_missing=true
            local result=f:prepare()
            equal(result.reason,"shape-sites-exhausted"); equal(result.pending,false); equal(result.attempts,1)
            equal(result.selection.candidateLimit,1); equal(result.selection.rejections[1].reason,"shape-floor-unavailable")
            equal(#f.floorQueries,1); equal(f.floorQueries[1].X,500)
            equal(#f.supportPoints,0); equal(f.surveys,0); equal(f.spawns,0)
        end)
    end)

    test("shape site selection skips duplicate inputs and collapsed nav projections",function()
        fixture(function(f)
            local search=f.engine:_new_placement_search(f.scope,f.member)
            f.scope.positions[1]=util.shallow_copy(search.candidates[2].position)
            f.support_missing=true
            local result=f:search_all()
            equal(result.attempts,17); equal(result.selection.duplicates,1)
            equal(result.selection.uniqueCandidates,16); equal(#f.supportPoints,16)
            equal(#f.floorQueries,32); equal(f.surveys,0)
        end)
        fixture(function(f)
            f.support_missing=true
            f.nav_projection=function(point)
                if point.X==0 and point.Y==0 then return util.shallow_copy(point) end
                return {X=600,Y=100,Z=1000}
            end
            local result=f:search_all()
            equal(result.reason,"shape-sites-exhausted"); equal(result.attempts,17)
            equal(result.selection.duplicates,16); equal(#f.supportPoints,1)
            equal(#f.floorQueries,18); equal(f.surveys,0)
        end)
    end)

    test("shape search pauses across residency flaps without rechecking rejected sites",function()
        fixture(function(f)
            f.support_missing=true
            equal(f:prepare().attempts,2)
            f.residency_missing=true
            for _=1,3 do
                local result=f:prepare()
                equal(result.reason,"shape-residency-pending"); equal(result.attempts,2)
                equal(result.residency.physicalQueried,false)
                equal(#result.selection.rejections,2)
            end
            equal(#f.floorQueries,4); equal(#f.supportPoints,2); equal(f.surveys,0)
            f.residency_missing,f.support_missing=false,false
            local result=f:prepare()
            equal(result.ready,true); equal(result.attempts,3); equal(f.surveys,1)
            equal(#f.supportPoints,3)
        end)
    end)

    test("shape preparation rejects late readiness and late candidate success at the shared deadline",function()
        fixture(function(f)
            f.residency_missing=true
            truthy(f:prepare().pending)
            f.residency_missing,f.now=false,1120
            local result=f:prepare()
            equal(result.ready,false); equal(result.pending,false); equal(result.reason,"spawn-placement-timeout")
            equal(f.residencies,1); equal(f.surveys,0); equal(#f.floorQueries,0)
        end)
        fixture(function(f)
            f.path_result=function()
                f.now=1120
                return {ready=true,pathPoints=2,pathLength=500,defaultNavDataUsed=true}
            end
            local result=f:prepare()
            equal(result.reason,"spawn-placement-timeout"); equal(result.ready,false)
            equal(f.engine.shapeQualification.attempted,nil); equal(f.surveys,0); equal(f.spawns,0)
        end)
    end)

    test("a rejected one-shot survey or template never resumes the candidate search",function()
        for _,template_changed in ipairs({false,true}) do
            fixture(function(f)
                if template_changed then
                    f.on_survey=function() f.cdo.Mesh.RelativeLocation.Z=-40 end
                else f.survey_classification="wet" end
                local result=f:prepare()
                equal(result.ready,false); equal(result.pending,false)
                equal(result.reason,template_changed and "shape-template-changed" or "shape-survey-wet")
                equal(f.surveys,1); equal(#f.supportPoints,1); equal(f.engine.shapeQualification.attempted,true)
                equal(f.engine:prepare_spawn(f.scope,f.member),false)
                equal(f.surveys,1); equal(#f.supportPoints,1); equal(f.spawns,0)
            end)
        end
    end)

    test("pending shape preparation remains bound to its original caller and artifact",function()
        for _,change in ipairs({
            function(f) f.member=util.shallow_copy(f.member) end,
            function(f) f.scope=util.shallow_copy(f.scope) end,
            function(f) f.member.characterId="BOSS_Ninja" end,
            function(f) f.runner.state.runId="different-run" end,
            function(f) f.runner.state.artifactSha256=string.rep("4",64) end,
            function(f) f.runner.state.case="engagement" end,
            function(f) f.engine.bridge.config.customAssault.allowInBaseFallback=false end,
        }) do
            fixture(function(f)
                f.support_missing=true
                truthy(f:prepare().pending)
                change(f)
                equal(f.engine:prepare_spawn(f.scope,f.member),false)
                equal(f.residencies,1); equal(#f.supportPoints,2); equal(f.surveys,0); equal(f.spawns,0)
            end)
        end
    end)

    test("a native fault during a pre-attempt candidate stops all later site and survey work",function()
        fixture(function(f)
            f.support_result=function() error("fixture-native-fault") end
            equal(f.engine:prepare_spawn(f.scope,f.member),false)
            equal(f.engine.shapeQualification.search.interrupted,true)
            local calls=#f.calls
            equal(f.engine:prepare_spawn(f.scope,f.member),false)
            equal(#f.calls,calls); equal(f.residencies,1); equal(#f.supportPoints,1)
            equal(f.surveys,0); equal(f.spawns,0)
        end)
    end)

    test("actual shape waits for pending IDs and measures owned instance geometry rather than CDO caches",function()
        fixture(function(f)
            truthy(f:prepare().ready); f.id_pending=true
            truthy(f:spawn()); equal(f:ready().phase,"pending"); equal(f.member.instanceGuid,nil)
            equal(f.spawns,1)
            f.id_pending=false
            equal(f:ready().phase,"alive"); equal(f.member.instanceGuid.A,1)
            local ok,result=f:observe()
            truthy(ok,result); equal(result.comparison,"MATCH")
            equal(result.instanceOnly,true); equal(result.spawnQualified,false)
            equal(result.actual.root.radius,30); equal(result.actual.body.halfHeight,95)
            equal(result.actual.mesh.relativeLocation.Z,-33); equal(result.actual.body.authoredOffset.Z,-97)
            equal(result.actual.nav.radius,30); equal(result.actual.nav.height,60); equal(result.actual.movement.grounded,true)
            equal(result.actual.water.cachedInstanceObservation,true); equal(result.actual.water.enteredFlag,0)
            equal(result.actual.measuredProxy.halfHeight,95); equal(result.actual.measuredProxy.centerOffsetZ,62)
            local cleaned,outcome=f.engine:despawn(f.scope,f.member)
            truthy(cleaned,outcome); equal(outcome,"despawned"); equal(f.despawns,1)
        end)
    end)

    test("shape ownership pins the first identified actor even while native initialization is pending",function()
        fixture(function(f,object)
            truthy(f:prepare().ready); f.initializing=true
            truthy(f:spawn()); equal(f:ready().phase,"pending")
            local identity=f.engine:startup_identity(f.member)
            equal(identity.actorAddress,f.actor.address)
            f.actor=object()
            equal(f.engine:inspect(f.member.handle,f.member),false)
            equal(f.spawns,1); equal(f.despawns,0)
        end)
    end)

    test("observation-only shape members still reject out-of-scope stock combat targets",function()
        fixture(function(f)
            truthy(f:prepare().ready); truthy(f:spawn())
            f.engine._combat_targets_scoped=function() return false end
            local state=f:ready()
            equal(state.phase,"escaped"); equal(state.scopeReason,"combat-target")
            local ok,outcome=f.engine:despawn(f.scope,f.member)
            truthy(ok,outcome); equal(outcome,"despawned"); equal(f.despawns,1)
        end)
    end)

    test("shape observation qualifiers require compact vector rotator and scalar contracts",function()
        fixture(function(f)
            truthy(f:prepare().ready)
            for _,method in ipairs({"K2_GetComponentLocation","K2_GetComponentRotation","K2_GetComponentScale"}) do
                local fields=f.signatures["/Script/Engine.SceneComponent:"..method]
                equal(fields.ReturnValue[1],"StructProperty"); equal(fields.ReturnValue[2],0)
            end
            local fields=f.signatures["/Script/Pal.PalCharacterParameterComponent:GetCapsuleRadius"]
            equal(fields.ReturnValue[1],"FloatProperty"); equal(fields.ReturnValue[2],0)
            for _,method in ipairs({"GetInWaterRate","GetWalkableFloorAngleByPriority"}) do
                fields=f.signatures["/Script/Pal.PalCharacterMovementComponent:"..method]
                equal(fields.ReturnValue[1],"FloatProperty"); equal(fields.ReturnValue[2],0)
            end
            fields=f.signatures["/Script/Pal.PalUtility:IsWildNPC"]
            equal(fields.Actor[1],"ObjectProperty"); equal(fields.Actor[2],0)
            equal(fields.ReturnValue[1],"BoolProperty"); equal(fields.ReturnValue[2],8)
            fields=f.signatures["/Script/Pal.PalUtility:GetEngineCollisionChannelByPalObjectType"]
            equal(fields.type[1],"EnumProperty"); equal(fields.type[2],0); equal(fields.ReturnValue[2],1)
            fields=f.signatures["/Script/Engine.PrimitiveComponent:GetCollisionProfileName"]
            equal(fields.ReturnValue[1],"NameProperty"); equal(fields.ReturnValue[2],0)
            equal(f.spawns,0)
        end)
    end)

    test("both initialized samples match derived policies while configuration and no-plane cache remain distinct",function()
        fixture(function(f)
            local placement=f:prepare()
            truthy(placement.ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            for _=1,2 do
                local ok,result=f:observe()
                truthy(ok,result); equal(result.comparison,"MATCH"); equal(result.spawnQualified,false); equal(result.instanceOnly,true)
                equal(result.actual.initializationPolicy.isWildNPC,true)
                equal(result.actual.initializationPolicy.playerPawnChannel,16)
                equal(result.expectedInitialization.nav.templateRadius,-1); equal(result.expectedInitialization.nav.radius,30)
                equal(result.expectedInitialization.nav.height,60); equal(result.expectedInitialization.nav.stepHeight,-1)
                equal(result.expectedInitialization.rootResponse.templateResponse,0)
                equal(result.expectedInitialization.rootResponse.expectedResponse,2)
                equal(result.expectedInitialization.rootResponse.templateProfile,"pawn")
                equal(result.expectedInitialization.rootResponse.expectedProfile,"custom")
                equal(result.expectedInitialization.rootResponse.profileBookkeeping,"EXPECTED_PROFILE_CUSTOMIZATION")
                truthy(math.abs(result.expectedInitialization.slope.expectedFloorZ-0.017452383413910866)<0.0000002)
                equal(result.actual.water.configuredImmersionTarget,0.6499999761581421)
                equal(result.actual.water.computedImmersionRate,0); equal(result.actual.water.cachedPlaneAvailable,false)
                equal(result.actual.water.cachedPlaneStatus,"NO_CACHED_PLANE"); equal(result.actual.water.cachedPlaneZ,nil)
                f.now=f.now+1
            end
            equal(f.cdo.CapsuleComponent.responses[17],0)
            equal(f.cdo.CharacterMovement.WalkableFloorAngle,45)
            equal(placement.plannedGeometry.nav.walkableZ,0.7071067690849304)
        end)
    end)

    test("unexpected initialized response navigation slope and water changes remain mismatches",function()
        for _,change in ipairs({
            function(f) f.playerPawnChannel=17 end,
            function(f) f.actor.CapsuleComponent.responses[18]=1 end,
            function(f) f.actor.CapsuleComponent.responses[17]=0 end,
            function(f) f.actor.CapsuleComponent.collisionEnabled=1 end,
            function(f) f.actor.CapsuleComponent.profileName="Pawn" end,
            function(f) f.actor.CharacterMovement.NavAgentProps.AgentRadius=31 end,
            function(f) f.actor.CharacterMovement.NavAgentProps.AgentHeight=61 end,
            function(f) f.actor.CharacterMovement.NavAgentProps.AgentStepHeight=0 end,
            function(f) f.actor.CharacterMovement.bUpdateNavAgentWithOwnersCollision=false end,
            function(f) f.actor.CharacterMovement.WalkableFloorZ=0.7071067690849304 end,
            function(f) f.actor.CharacterMovement.WalkableFloorAngle=88 end,
            function(f) f.actor.CharacterMovement.InWaterRate=0.8 end,
            function(f) f.computedImmersion=0.65 end,
        }) do
            fixture(function(f)
                truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
                change(f)
                local ok,result=f:observe()
                truthy(ok,result); equal(result.comparison,"MISMATCH"); truthy(#result.reasons>0)
                truthy(f.engine:despawn(f.scope,f.member)); equal(f.despawns,1)
            end)
        end
    end)

    test("initialized policy applicability excludes nonwild profiles and unqualified movement ownership",function()
        for _,change in ipairs({
            function(f) f.wildNPC=false end,
            function(f) f.actor.CapsuleComponent.profileName="Pawn_NoDamageFlyPal" end,
            function(f) f.actor.CapsuleComponent.profileName="PawnParts_NonBlock" end,
            function(f) f.actor.CharacterMovement.CharacterOwner=nil end,
            function(f) f.actor.CharacterMovement.GetClass=function() return {} end end,
            function(f) f.engine.shapeQualification.drySceneQualified=false end,
        }) do
            fixture(function(f)
                truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
                change(f)
                local ok,result=f:observe()
                truthy(ok,result); equal(result.comparison,"UNSUPPORTED")
                truthy(f.engine:despawn(f.scope,f.member)); equal(f.despawns,1)
            end)

        end
        fixture(function(f)
            f.cdo.CharacterMovement.bUpdateNavAgentWithOwnersCollision=false
            f.actor.CharacterMovement.bUpdateNavAgentWithOwnersCollision=false
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            local ok,result=f:observe()
            truthy(ok,result); equal(result.comparison,"UNSUPPORTED"); equal(result.reasons[1],"custom-nav-agent-policy")
        end)
    end)

    test("profile customization requires a changed response and never hides an original policy exclusion",function()
        local responses={}
        for index=1,32 do responses[index]=2 end
        local template={enabled=3,objectType=2,profileName="pawn",responses=responses}
        local model=Native.player_pawn_collision_model(template,16)
        equal(model.profileName,"pawn")
        responses[17]=0
        model=Native.player_pawn_collision_model(template,16)
        equal(model.profileName,"custom"); equal(model.responses[17],2)
        equal(template.profileName,"pawn"); equal(template.responses[17],0)
        for _,profile in ipairs({"Pawn_NoDamageFlyPal","PawnParts_NonBlock"}) do
            fixture(function(f)
                f.cdo.CapsuleComponent.profileName=profile
                local result=f:prepare()
                equal(result.ready,false); equal(result.reason,"shape-template-profile-excluded")
                equal(f.spawns,0)
            end)
        end
    end)

    test("entered water with the unavailable plane sentinel never passes from computed zero",function()
        fixture(function(f)
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            f.actor.CharacterMovement.EnteredWaterFlag=2
            local ok,result=f:observe()
            truthy(ok,result); equal(result.comparison,"UNSUPPORTED"); equal(result.reasons[1],"entered-water-without-cached-plane")
            equal(result.actual.water.computedImmersionRate,0); equal(result.actual.water.cachedPlaneStatus,"NO_CACHED_PLANE")
            truthy(result.expectedInitialization)
        end)
    end)

    test("active slope and PlayerPawn mapping are derived rather than hardcoded to the prior sample",function()
        fixture(function(f)
            f.playerPawnChannel=18
            f.cdo.CapsuleComponent.responses[19]=0
            f.actor.CapsuleComponent.responses[17]=0
            f.actor.CapsuleComponent.responses[19]=2
            f.selectedAngle=60
            f.actor.CharacterMovement.WalkableFloorAngle=60
            f.actor.CharacterMovement.WalkableFloorZ=0.5
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            local ok,result=f:observe()
            truthy(ok,result); equal(result.comparison,"MATCH")
            equal(result.expectedInitialization.rootResponse.playerPawnChannel,18)
            equal(result.expectedInitialization.slope.selectedAngleDegrees,60)
        end)
        fixture(function(f)
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            local ok,result=f:observe()
            truthy(ok,result); equal(result.comparison,"MATCH")
            f.selectedAngle=60
            f.actor.CharacterMovement.WalkableFloorAngle=60
            f.actor.CharacterMovement.WalkableFloorZ=0.5
            ok,result=f:observe()
            truthy(ok,result); equal(result.comparison,"MISMATCH"); equal(result.reasons[1],"initialized-slope-policy-changed")
        end)
    end)

    test("a changed PlayerPawn model between local and final clearance cannot mint a spawn proof",function()
        fixture(function(f)
            f.local_proxy_result=function()
                return {complete=true,localOnly=true,templateOnly=true,spawnQualified=false,classification="proxy-clear",
                    collisionPolicy={playerPawnChannel=17}}
            end
            local result=f:prepare()
            equal(result.ready,false); equal(result.reason,"shape-template-changed"); equal(f.spawns,0)
        end)
    end)

    test("actual geometry changes are mismatches cleaned by exact handle without resizing or movement",function()
        for _,change in ipairs({
            function(f) f.actor.CapsuleComponent.CapsuleHalfHeight=95 end,
            function(f) f.actor.Mesh.RelativeLocation.Z=-97 end,
            function(f) f.actor.StaticCharacterParameterComponent.MeshCapsuleHalfHeight=110 end,
            function(f) f.actor.CharacterMovement.NavAgentProps.AgentHeight=190 end,
            function(f) f.actor.CapsuleComponent.worldScale={X=2,Y=1,Z=1} end,
            function(f) f.actor.Mesh.RelativeScale3D.Z=2 end,
            function(f) f.actor.CapsuleComponent.responses[1]=1 end,
            function(f) f.actor.CharacterMovement.EnteredWaterFlag=1; f.actor.CharacterMovement.WaterPlaneZ=0 end,
            function(f) f.actor.CapsuleComponent.RelativeLocation.Z=f.actor.CapsuleComponent.RelativeLocation.Z+20 end,
        }) do
            fixture(function(f)
                truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
                change(f)
                local ok,result=f:observe()
                truthy(ok,result); equal(result.comparison,"MISMATCH"); truthy(#result.reasons>0)
                local cleaned,outcome=f.engine:despawn(f.scope,f.member)
                truthy(cleaned,outcome); equal(outcome,"despawned"); equal(f.despawns,1)
                for _,method in ipairs(f.calls) do
                    equal(method=="SetCapsuleSize" or method=="SetActorLocation" or method=="PalMoveToLocation"
                        or method=="SetActionClassParameter" or method=="SetupAI",false)
                end
            end)
        end
    end)

    test("unsupported component and water observations retain ownership for verified cleanup",function()
        for _,change in ipairs({
            function(f) f.actor.Mesh.GetOwner=function() return {} end end,
            function(f) f.actor.CharacterMovement.EnteredWaterFlag=nil end,
            function(f) f.actor.Mesh.AttachParent=nil end,
            function(f) f.actor.CharacterMovement.NavAgentProps.AgentStepHeight=nil end,
        }) do
            fixture(function(f)
                truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
                change(f)
                local ok,result=f:observe()
                truthy(ok,result); equal(result.comparison,"UNSUPPORTED")
                truthy(f.engine:despawn(f.scope,f.member)); equal(f.despawns,1)
            end)
        end
        fixture(function(f)
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            f.actor.CharacterMovement.NavAgentProps.AgentStepHeight=nil
            local ok,result=f:observe()
            truthy(ok,result); equal(result.comparison,"UNSUPPORTED")
            equal(result.actual.root.halfHeight,30); equal(result.actual.body.halfHeight,95)
            truthy(require("ped.json").encode(result))
            truthy(f.engine:despawn(f.scope,f.member))
        end)
    end)

    test("an observed stock action is unsupported rather than a no-combat or universal shape certificate",function()
        fixture(function(f,object)
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            f.action=object({IsA=function() return false end})
            local ok,result=f:observe()
            truthy(ok,result); equal(result.comparison,"UNSUPPORTED"); equal(result.reasons[1],"stock-action-present")
            equal(result.actual.root.halfHeight,30)
            truthy(f.engine:despawn(f.scope,f.member)); equal(f.despawns,1)
        end)
    end)

    test("qualified engagement needs two native same-actor receipts and an explicit bounded arm",function()
        fixture(function(f)
            f:qualify_engagement()
            local permit=f.engine.shapeQualification.engagementPermit
            equal(permit.expiresAt,permit.stageStartedAt+60)
            local ok,result=f.engine:engage(f.scope,f.member)
            truthy(ok,result); equal(result,true); equal(f.targets,1); equal(f.dispatched,1)
            equal(f.walking,1); equal(f.runner.state.moved,0); equal(f.spawns,1)
            truthy(f.engine:despawn(f.scope,f.member)); equal(f.despawns,1)
            equal(f.engine.shapeQualification.engagementPermit,nil)
        end,Shape.ENGAGEMENT_CASE)
    end)

    test("zero or one matching shape sample cannot authorize any gameplay entry",function()
        for _,method in ipairs({"engage","startup_travel","configure"}) do
            for samples=0,1 do
                fixture(function(f)
                    truthy(f:prepare().ready); truthy(f:spawn()); local state=f:ready()
                    if samples==1 then
                        local ok,result=f:observe()
                        truthy(ok,result); equal(result.comparison,"MATCH")
                    end
                    local calls=#f.calls
                    local ok
                    if method=="configure" then
                        local record=f.engine.records[f.member.groupId..":1"]
                        ok=pcall(f.engine._configure_movement,f.engine,record,state,f.scope,f.member)
                    else ok=f.engine[method](f.engine,f.scope,f.member) end
                    equal(ok,false); equal(#f.calls,calls); equal(f.dispatched,nil); equal(f.walking,nil)
                end,Shape.ENGAGEMENT_CASE)
            end
        end
    end)

    test("qualified gameplay refuses changed case run artifact contract member and copied receipts",function()
        for _,change in ipairs({
            function(f) f.runner.state.case=Shape.CASE end,
            function(f) f.runner.state.runId="old-run" end,
            function(f) f.runner.state.artifactSha256=string.rep("7",64) end,
            function(f) f.runner.state.experiment=Shape.CONTRACT end,
            function(f) f.runner.state.engagementAuthorization=util.deep_copy(f.runner.state.engagementAuthorization) end,
            function(f) f.member=util.shallow_copy(f.member); f.member.index=2 end,
            function(f) f.member=util.shallow_copy(f.member); f.member.instanceGuid={A=99,B=2,C=3,D=4} end,
            function(f) f.runner.state.shapeObservations=util.deep_copy(f.runner.state.shapeObservations) end,
        }) do
            fixture(function(f)
                f:qualify_engagement()
                change(f)
                equal(f.engine:engage(f.scope,f.member),false)
                equal(f.dispatched,nil); equal(f.walking,nil)
            end,Shape.ENGAGEMENT_CASE)
        end
    end)

    test("cleanup stage changes capture and death permanently revoke the engagement permit",function()
        for _,change in ipairs({
            function(f) f.engine:startup_test_stage_changed(f.runner,"cleanup"); f.runner.state.stage="cleanup" end,
            function(f) f.capturing=true; truthy(f.engine:inspect(f.member.handle,f.member)); f.capturing=false end,
            function(f) f.dead=true; truthy(f.engine:inspect(f.member.handle,f.member)); f.dead=false end,
            function(f) truthy(f.engine:despawn(f.scope,f.member)) end,
        }) do
            fixture(function(f)
                f:qualify_engagement()
                change(f)
                equal(f.engine:engage(f.scope,f.member),false)
                equal(f.dispatched,nil); equal(f.walking,nil)
            end,Shape.ENGAGEMENT_CASE)
        end
    end)

    test("an expired engagement window refuses dispatch without inventing a native fault or blocking cleanup",function()
        fixture(function(f)
            f:qualify_engagement()
            f.now=f.engine.shapeQualification.engagementPermit.expiresAt
            local ok,result=f.engine:engage(f.scope,f.member)
            truthy(ok,result); equal(result,"unavailable")
            equal(f.engine.shapeQualification.engagementPermit,nil); equal(f.engine.bridge.native_fault,nil)
            equal(f.dispatched,nil); equal(f.walking,nil)
            truthy(f.engine:despawn(f.scope,f.member)); equal(f.despawns,1)
        end,Shape.ENGAGEMENT_CASE)
    end)

    test("mismatched or replayed shape evidence cannot arm qualified engagement",function()
        fixture(function(f)
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            local ok,result=f:observe(); truthy(ok,result); equal(result.comparison,"MATCH")
            f.now=f.now+1
            f.actor.CapsuleComponent.CapsuleHalfHeight=95
            ok,result=f:observe(); truthy(ok,result); equal(result.comparison,"MISMATCH")
            equal(f:arm(),false); equal(f.engine.shapeQualification.engagementPermit,nil); equal(f.dispatched,nil)
        end,Shape.ENGAGEMENT_CASE)
        fixture(function(f)
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            f.runner.state.shapeObservations={{comparison="MATCH"},{comparison="MATCH"}}
            equal(f:arm(),false); equal(f.dispatched,nil)
        end,Shape.ENGAGEMENT_CASE)
    end)

    test("qualified engagement retains full parent child and unknown target scope checks",function()
        for _,kind in ipairs({"parent","child","unknown-child"}) do
            fixture(function(f,object)
                f:qualify_engagement()
                local foreign=f:defender_at(99,98)
                local combat=object({IsA=function(_,path)
                    return path=="/Script/AIModule.PawnAction" or path:find("NPC_CombatBase",1,true)~=nil
                end,TargetActor=foreign,CombatModule=object({GetTargetActor=function() return foreign end})})
                if kind=="parent" then
                    f.action=combat
                else
                    f.action=object({IsA=function(_,path) return path=="/Script/AIModule.PawnAction" end,
                        ChildAction=kind=="child" and combat or object({IsA=function() return false end})})
                end
                local ok,result=f.engine:engage(f.scope,f.member)
                truthy(ok,result); equal(result,"unavailable")
                equal(f.engine.shapeQualification.engagementPermit,nil); equal(f.dispatched,nil)
                equal(f.walking,nil)
            end,Shape.ENGAGEMENT_CASE)
        end
    end)

    test("qualified outgoing damage requires the owned attacker and the exact target base",function()
        fixture(function(f)
            f:qualify_engagement()
            local ok,result=f.engine:startup_qualified_damage_target(f.scope,f.member,f.actor,f.defender)
            truthy(ok,result); equal(result.allowed,true); equal(result.active,true)
            ok,result=f.engine:startup_qualified_damage_target(f.scope,f.member,f.actor,f:defender_at(99,8))
            truthy(ok,result); equal(result.allowed,false)
            ok,result=f.engine:startup_qualified_damage_target(f.scope,f.member,{},f.defender)
            truthy(ok,result); equal(result.allowed,false)
        end,Shape.ENGAGEMENT_CASE)
    end)

    test("shape records reject gameplay dispatch and mismatched individual identity before mutation",function()
        for _,method in ipairs({"engage","startup_travel"}) do
            fixture(function(f)
                truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
                local count=#f.calls
                equal(f.engine[method](f.engine,f.scope,f.member),false); equal(#f.calls,count)
                equal(f.actor.parameterComponent.bIsAttackNonCriminal,nil)
            end)
        end
        fixture(function(f)
            truthy(f:prepare().ready); truthy(f:spawn()); equal(f:ready().phase,"alive")
            local member=util.shallow_copy(f.member)
            member.instanceGuid={A=999,B=2,C=3,D=4}
            local count=#f.calls
            equal(f.engine:startup_shape_observation(f.scope,member),false)
            equal(#f.calls,count); equal(f.despawns,0)
        end)
    end)
end
