return function(test,equal,truthy)
    local Cadence=require("ped.cadence_trial")
    local Bridge=require("ped.palworld")
    local Startup=require("ped.startup_test")
    local Config=require("ped.config")
    local util=require("ped.util")
    local function fixture(callback)
        local f={gt=true,interval=10,sets={},events={},reads=0,queued=0,boundaries={},errors={},writes=0,nextAddress=0,hooks={}}
        local function object(values)
            values=values or {}
            f.nextAddress=f.nextAddress+1
            local address=f.nextAddress
            values.IsValid=function(self) return self.disposed~=true end
            values.GetAddress=function() return address end
            return values
        end
        local world=object({IsA=function() return true end})
        local actor=object({world=world,IsA=function(_,name) return name=="/Script/Pal.PalCharacter" or name=="/Script/Engine.Actor" end})
        local controller=object({world=world,MinAIActionComponentTickInterval=0,CustomTimeDilation=1,
            IsA=function(_,name) return name=="/Script/Pal.PalAIController" or name=="/Script/Engine.Actor" end})
        local component=object({world=world,owner=controller,IsA=function(_,name) return name=="/Script/Pal.PalAIActionComponent" end,
            GetOwner=function(self) return self.owner end,GetWorld=function(self) return self.world end})
        f.currentComponent=component
        controller.GetAIActionComponent=function() return f.currentComponent end
        actor.GetController=function() return f.currentController or controller end
        actor.IsActorBeingDestroyed=function() return f.destroying==true end
        actor.IsInitialized=function() return true end
        actor.GetCharacterParameterComponent=function() return object({GetIsCapturedProcessing=function() return f.capturing==true end}) end
        local zero={A=0,B=0,C=0,D=0}
        local id={PlayerUId=util.deep_copy(zero),InstanceId={A=1,B=2,C=3,D=4},DebugName=""}
        local parameter=object({SaveParameter={IsPlayer=false,OwnerPlayerUId=util.deep_copy(zero),OldOwnerPlayerUIds={}},
            GetPalId=function() return id end,GetCharacterID=function() return "BOSS_Hunter_Rifle" end})
        local handle=object({GetIndividualID=function() return id end,TryGetIndividualParameter=function() return parameter end,
            TryGetIndividualActor=function() return actor end})
        local config=Config.defaults()
        config.mode="laboratory"; config.capabilities.startAllInvasions=true
        local bridge=Bridge.new({config=config,clock=function() return 1000 end,logger={
            preflight_breadcrumb=function(_,step) f.boundaries[#f.boundaries+1]=step; return true end,
            info=function() end,error=function(_,message) f.errors[#f.errors+1]=message end,warn=function() end,
        }})
        bridge.delivery_profile="laboratory-native-test"
        local native=bridge:_custom_engine()
        native.a.unwrap=function(v) return v end
        native.a.text=function(v) return v end
        native.actor_world=function(_,which) return which.world end
        native.characterManager=object({GetIndividualHandle=function(_,actual)
            equal(actual.InstanceId.A,1)
            return f.handleMissing and nil or handle
        end})
        native._signature=function(_,path,fields)
            f.signatures=f.signatures or {}; f.signatures[path]=fields
        end
        local getter=setmetatable(object(),{__call=function(_,receiver)
            equal(receiver,component); f.reads=f.reads+1; f.events[#f.events+1]="getter"
            return f.interval
        end})
        local setter=setmetatable(object(),{__call=function(_,receiver,value)
            equal(receiver,component); truthy(f.gt)
            f.sets[#f.sets+1]=value
            f.events[#f.events+1]="setter"
            if #f.sets>1 then equal(f.lease.active,false); equal(f.lease.retired,true); truthy(f.lease.generation>=2) end
            if f.setterFault then error("fixture private setter error") end
            if not f.badReadback then f.interval=(string.unpack("<f",string.pack("<f",value))) end
        end})
        local rpc=object({GetFunctionFlags=function() return f.flags or 0x00220cc0 end})
        bridge._static_find=function(_,path)
            if path==Cadence.BARRIER then return rpc end
            if path=="/Script/Engine.ActorComponent:GetComponentTickInterval" then return getter end
            if path=="/Script/Engine.ActorComponent:SetComponentTickIntervalAndCooldown" then return setter end
            error("unexpected native function")
        end
        bridge.custom_engine=native
        local member={index=1,slot=1,baseId="fixture-base",groupId="startup:cadence-fixture",characterId="BOSS_Hunter_Rifle",level=30}
        local store={sequence=0}
        function store:append(kind,_,state)
            f.writes=f.writes+1
            f.events[#f.events+1]=kind
            if f.throwRecord==kind or f.throwWrites then error("fixture private journal error") end
            if f.failRecord==kind or f.failWrites then return false end
            self.sequence=self.sequence+1
            f.saved=util.deep_copy(state)
            return true
        end
        function store:save_snapshot()
            if f.throwSnapshot then error("fixture private snapshot error") end
            return not f.failSnapshot
        end
        local runner=Startup.new({plan={schemaVersion=1,case=Cadence.CASE,experiment=Cadence.CONTRACT,
            capturePolicy=Cadence.CAPTURE_POLICY,cadenceSeconds=Cadence.SECONDS,runId="cadence-fixture",
            sourceRevision=string.rep("1",40),artifactSha256=string.rep("2",64)},
            store=store,engine=native,clock=bridge.clock,logger=bridge.logger})
        runner.state.members,runner.state.stage,runner.state.stageStartedAt={member},"engagement",1000
        runner.state.mutationStarted,runner.state.spawned,runner.state.initialized=true,1,1
        bridge.startup_test=runner
        local q={runner=runner,member=member,case=Cadence.CASE,engagementPermit={expiresAt=1060},
            ownership_observed=function() end,
            revoke_engagement=function(self,reason) self.revoked=reason; f.events[#f.events+1]="revoked" end}
        local record={actor=actor,parameter=parameter,handle=handle,id=id,world=world,characterId=member.characterId,shapeQualification=q}
        native.records[member.groupId..":1"]=record
        native._cadence_acquisition_state=function()
            truthy(f.twoMatches~=false,"cadence bypassed shape receipts")
            return {phase="alive",actor=actor,controller=controller,parameter=parameter},record
        end
        local previousGT,previousQueue,previousGetenv,previousRegister=_G.IsInGameThread,_G.ExecuteInGameThread,os.getenv,_G.RegisterHook
        _G.IsInGameThread=function() f.events[#f.events+1]="thread"; return f.gt end
        _G.ExecuteInGameThread=function() f.queued=f.queued+1; error("capture restore queued") end
        local env={COMPUTERNAME="IMOUTO",PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN=runner.state.runId,
            PAL_EVENT_DIRECTOR_SOURCE_REVISION=runner.state.sourceRevision,PAL_EVENT_DIRECTOR_ARTIFACT_SHA256=runner.state.artifactSha256,
            PAL_EVENT_DIRECTOR_SERVER_BUILD_ID="25080279",PAL_EVENT_DIRECTOR_UE4SS_TAG="2281fa31",PAL_EVENT_DIRECTOR_UE4SS_API_VERSION="3.0.1"}
        os.getenv=function(key) return env[key] end
        _G.RegisterHook=function(path,pre,post)
            equal(bridge.registeringHooks,true)
            f.hooks[path]={pre=pre,post=post}
            if path==Cadence.BARRIER then f.pre,f.post=pre,post
            else
                local observer=require("ped.projectile_observer")
                truthy(path==observer.CREATED or path==observer.HIT)
            end
            return f.badIDs and 1 or 11,f.badIDs and 1 or 12
        end
        f.native,f.bridge,f.runner,f.actor,f.controller,f.component,f.parameter,f.member=native,bridge,runner,actor,controller,component,parameter,member
        f.handle=handle
        f.env=env
        function f:register()
            bridge.registeringHooks=true
            local ok,reason=Cadence.register(bridge,native)
            bridge.registeringHooks=false
            return ok,reason
        end
        function f:acquire()
            if not bridge.cadenceBarrier then truthy(self:register()) end
            self.lease=Cadence.new(native,q,record)
            native.cadenceLease=self.lease
            local ok,result=bridge:_native_step("fixture-cadence-acquire",function() return self.lease:acquire({},member) end)
            truthy(ok,result); truthy(result)
        end
        function f:sphere(name)
            name=name or "BP_PalSphere_Body"
            return object({world=world,IsA=function(_,path) return path=="/Script/Engine.Actor" end,
                GetClass=function() return object({GetFullName=function()
                    return "BlueprintGeneratedClass /Game/Pal/Blueprint/Weapon/Other/NewPalSphere/"..name.."."..name.."_C"
                end}) end})
        end
        function f:capture(target,sphere,capturer)
            local function remote(value,label)
                return {get=function() self.events[#self.events+1]=label; return value end}
            end
            local pc=capturer or object({world=world,IsA=function(_,path) return path=="/Script/Pal.PalPlayerController" end})
            return self.pre(remote(pc,"capturer"),{get=function() error("capture id was read") end},
                remote(sphere or self:sphere(),"sphere"),remote(target or actor,"target"))
        end
        local ok,reason=xpcall(function() callback(f,object) end,debug.traceback)
        _G.IsInGameThread,_G.ExecuteInGameThread,os.getenv,_G.RegisterHook=previousGT,previousQueue,previousGetenv,previousRegister
        truthy(ok,reason)
    end

    local function projectiles(f,object)
        local Observer=require("ped.projectile_observer")
        local world=f.lease.world
        local function class(name,full)
            return object({GetFName=function() return {ToString=function() return name end} end,
                GetFullName=function() return full or "Class /Script/Engine."..name end})
        end
        local weaponClass=class("BP_AssaultRifle_NPC_C",Observer.RIFLE)
        local weapon=object({world=world,GetClass=function() return weaponClass end})
        local bulletClass=class("BP_NormalBullet_NPC_C",Observer.BULLET)
        local bullet=object({world=world,isDamageable=true,GetClass=function() return bulletClass end,
            GetOwner=function() return f.bulletOwner or weapon end,
            GetActorEnableCollision=function() return true end,GetWeaponDamage=function() return 100 end})
        local target=object({world=world})
        local function primitive(owner,name,kind)
            local which=class(name)
            return object({Mobility=2,IsA=function(_,path) return path=="/Script/Engine.PrimitiveComponent" end,
                GetClass=function() return which end,GetOwner=function() return owner end,GetWorld=function() return world end,
                GetGenerateOverlapEvents=function() return true end,GetCollisionEnabled=function() return 3 end,
                GetCollisionObjectType=function() return kind end,GetCollisionResponseToChannel=function() return 1 end})
        end
        local source=primitive(bullet,"SphereComponent",1)
        local receiver=primitive(target,"PalBodyPartsCapsuleComponent",2)
        bullet.RootComponent=source
        bullet.ProjectileMovement=object({UpdatedComponent=source,Velocity={X=12000,Y=0,Z=0},
            bSimulationEnabled=true,bSweepCollision=true,bUpdateOnlyIfRendered=false,
            IsA=function(_,path) return path=="/Script/Pal.PalProjectileMovementComponent" end,
            GetOwner=function() return bullet end,GetWorld=function() return world end,
            IsActive=function() return true end,IsComponentTickEnabled=function() return true end,
            GetComponentTickInterval=function() return 0 end})
        f.native.utility=object({IsApplicableDamage=function(_,causer,other,component)
            equal(causer,bullet); equal(other,target); equal(component,receiver)
            return true
        end})
        f.native._simulation_weapon=function(_,actor,which)
            equal(actor,f.actor); equal(which,world)
            return weapon
        end
        f.native._simulation_target=function() return target end
        f.native._simulation_receiver=function(_,actor)
            return actor==target and target or nil,"unscoped-receiver"
        end
        f.native._character_simulation=function(_,_,which,component)
            equal(which,world); equal(component,source)
            f.bodySamples=(f.bodySamples or 0)+1
            if f.nestedCreation then f:createBulletEvent() end
            return {available=true,bodyPartsSampled=true,bodyPartsComplete=true,bodyParts={{overlapEvents=false}}}
        end
        f.bullet,f.projectileWeapon,f.projectileSource,f.projectileTarget,f.projectileReceiver=bullet,weapon,source,target,receiver
        local function remote(value) return {get=function() return value end} end
        function f:createBulletEvent(value,owner)
            if value==nil then value=bullet elseif value==false then value=nil end
            return self.hooks[Observer.CREATED].post(remote(owner or weapon),remote(value))
        end
        function f:hitBulletEvent(value)
            return self.hooks[Observer.HIT].pre(remote(value or bullet),remote(source),remote(target),remote(receiver),
                {get=function() error("unsafe HitResult decode") end})
        end
        return Observer
    end

    test("cadence contract requires the explicit capture restriction and fixed interval",function()
        equal(Cadence.plan_valid({case=Cadence.CASE,experiment=Cadence.CONTRACT}),false)
        truthy(Cadence.plan_valid({case=Cadence.CASE,experiment=Cadence.CONTRACT,capturePolicy=Cadence.CAPTURE_POLICY,cadenceSeconds=0.1}))
        equal(Cadence.plan_valid({case="qualified-engagement",capturePolicy=Cadence.CAPTURE_POLICY,cadenceSeconds=0.1}),false)
        fixture(function(f)
            equal(Cadence.register(f.bridge,f.native),false)
            equal(Cadence.admission(f.native,f.runner),false); equal(#f.sets,0)
            f.badIDs=true
            equal(f:register(),false); equal(f.bridge.cadenceBarrier,nil)
        end)
    end)

    test("capture barrier is registered as a native four-argument prehook with exact compact layouts",function()
        fixture(function(f)
            truthy(f:register())
            truthy(f.pre); truthy(f.post); equal(f.post(),nil)
            local fields=f.signatures[Cadence.BARRIER]
            equal(fields.id[1],"IntProperty"); equal(fields.id[2],0)
            equal(fields.target[2],8); equal(fields.targetCharacter[2],16); equal(fields.ReturnValue,nil)
            fields=f.signatures["/Script/Engine.ActorComponent:SetComponentTickIntervalAndCooldown"]
            equal(fields.TickInterval[1],"FloatProperty"); equal(fields.TickInterval[2],0)
            fields=f.signatures["/Script/Pal.PalCharacter:GetActiveActorFlag"]
            equal(fields.ReturnValue[1],"BoolProperty"); equal(fields.ReturnValue[2],0)
            fields=f.signatures["/Script/Engine.CharacterMovementComponent:GetLastUpdateLocation"]
            equal(fields.ReturnValue[1],"StructProperty"); equal(fields.ReturnValue[2],0)
            truthy(f.native.simulationObservationQualified)
            equal(#f.sets,0)
        end)

        fixture(function(f)
            f.flags=0x400
            equal(f:register(),false); equal(f.pre,nil); equal(#f.sets,0)
        end)
    end)

    test("Bridge registers the cadence barrier before scheduling any startup NPC work",function()
        fixture(function(f)
            local previousConsole,previousLoop=_G.RegisterConsoleCommandGlobalHandler,_G.LoopInGameThreadWithDelay
            _G.RegisterConsoleCommandGlobalHandler=function() return true end
            _G.LoopInGameThreadWithDelay=function(_,callback)
                truthy(f.pre); truthy(f.bridge.cadenceBarrier.ready)
                equal(#f.sets,0); f.poll=callback; return 1
            end
            for _,key in ipairs({"chatCommands","observeCombat","observeInvasions","substituteBountyMembers"}) do
                f.bridge.config.capabilities[key]=false
            end
            local ok,reason=pcall(function()
                local registered,why=f.bridge:register()
                truthy(registered,why); truthy(f.bridge.cadenceBarrier.ready); truthy(f.poll)
                equal(f.bridge.registeringHooks,false); equal(#f.sets,0)
            end)
            _G.RegisterConsoleCommandGlobalHandler,_G.LoopInGameThreadWithDelay=previousConsole,previousLoop
            truthy(ok,reason)
        end)
    end)

    test("cadence applies once and compares float32 readback without resetting cooldown on polls",function()
        fixture(function(f)
            f:acquire()
            equal(#f.sets,1); equal(f.interval,Cadence.APPLIED); equal(f.lease.prior,10)
            for _=1,3 do truthy(f.lease:check()) end
            equal(#f.sets,1)
            truthy(f.lease:release("cleanup"))
            equal(#f.sets,2); equal(f.interval,10); equal(f.runner.state.cadence.status,"RESTORED")
            truthy(Cadence.passed(f.runner.state.cadence))
            truthy(f.lease:release("duplicate")); equal(#f.sets,2)
        end)
        fixture(function(f)
            f.interval=Cadence.APPLIED
            f:acquire(); equal(#f.sets,0)
            truthy(f.lease:release("cleanup")); equal(#f.sets,0)
            equal(f.runner.state.cadence.status,"RESTORED")
        end)
    end)

    test("normal-sphere pretransfer restores inline after retirement and never rearms on duplicates",function()
        fixture(function(f)
            f:acquire()
            local before=#f.events
            equal(f:capture(),nil)
            equal(f.interval,10); equal(#f.sets,2); equal(f.lease.active,false); equal(f.lease.retired,true)
            equal(f.runner.state.cadence.status,"RESTORED"); equal(f.queued,0)
            local retired,setter
            for index=before+1,#f.events do
                if f.events[index]=="revoked" then retired=retired or index end
                if f.events[index]=="setter" then setter=index end
            end
            truthy(retired and setter and retired<setter)
            local generation=f.lease.generation
            f:capture(); equal(f.lease.generation,generation); equal(#f.sets,2)
            equal(pcall(f.lease.acquire,f.lease,{},f.member),false)
        end)
    end)

    test("unrelated capture targets and inactive cases never touch capture arguments or cadence",function()
        fixture(function(f,object)
            f:acquire()
            f:capture(object(),f:sphere("Unqualified"),object())
            equal(f.lease.active,true); equal(#f.sets,1)
            local count=#f.events
            f.native.cadenceLease=nil
            Cadence.capture_pre(f.bridge)
            equal(#f.events,count); equal(#f.sets,1)
        end)

        test("capture barrier accepts only the twelve recovered exact sphere body classes",function()
            fixture(function(f,object)
                for _,suffix in ipairs({"","_Ancient1","_Ancient2","_Debug","_Exotic","_Giga","_Legend","_Master","_Mega","_Robbery","_Tera","_Ultimate"}) do
                    truthy(Cadence.normal_sphere(f.native,f:sphere("BP_PalSphere_Body"..suffix)))
                end
                equal(Cadence.normal_sphere(f.native,f:sphere("BP_PalSphere_Body_Custom")),false)
                local sphere=f:sphere()
                sphere.GetClass=function() return object({GetFullName=function()
                    return "BlueprintGeneratedClass /Game/Other/BP_PalSphere_Body.BP_PalSphere_Body_C"
                end}) end
                equal(Cadence.normal_sphere(f.native,sphere),false)
            end)
        end)
    end)

    test("capture target identity failures cannot masquerade as unrelated captures",function()
        for _,kind in ipairs({"validity-throws","validity-nonboolean","address-throws","address-noninteger"}) do
            fixture(function(f)
                f:acquire()
                local failedReads=0
                if kind:match("^validity") then
                    f.actor.IsValid=function()
                        failedReads=failedReads+1
                        if kind=="validity-throws" then error("fixture private target validity error") end
                        return nil
                    end
                else
                    f.actor.GetAddress=function()
                        failedReads=failedReads+1
                        if kind=="address-throws" then error("fixture private target address error") end
                        return "unreadable-address"
                    end
                end
                equal(f:capture(),nil)
                equal(failedReads,1); equal(f.lease.active,false); equal(f.lease.retired,true)
                equal(f.runner.state.cadence.status,"UNRESOLVED")
                truthy(f.bridge.native_fault); truthy(f.bridge.startup_quarantine)
                equal(f.interval,Cadence.APPLIED); equal(#f.sets,1)
                equal(Cadence.passed(f.runner.state.cadence),false)
                local boundaries=#f.boundaries
                f:capture(); f.runner:tick(); f.bridge:unregister()
                equal(failedReads,1); equal(#f.boundaries,boundaries)
                truthy(f.runner.stopped); equal(f.runner.state.cleanupComplete,false)
                for _,message in ipairs(f.errors) do equal(message:find("fixture private",1,true),nil) end
            end)
        end
    end)

    test("capture identity matches distinct valid wrappers for the same native actor",function()
        fixture(function(f,object)
            f:acquire()
            local target=object()
            target.GetAddress=f.actor.GetAddress
            f:capture(target)
            equal(f.runner.state.cadence.status,"RESTORED")
            equal(f.interval,10); equal(#f.sets,2)
        end)
    end)

    test("offthread unknown-family and invalid-capturer entries revoke without a foreign setter",function()
        for _,kind in ipairs({"offthread","family","context","arity"}) do
            fixture(function(f,object)
                f:acquire()
                if kind=="offthread" then f.gt=false end
                if kind=="arity" then f.pre({})
                elseif kind=="family" then f:capture(nil,f:sphere("BP_CustomSphere"))
                elseif kind=="context" then f:capture(nil,nil,object({IsA=function() return false end}))
                else f:capture() end
                equal(f.lease.active,false); equal(#f.sets,1)
                equal(f.runner.state.cadence.status,"UNRESOLVED")
                truthy(f.bridge.startup_quarantine); equal(f.queued,0)
            end)
        end
    end)

    test("cadence restoration never follows a replaced controller component or captured owner",function()
        for _,kind in ipairs({"controller","component","captured","processing","world"}) do
            fixture(function(f,object)
                f:acquire()
                if kind=="controller" then f.currentController=object() end
                if kind=="component" then f.currentComponent=object() end
                if kind=="captured" then f.parameter.SaveParameter.OwnerPlayerUId.A=9 end
                if kind=="processing" then f.capturing=true end
                if kind=="world" then f.component.world=object() end
                equal(f.lease:release("cleanup"),false); equal(#f.sets,1)
                equal(f.runner.state.cadence.status,"UNRESOLVED"); equal(Cadence.passed(f.runner.state.cadence),false)
                truthy(f.bridge.native_fault)
                local touched=false
                equal(f.bridge:_native_step("fixture-after-unresolved",function() touched=true end),false)
                equal(touched,false)
            end)
        end
    end)

    test("unexpected interval writers are not clobbered and the first cadence trial stops",function()
        fixture(function(f)
            f:acquire(); f.interval=5
            equal(f.lease:check(),false); equal(f.interval,5); equal(#f.sets,1)
            equal(f.runner.state.cadence.status,"OVERRIDDEN")
            equal(f.runner.state.failure,"cadence-external-write")
            truthy(Cadence.settled(f.runner.state.cadence)); equal(Cadence.passed(f.runner.state.cadence),false)
        end)
    end)

    test("expired dead and normal cleanup use the same guarded old-component restoration",function()
        for _,reason in ipairs({"expired","ownership-dead","cleanup"}) do
            fixture(function(f)
                f:acquire(); truthy(f.lease:release(reason)); equal(f.interval,10); equal(#f.sets,2)
                equal(f.runner.state.cadence.status,"RESTORED")
            end)
        end
        fixture(function(f)
            f:acquire(); f.component.disposed=true
            truthy(f.lease:release("ownership-dead")); equal(#f.sets,1)
            equal(f.runner.state.cadence.status,"DISPOSED"); truthy(f.runner.state.cadence.disposalVerified)
        end)
    end)

    test("capture validity failures cannot become verified component disposal",function()
        for _,kind in ipairs({"throws","nonboolean"}) do
            fixture(function(f)
                f:acquire()
                local probes=0
                f.component.IsValid=function()
                    probes=probes+1
                    if kind=="throws" then error("fixture private validity error") end
                    return nil
                end
                equal(f:capture(),nil)
                equal(probes,1); equal(#f.sets,1); equal(f.interval,Cadence.APPLIED)
                equal(f.runner.state.cadence.status,"UNRESOLVED")
                equal(f.runner.state.cadence.disposalVerified,nil)
                equal(Cadence.passed(f.runner.state.cadence),false)
                truthy(f.bridge.native_fault); truthy(f.bridge.startup_quarantine)
                local boundaries=#f.boundaries
                f.runner:tick()
                truthy(f.runner.stopped); equal(f.runner.state.status,"failed")
                equal(f.runner.state.cleanupComplete,false)
                equal(f.lease:release("duplicate"),false)
                f.bridge:unregister()
                equal(probes,1); equal(#f.boundaries,boundaries); equal(#f.sets,1)
                for _,message in ipairs(f.errors) do equal(message:find("fixture private",1,true),nil) end
            end)
        end
    end)

    test("cadence polling does not retry a failed validity probe during release",function()
        fixture(function(f)
            f:acquire()
            local probes=0
            f.component.IsValid=function() probes=probes+1; error("fixture private validity error") end
            equal(f.lease:check(),false)
            equal(probes,1); equal(#f.sets,1); equal(f.interval,Cadence.APPLIED)
            equal(f.runner.state.cadence.status,"UNRESOLVED"); truthy(f.bridge.native_fault)
            equal(Cadence.passed(f.runner.state.cadence),false)
        end)
    end)

    test("tick cleanup ownership faults retire once and finish halt without native reentry",function()
        fixture(function(f)
            f:acquire()
            local ownershipReads=0
            f.parameter.SaveParameter=nil
            setmetatable(f.parameter,{__index=function(_,key)
                if key=="SaveParameter" then
                    ownershipReads=ownershipReads+1
                    error("fixture private ownership error")
                end
            end})
            f.lease:retire("fixture-window-ended")
            local called,reason=pcall(f.runner.tick,f.runner)
            truthy(called,reason); equal(ownershipReads,1)
            truthy(f.runner.stopped); equal(f.runner.state.status,"failed")
            equal(f.runner.state.cleanupComplete,false); equal(f.saved.status,"failed")
            equal(f.runner.state.cadence.status,"UNRESOLVED")
            equal(f.saved.cadence.status,"UNRESOLVED")
            truthy(f.bridge.native_fault); equal(Cadence.passed(f.runner.state.cadence),false)
            equal(f.interval,Cadence.APPLIED); equal(#f.sets,1)
            local boundaries=#f.boundaries
            f.runner:tick()
            equal(f.native:startup_test_stage_changed(f.runner,"failed"),false)
            f.bridge:unregister()
            equal(ownershipReads,1); equal(#f.boundaries,boundaries); equal(#f.sets,1)
        end)
    end)

    test("cadence journal failures finish the real runner without recursive restoration",function()
        for _,kind in ipairs({"failWrites","throwWrites","failSnapshot","throwSnapshot"}) do
            fixture(function(f)
                f:acquire()
                f[kind]=true
                f.lease:retire("fixture-window-ended")
                local boundaries=#f.boundaries
                local called,reason=pcall(f.runner.tick,f.runner)
                truthy(called,reason); truthy(f.runner.stopped)
                equal(f.runner.state.status,"failed"); equal(f.runner.state.cleanupComplete,false)
                equal(f.runner.state.cadence.status,"UNRESOLVED")
                equal(Cadence.passed(f.runner.state.cadence),false)
                equal(f.interval,Cadence.APPLIED); equal(#f.sets,1); equal(#f.boundaries,boundaries)
                local writes=f.writes
                f.runner:tick()
                f.bridge:unregister()
                equal(f.writes,writes); equal(#f.boundaries,boundaries)
                for _,message in ipairs(f.errors) do equal(message:find("fixture private",1,true),nil) end
            end)
        end
    end)

    test("owned-state restoration failures stop inspect and the current startup tick",function()
        for _,kind in ipairs({"native","journal"}) do
            fixture(function(f)
                f:acquire()
                local readsAfterStop,observations=0,0
                local getAddress,isValid=f.actor.GetAddress,f.actor.IsValid
                f.actor.GetAddress=function(...)
                    if f.bridge.native_fault or f.runner.stopped then readsAfterStop=readsAfterStop+1 end
                    return getAddress(...)
                end
                f.actor.IsValid=function(...)
                    if f.bridge.native_fault or f.runner.stopped then readsAfterStop=readsAfterStop+1 end
                    return isValid(...)
                end
                f.native._read_owned_state=function() return {phase="escaped",actor=f.actor} end
                local observe=f.native.startup_combat_observation
                f.native.startup_combat_observation=function(...)
                    observations=observations+1
                    return observe(...)
                end
                if kind=="native" then
                    f.component.IsValid=function() error("fixture private restoration error") end
                else
                    f.failRecord="startup_cadence_retired"
                end
                f.runner.state.qualifiedEngagementArmed=true
                f.runner.runtime={{actor=f.actor,handle=f.handle}}
                f.runner.scopes={{}}
                f.member.instanceGuid,f.member.playerGuid=f.lease.id.InstanceId,f.lease.id.PlayerUId
                f.member.actorAddress="fixture-actor"
                local called,reason=pcall(f.runner.tick,f.runner)
                truthy(called,reason); truthy(f.runner.stopped)
                equal(f.runner.state.status,"failed"); equal(f.runner.state.cleanupComplete,false)
                equal(f.runner.state.cadence.status,"UNRESOLVED")
                equal(readsAfterStop,0); equal(observations,0)
                equal(f.interval,Cadence.APPLIED); equal(#f.sets,1)
                truthy(f.bridge.native_fault)
                local boundaries=#f.boundaries
                f.runner:tick(); f.bridge:unregister()
                equal(readsAfterStop,0); equal(observations,0); equal(#f.boundaries,boundaries)
            end)
        end
    end)

    test("restore readback failure and post-apply faults preserve unresolved recovery",function()
        fixture(function(f)
            f:acquire(); f.badReadback=true
            equal(f.lease:release("cleanup"),false)
            equal(f.runner.state.cadence.status,"UNRESOLVED"); equal(Cadence.settled(f.runner.state.cadence),false)
        end)
        fixture(function(f)
            f:acquire(); f.bridge.native_fault="fixture-native-fault"
            local reads=f.reads
            equal(f.lease:release("failed"),false); equal(f.reads,reads); equal(#f.sets,1)
            equal(f.runner.state.cadence.status,"UNRESOLVED")
        end)
        fixture(function(f)
            f:acquire()
            f.failRecord="startup_cadence_restore_intent"
            equal(f.lease:release("cleanup"),false)
            equal(#f.sets,1); equal(f.runner.state.cadence.status,"UNRESOLVED")
        end)
    end)

    test("minimum policy and changed run cannot acquire a cadence lease",function()
        fixture(function(f)
            truthy(f:register()); f.controller.MinAIActionComponentTickInterval=0.2
            local q=f.native.records["startup:cadence-fixture:1"].shapeQualification
            f.lease=Cadence.new(f.native,q,f.native.records["startup:cadence-fixture:1"])
            f.native.cadenceLease=f.lease
            equal(f.lease:acquire({},f.member),false); equal(#f.sets,0)
            equal(f.runner.state.cadence.status,"NOT_ACQUIRED")
        end)
        fixture(function(f)
            f:acquire(); f.env.PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN="different-run"
            equal(f.lease:check(),false); equal(#f.sets,1); equal(f.runner.state.cadence.status,"UNRESOLVED")
        end)
    end)

    test("natural projectile witnesses use creation post and hit pre without retaining native references",function()
        fixture(function(f,object)
            f:acquire()
            local Observer=projectiles(f,object)
            equal(f.hooks[Observer.CREATED].pre(),nil)
            equal(f.hooks[Observer.HIT].post(),nil)
            f:hitBulletEvent()
            f:createBulletEvent()
            local evidence=f.runner.state.projectileObservation
            equal(#evidence.creations,1); equal(#evidence.hits,1)
            equal(evidence.creations[1].phase,"created-notification-post")
            equal(evidence.creations[1].projectile.speed,12000)
            equal(evidence.creations[1].projectile.updateOnlyIfRendered,false)
            equal(evidence.hits[1].phase,"hit-native-pre")
            equal(evidence.hits[1].contact,"exact-base-character")
            equal(evidence.hits[1].applicable,true); equal(evidence.hits[1].receiver.pairResponse,1)
            equal(evidence.hits[1].independentOfCreationSamples,true)
            equal(evidence.hits[1].damageSetupFinalized,"unknown")
            equal(evidence.laterMotionSampled,false); equal(#f.sets,1)
            local function scalars(value)
                truthy(type(value)~="function" and type(value)~="userdata")
                if type(value)=="table" then for _,child in pairs(value) do scalars(child) end end
            end
            scalars(evidence)
        end)
    end)

    test("projectile observers cap independent samples and reject foreign or reused ownership",function()
        fixture(function(f,object)
            f:acquire()
            local Observer=projectiles(f,object)
            f:createBulletEvent(nil,object())
            equal(#f.runner.state.projectileObservation.creations,0)
            f.bulletOwner=object()
            f:hitBulletEvent()
            equal(#f.runner.state.projectileObservation.hits,0)
            f.bulletOwner=nil
            for _=1,5 do f:createBulletEvent(); f:hitBulletEvent() end
            local evidence=f.runner.state.projectileObservation
            equal(#evidence.creations,3); equal(#evidence.hits,3)
            truthy(evidence.creationSamplingCapped); truthy(evidence.hitSamplingCapped)
            local boundaries=#f.boundaries
            f.hooks[Observer.CREATED].post({}, {})
            f.hooks[Observer.HIT].pre({}, {}, {}, {}, {})
            equal(#f.boundaries,boundaries); equal(#f.sets,1)
        end)
    end)

    test("projectile creation reservations bound nested observations and preserve invalid results",function()
        fixture(function(f,object)
            f:acquire(); projectiles(f,object)
            f.nestedCreation=true
            f:createBulletEvent()
            equal(#f.runner.state.projectileObservation.creations,3)
            equal(f.native.projectileObserver.creationAttempts,3); equal(#f.sets,1)
        end)
        fixture(function(f,object)
            f:acquire(); projectiles(f,object)
            f:createBulletEvent(false)
            local record=f.runner.state.projectileObservation.creations[1]
            equal(record.bulletAvailable,false); equal(record.projectile,nil)
            equal(f.bodySamples,nil); equal(f.bridge.native_fault,nil)
        end)
    end)

    test("projectile read faults and off-thread callbacks retire the lease without more native work",function()
        for _,kind in ipairs({"read","thread","journal"}) do
            fixture(function(f,object)
                f:acquire(); projectiles(f,object)
                if kind=="read" then f.bullet.GetOwner=function() error("fixture private projectile error") end end
                if kind=="thread" then f.gt=false end
                if kind=="journal" then f.failRecord="startup_projectile_creation" end
                f:createBulletEvent()
                equal(f.lease.active,false); equal(f.lease.status,"UNRESOLVED")
                truthy(f.bridge.native_fault); equal(Cadence.passed(f.runner.state.cadence),false)
                local boundaries=#f.boundaries
                f:createBulletEvent(); f:hitBulletEvent()
                equal(#f.boundaries,boundaries); equal(#f.sets,1)
                for _,message in ipairs(f.errors) do equal(message:find("fixture private",1,true),nil) end
            end)
        end
    end)
end
