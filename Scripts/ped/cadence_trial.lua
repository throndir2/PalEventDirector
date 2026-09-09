local util = require("ped.util")
local invoke = require("ped.native_observer").invoke

local Cadence = {}
Cadence.__index = Cadence
Cadence.CASE = "cadenced-engagement"
Cadence.CONTRACT = "hunter-level30-network-sphere-cadence-v1"
Cadence.CAPTURE_POLICY = "stock-networked-spheres-only-v1"
Cadence.SECONDS = 0.1
Cadence.APPLIED = (string.unpack("<f",string.pack("<f",Cadence.SECONDS)))
Cadence.BARRIER = "/Script/Pal.PalPlayerController:SetupInternalForSphere_ToServer"
local SETTER = "/Script/Engine.ActorComponent:SetComponentTickIntervalAndCooldown"
local GETTER = "/Script/Engine.ActorComponent:GetComponentTickInterval"
local ERROR = "Custom assault scope is invalid"
local SPHERES = {}
for _,suffix in ipairs({"","_Ancient1","_Ancient2","_Debug","_Exotic","_Giga","_Legend","_Master","_Mega","_Robbery","_Tera","_Ultimate"}) do
    local name="BP_PalSphere_Body"..suffix
    SPHERES[("/Game/Pal/Blueprint/Weapon/Other/NewPalSphere/"..name.."."..name.."_C"):lower()]=true
end

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

local function checked_validity(object)
    -- Conservative filters hide read errors; identity and disposal evidence must distinguish them.
    local result=object:IsValid()
    if type(result)~="boolean" then error(ERROR,0) end
    return result
end

local function checked_address(object)
    if not checked_validity(object) then error(ERROR,0) end
    local result=object:GetAddress()
    if not finite(result) or not util.is_integer(result) or result<=0 then error(ERROR,0) end
    return result
end

function Cadence.plan_valid(plan)
    if plan.case==Cadence.CASE then
        return plan.experiment==Cadence.CONTRACT and plan.capturePolicy==Cadence.CAPTURE_POLICY and plan.cadenceSeconds==Cadence.SECONDS
    end
    return plan.capturePolicy==nil and plan.cadenceSeconds==nil
end

function Cadence.in_game_thread()
    local predicate=rawget(_G,"IsInGameThread")
    if type(predicate)~="function" then return false end
    local ok,value=pcall(predicate)
    return ok and value==true
end

function Cadence.admission(native,runner)
    local barrier=native.bridge.cadenceBarrier
    return (Cadence.plan_valid(runner.state) and runner.state.case==Cadence.CASE
        and native.bridge.startup_test==runner and native.bridge.delivery_profile=="laboratory-native-test"
        and native.bridge.config.mode=="laboratory" and native.bridge.config.capabilities.startAllInvasions==true
        and barrier and barrier.ready==true and barrier.runner==runner and barrier.native==native
        and barrier.runId==runner.state.runId and barrier.artifact==runner.state.artifactSha256
        and Cadence.in_game_thread())==true
end

function Cadence.register(bridge,native)
    local runner=bridge.startup_test
    if not runner or runner.state.case~=Cadence.CASE then return true end
    if bridge.registeringHooks~=true or bridge.delivery_profile~="laboratory-native-test" or bridge.config.mode~="laboratory"
        or not Cadence.plan_valid(runner.state) or type(rawget(_G,"IsInGameThread"))~="function" then
        return false,"Cadence capture barrier prerequisites are unavailable"
    end
    local qualified=bridge:_native_step("cadence-barrier-layout",function()
        native:_signature(Cadence.BARRIER,{id={"IntProperty",0},target={"ObjectProperty",8},targetCharacter={"ObjectProperty",16}})
        local fn=bridge:_static_find(Cadence.BARRIER)
        if not native.a.valid(fn) or fn:GetFunctionFlags()~=0x00220cc0 then error(ERROR,0) end
        native:_signature(SETTER,{TickInterval={"FloatProperty",0}})
        native:_signature(GETTER,{ReturnValue={"FloatProperty",0}})
    end)
    if not qualified then return false,"Cadence capture barrier layout is unsupported" end
    local ok=bridge:_native_step("cadence-barrier-register",function()
        local registered=bridge:_register_hook("cadence_capture",Cadence.BARRIER,function(...)
            Cadence.capture_pre(bridge,...)
        end,"native-pre")
        if not registered then error(ERROR,0) end
    end)
    if not ok then return false,"Cadence capture barrier registration failed" end
    bridge.cadenceBarrier={ready=true,native=native,runner=runner,runId=runner.state.runId,artifact=runner.state.artifactSha256}
    return true
end

function Cadence.normal_sphere(native,sphere)
    if not native.a.valid(sphere) or not sphere:IsA("/Script/Engine.Actor") then return false end
    local class=sphere:GetClass()
    if not native.a.valid(class) then return false end
    local path=class:GetFullName()
    if type(path)~="string" then return false end
    path=path:gsub("^BlueprintGeneratedClass ",""):gsub("^Class ","")
    return SPHERES[path:lower()]==true
end

function Cadence.capture_pre(bridge,...)
    local native=bridge.custom_engine
    local lease=native and native.cadenceLease
    if not lease or lease.retired then return end
    if not lease:_context() then
        lease:retire("capture-context")
        lease:unresolved("capture-context")
        return
    end
    if not Cadence.in_game_thread() then
        lease:retire("capture-off-thread")
        lease:unresolved("capture-off-thread")
        return
    end
    if select("#",...)~=4 then
        lease:retire("capture-arity")
        lease:unresolved("capture-arity")
        return
    end
    local context,_,sphere,target=...
    local identity_ok,matches=bridge:_native_step("cadence-capture-identity",function()
        local actor=target:get()
        return checked_address(actor)==checked_address(lease.actor)
    end)
    if not identity_ok then
        lease:unresolved("capture-identity-unreadable")
        return
    end
    if not matches then return end
    lease:retire("capture-fence")
    local ok=bridge:_native_step("cadence-capture-pre",function()
        local controller=context:get()
        local body=sphere:get()
        if not native.a.valid(controller) or not controller:IsA("/Script/Pal.PalPlayerController")
            or not Cadence.normal_sphere(native,body)
            or not native.a.same(native:actor_world(controller),lease.world)
            or not native.a.same(native:actor_world(body),lease.world) then
            lease:unresolved("capture-route-unqualified")
            return
        end
        lease.runner.state.failure=lease.runner.state.failure or "cadence-capture-fence"
        lease:release("capture-fence")
    end)
    if not ok then lease:unresolved("capture-native-fault") end
end

function Cadence.new(native,qualification,record)
    local runner=qualification.runner
    if not Cadence.admission(native,runner) or native.cadenceLease or runner.state.cadence.retired then error(ERROR,0) end
    return setmetatable({native=native,runner=runner,qualification=qualification,record=record,world=record.world,
        actor=record.actor,parameter=record.parameter,handle=record.handle,id=util.deep_copy(record.id),
        memberKey=qualification.member.groupId..":"..qualification.member.index,baseId=qualification.member.baseId,
        baseOrdinal=runner.state.baseOrdinal,
        runId=runner.state.runId,artifact=runner.state.artifactSha256,source=runner.state.sourceRevision,
        generation=1,status="NOT_ACQUIRED",active=false,retired=false},Cadence)
end

function Cadence:_context()
    local state=self.runner.state
    return Cadence.plan_valid(state) and state.case==Cadence.CASE and self.native.bridge.startup_test==self.runner
        and state.runId==self.runId and state.artifactSha256==self.artifact and state.sourceRevision==self.source
        and os.getenv("COMPUTERNAME")=="IMOUTO" and os.getenv("PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN")==self.runId
        and os.getenv("PAL_EVENT_DIRECTOR_SOURCE_REVISION")==self.source
        and os.getenv("PAL_EVENT_DIRECTOR_ARTIFACT_SHA256")==self.artifact
        and os.getenv("PAL_EVENT_DIRECTOR_SERVER_BUILD_ID")=="25080279"
        and os.getenv("PAL_EVENT_DIRECTOR_UE4SS_TAG")=="2281fa31" and os.getenv("PAL_EVENT_DIRECTOR_UE4SS_API_VERSION")=="3.0.1"
        and self.native.bridge.delivery_profile=="laboratory-native-test" and self.native.bridge.config.mode=="laboratory"
        and type(state.members)=="table" and #state.members==1 and type(state.members[1])=="table"
        and state.members[1]==self.qualification.member
        and state.members[1].characterId=="BOSS_Hunter_Rifle" and state.members[1].level==30
        and state.members[1].index==1 and state.members[1].slot==1 and state.members[1].baseId==self.baseId
        and state.baseOrdinal==self.baseOrdinal
        and type(state.members[1].groupId)=="string" and state.members[1].groupId..":"..state.members[1].index==self.memberKey
        and self.native.records[self.memberKey]==self.record
end

function Cadence:_record(kind)
    local state=self.runner.state.cadence
    state.status,state.active,state.retired,state.generation=self.status,self.active,self.retired,self.generation
    state.priorSeconds,state.appliedSeconds=self.prior,self.applied
    state.lastObservedSeconds,state.mutated,state.reason=self.lastObserved,self.mutated,self.reason
    if self.recording or self.journalFailed or self.runner.journalFailed then return false end
    self.recording=true
    local called,saved=pcall(self.runner._save,self.runner,"startup_cadence_"..kind)
    local ok=called and saved==true
    self.recording=false
    if not ok then
        self.journalFailed=true
        return self:unresolved("cadence-journal")
    end
    return ok
end

function Cadence:retire(reason)
    if not self.retired then
        self.active,self.retired,self.generation=false,true,self.generation+1
        self.reason=reason
        self.runner.state.cadence.active=false
        self.runner.state.cadence.retired=true
        self.runner.state.cadence.generation=self.generation
    end
    self.qualification:revoke_engagement(reason)
end

function Cadence:unresolved(reason)
    if self.status=="UNRESOLVED" then return false end
    self:retire(reason)
    self.status,self.reason="UNRESOLVED",reason
    self.runner.state.failure=self.runner.state.failure or "cadence-unresolved"
    local bridge=self.native.bridge
    bridge.startup_quarantine="Cadence lease ownership/restoration is unresolved; native work is quarantined."
    if not bridge.native_fault then
        bridge.native_fault="Native operation stopped at cadence-lease [cadence-unresolved]; preserve server logs and restart after investigation. Do not retry."
        bridge.logger:error(bridge.native_fault)
    end
    self.runner.state.cadence.status=self.status
    self:_record("unresolved")
    return false
end

function Cadence:_interval()
    local fn=self.native.bridge:_static_find(GETTER)
    local value=invoke(self.native,"cadence-interval",fn,self.component)
    if not finite(value) or value<0 then error(ERROR,0) end
    return value
end

function Cadence:_set(value,label)
    local fn=self.native.bridge:_static_find(SETTER)
    invoke(self.native,label,fn,self.component,value)
end

function Cadence:acquire(scope,member)
    if not self:_context() or not Cadence.admission(self.native,self.runner) or self.retired or self.attempted then error(ERROR,0) end
    self.attempted=true
    local state,record=self.native:_cadence_acquisition_state(scope,member)
    if state.phase~="alive" or record~=self.record then return self:unresolved("cadence-acquire-ownership") end
    self.controller=state.controller
    self.component=self.native:_call("cadence-component",self.controller,"GetAIActionComponent")
    if not self.native.a.valid(self.component) or not self.component:IsA("/Script/Pal.PalAIActionComponent") then
        return self:unresolved("cadence-component-unavailable")
    end
    local owned,reason=self.native:_cadence_owner(self)
    if not owned then return self:unresolved(reason) end
    local minimum,dilation=self.controller.MinAIActionComponentTickInterval,self.controller.CustomTimeDilation
    if not finite(minimum) or minimum<0 or minimum>Cadence.APPLIED or not finite(dilation) or dilation<=0 then
        self:retire("cadence-controller-policy")
        self.runner.state.failure="cadence-controller-policy"
        self:_record("not-acquired")
        return false
    end
    self.runner.state.cadence.minimumSeconds,self.runner.state.cadence.controllerTimeDilation=minimum,dilation
    self.prior=self:_interval()
    self.mutated=self.prior~=Cadence.APPLIED
    self.status="APPLYING"
    if not self:_record("apply_intent") then return false end
    if self.mutated then self:_set(Cadence.SECONDS,"cadence-apply") end
    if not self:_record("apply_returned") then return false end
    local value=self:_interval()
    self.lastObserved=value
    if value~=Cadence.APPLIED then return self:unresolved("cadence-apply-readback") end
    self.applied,self.active,self.status=value,true,"ACTIVE"
    self.runner.state.cadence.appliedObserved=true
    return self:_record("applied")
end

function Cadence:release(reason)
    self:retire(reason)
    if self.status=="RESTORED" or self.status=="DISPOSED" or self.status=="OVERRIDDEN" then return true end
    if self.status=="UNRESOLVED" then return false end
    if self.recording or self.journalFailed or self.runner.journalFailed then return self:unresolved("cadence-journal") end
    if self.status=="NOT_ACQUIRED" then return self:_record("not-acquired") end
    if not self:_record("retired") then return false end
    if self.native.bridge.native_fault or not Cadence.in_game_thread() or not self:_context() then
        return self:unresolved("cadence-restore-context")
    end
    local ok,released=self.native.bridge:_native_step("cadence-restoration",function()
        if not checked_validity(self.component) then
            self.status="DISPOSED"
            self.runner.state.cadence.disposalVerified=true
            return self:_record("disposed")
        end
        if self.applied==nil then return self:unresolved("cadence-apply-uncertain") end
        local owned,why=self.native:_cadence_owner(self)
        if not owned then return self:unresolved(why) end
        local current=self:_interval()
        self.lastObserved=current
        if current~=self.applied then
            self.status,self.reason="OVERRIDDEN","cadence-external-write"
            self.runner.state.failure=self.runner.state.failure or self.reason
            return self:_record("unknown_write")
        end
        self.status="RESTORING"
        if not self:_record("restore_intent") then return false end
        if current~=self.prior then self:_set(self.prior,"cadence-restore") end
        if not self:_record("restore_returned") then return false end
        self.lastObserved=self:_interval()
        if self.lastObserved~=self.prior then return self:unresolved("cadence-restore-readback") end
        self.status="RESTORED"
        self.runner.state.cadence.restorationVerified=true
        return self:_record("restored")
    end)
    if not ok then return self:unresolved("cadence-restore-native-fault") end
    return released
end

function Cadence:check()
    if not self.active then return false end
    local ok,available=self.native.bridge:_native_step("cadence-check",function()
        if not self:_context() or not Cadence.in_game_thread() then
            return self:unresolved("cadence-check-context")
        end
        local permit=self.qualification.engagementPermit
        if not permit or self.runner.state.stage~="engagement" or self.native.bridge.clock()>=permit.expiresAt then
            self:release("cadence-window-ended")
            return false
        end
        if not checked_validity(self.component) then self:release("cadence-disposed"); return false end
        local owned,reason=self.native:_cadence_owner(self)
        if not owned then return self:unresolved(reason) end
        local current=self:_interval()
        self.lastObserved=current
        if current~=self.applied then self:release("cadence-external-write"); return false end
        local minimum=self.controller.MinAIActionComponentTickInterval
        if not finite(minimum) or minimum<0 or minimum>self.applied then
            self.runner.state.failure="cadence-controller-policy"
            self:release("cadence-controller-policy")
            return false
        end
        return true
    end)
    if not ok then return self:unresolved("cadence-check-native-fault") end
    return available
end

function Cadence.settled(state)
    return state and state.active==false
        and (state.status=="NOT_ACQUIRED" or (state.status=="RESTORED" and state.restorationVerified==true)
            or (state.status=="DISPOSED" and state.disposalVerified==true) or state.status=="OVERRIDDEN")
end

function Cadence.passed(state)
    return state and state.appliedObserved==true and state.active==false and state.retired==true
        and ((state.status=="RESTORED" and state.restorationVerified==true) or (state.status=="DISPOSED" and state.disposalVerified==true))
end

return Cadence
