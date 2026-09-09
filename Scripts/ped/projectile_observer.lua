local json=require("ped.json")
local util=require("ped.util")

local Observer={}
Observer.__index=Observer
Observer.CREATED="/Script/Pal.PalWeaponBase:OnCreatedBullet"
Observer.HIT="/Script/Pal.PalBullet:OnHit"
Observer.LIMIT=3
Observer.RIFLE="BlueprintGeneratedClass /Game/Pal/Blueprint/Weapon/NPCWeapon/BP_AssaultRifle_NPC.BP_AssaultRifle_NPC_C"
Observer.BULLET="BlueprintGeneratedClass /Game/Pal/Blueprint/Weapon/Bullet/BP_NormalBullet_NPC.BP_NormalBullet_NPC_C"
local ERROR="Custom assault scope is invalid"

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

local function vector(value)
    local result={}
    for _,axis in ipairs({"X","Y","Z"}) do
        local number=value[axis]
        if not finite(number) then error(ERROR,0) end
        result[axis]=number
    end
    return result
end

function Observer.register(bridge,native,cadence)
    local runner=bridge.startup_test
    if not runner or runner.state.case~=cadence.CASE then return true end
    if bridge.registeringHooks~=true then return false end
    local observer=setmetatable({bridge=bridge,native=native,cadence=cadence,runner=runner,ready=false,creationAttempts=0,hitAttempts=0,
        state={creationLimit=Observer.LIMIT,hitLimit=Observer.LIMIT,independentSamples=true,laterMotionSampled=false,
            creations=json.array(),hits=json.array()}},Observer)
    local ok=bridge:_native_step("projectile-observer-layout",function()
        native:_signature(Observer.CREATED,{Bullet={"ObjectProperty",0}})
        native:_signature(Observer.HIT,{
            HitComp={"ObjectProperty",0},OtherActor={"ObjectProperty",8},OtherComp={"ObjectProperty",16},Hit={"StructProperty",24},
        })
        native:_signature("/Script/Pal.PalBullet:GetWeaponDamage",{ReturnValue={"IntProperty",0}})
        native:_signature("/Script/Pal.PalUtility:IsApplicableDamage",{
            Causer={"ObjectProperty",0},Receiver={"ObjectProperty",8},ReceivedComponent={"ObjectProperty",16},
            ReturnValue={"BoolProperty",24},
        })
    end)
    if not ok then return false end
    ok=bridge:_native_step("projectile-observer-register",function()
        local hooks={
            {"projectile_created",Observer.CREATED,function(...) observer:created(...) end},
            {"projectile_hit",Observer.HIT,function(...) observer:hit(...) end,"native-pre"},
        }
        for _,hook in ipairs(hooks) do
            local registered=bridge:_register_hook(hook[1],hook[2],hook[3],hook[4])
            local ids=bridge.hook_ids[hook[1]]
            if not registered or not ids or not util.is_integer(ids.pre) or not util.is_integer(ids.post)
                or ids.pre<0 or ids.post<0 or ids.pre==ids.post then error(ERROR,0) end
        end
        observer.ready=true
        observer.state.registrationReady=true
        native.projectileObserver=observer
        runner.state.projectileObservation=observer.state
        if not runner:_save("startup_projectile_observer_ready") then error(ERROR,0) end
    end)
    return ok
end

function Observer:_lease()
    local lease=self.native.cadenceLease
    if not self.ready or self.bridge.native_fault or self.bridge.startup_test~=self.runner or self.runner.stopped
        or self.runner.state.stage~="engagement" or not lease or lease.runner~=self.runner
        or not lease.active or lease.retired then return nil end
    if not lease:_context() or not self.cadence.in_game_thread() then
        lease:unresolved("projectile-observation-context")
        return nil
    end
    return lease
end

function Observer:_valid(object)
    return object~=nil and self.cadence.valid_checked(object)
end

function Observer:_class(object,expected)
    local class=object:GetClass()
    if not self:_valid(class) then error(ERROR,0) end
    local name=class:GetFullName()
    if type(name)~="string" then error(ERROR,0) end
    return name==expected
end

function Observer:_weapon(lease)
    local weapon,reason=self.native:_simulation_weapon(lease.actor,lease.world)
    if not weapon then self.state.lastRefusal=reason; return nil end
    if not self:_class(weapon,Observer.RIFLE) then
        self.state.lastRefusal="unqualified-weapon-class"
        return nil
    end
    return weapon
end

function Observer:_record(kind,record)
    local entries=kind=="creation" and self.state.creations or self.state.hits
    record.sample=record.sample or #entries+1
    record.observedAt=self.bridge.clock()
    record.damageSetupFinalized="unknown"
    entries[#entries+1]=record
    self.state.creationSamplingCapped=self.creationAttempts>=Observer.LIMIT
    self.state.hitSamplingCapped=self.hitAttempts>=Observer.LIMIT
    return self.runner:_save("startup_projectile_"..kind)
end

function Observer:_projectile(bullet,lease)
    local native=self.native
    local root=native.a.unwrap(bullet.RootComponent)
    if not self:_valid(root) then return {rootAvailable=false},nil end
    if not root:IsA("/Script/Engine.PrimitiveComponent") then error(ERROR,0) end
    local result={rootAvailable=true,root=native:_simulation_component(root,bullet,lease.world),
        actorCollision=native:_call("projectile-actor-collision",bullet,"GetActorEnableCollision")}
    if type(result.actorCollision)~="boolean" then error(ERROR,0) end
    local movement=native.a.unwrap(bullet.ProjectileMovement)
    result.movementAvailable=self:_valid(movement)
    if not result.movementAvailable then return result,root end
    if not movement:IsA("/Script/Pal.PalProjectileMovementComponent")
        or not self.cadence.same_checked(native:_call("projectile-movement-owner",movement,"GetOwner"),bullet)
        or not self.cadence.same_checked(native:_call("projectile-movement-world",movement,"GetWorld"),lease.world) then error(ERROR,0) end
    local updated=native.a.unwrap(movement.UpdatedComponent)
    result.updatedRoot=self:_valid(updated) and self.cadence.same_checked(updated,root)
    result.active=native:_call("projectile-active",movement,"IsActive")
    result.tickEnabled=native:_call("projectile-tick-enabled",movement,"IsComponentTickEnabled")
    result.tickInterval=native:_call("projectile-tick-interval",movement,"GetComponentTickInterval")
    result.simulationEnabled=movement.bSimulationEnabled
    result.sweepCollision=movement.bSweepCollision
    result.updateOnlyIfRendered=movement.bUpdateOnlyIfRendered
    for _,key in ipairs({"active","tickEnabled","simulationEnabled","sweepCollision","updateOnlyIfRendered"}) do
        if type(result[key])~="boolean" then error(ERROR,0) end
    end
    if not finite(result.tickInterval) or result.tickInterval<0 then error(ERROR,0) end
    local velocity=vector(native.a.unwrap(movement.Velocity))
    result.speed=math.sqrt(velocity.X^2+velocity.Y^2+velocity.Z^2)
    result.velocityZ=velocity.Z
    result.mobility=root.Mobility
    if not util.is_integer(result.mobility) or result.mobility<0 or result.mobility>2 then error(ERROR,0) end
    return result,root
end

function Observer:created(...)
    if self.creationAttempts>=Observer.LIMIT then return end
    local lease=self:_lease()
    if not lease then return end
    local args=table.pack(...)
    local ok=self.bridge:_native_step("projectile-creation-observation",function()
        if args.n~=2 then error(ERROR,0) end
        if not lease:check() then return end
        local weapon=self:_weapon(lease)
        if not weapon then return end
        local context=args[1]:get()
        if not self.cadence.same_checked(context,weapon) then return end
        self.creationAttempts=self.creationAttempts+1
        local bullet=args[2]:get()
        local record={sample=self.creationAttempts,bulletAvailable=self:_valid(bullet),phase="created-notification-post"}
        if not record.bulletAvailable then self:_record("creation",record); return end
        record.exactBulletFamily=self:_class(bullet,Observer.BULLET)
        if not record.exactBulletFamily then self:_record("creation",record); return end
        if not self.cadence.same_checked(self.native:_call("projectile-created-owner",bullet,"GetOwner"),weapon)
            or not self.cadence.same_checked(self.native:actor_world(bullet),lease.world) then error(ERROR,0) end
        local source
        record.projectile,source=self:_projectile(bullet,lease)
        if source then
            record.actor=self.native:_character_simulation(lease.actor,lease.world,source)
            local target,reason=self.native:_simulation_target(lease.record.scope,lease.controller)
            record.target=target and self.native:_character_simulation(target,lease.world,source)
                or {available=false,reason=reason}
        end
        self:_record("creation",record)
    end)
    if not ok then lease:unresolved("projectile-creation-native-fault") end
end

function Observer:hit(...)
    if self.hitAttempts>=Observer.LIMIT then return end
    local lease=self:_lease()
    if not lease then return end
    local args=table.pack(...)
    local ok=self.bridge:_native_step("projectile-hit-observation",function()
        if args.n~=5 then error(ERROR,0) end
        if not lease:check() then return end
        local bullet=args[1]:get()
        if not self:_valid(bullet) or not self:_class(bullet,Observer.BULLET) then return end
        local weapon=self:_weapon(lease)
        if not weapon then return end
        local owner=self.native:_call("projectile-hit-owner",bullet,"GetOwner")
        if not self:_valid(owner) or not self.cadence.same_checked(owner,weapon) then return end
        if not self.cadence.same_checked(self.native:actor_world(bullet),lease.world) then error(ERROR,0) end
        self.hitAttempts=self.hitAttempts+1
        local record={sample=self.hitAttempts,phase="hit-native-pre",independentOfCreationSamples=true,damageable=bullet.isDamageable,
            weaponDamage=self.native:_call("projectile-weapon-damage",bullet,"GetWeaponDamage")}
        if type(record.damageable)~="boolean" or not util.is_integer(record.weaponDamage) then error(ERROR,0) end
        local source,receiver,component=args[2]:get(),args[3]:get(),args[4]:get()
        record.contact="unqualified-contact"
        if self:_valid(source) and self:_valid(receiver) and self:_valid(component) then
            if not source:IsA("/Script/Engine.PrimitiveComponent")
                or not self.cadence.same_checked(self.native:_call("projectile-hit-source-owner",source,"GetOwner"),bullet) then error(ERROR,0) end
            local root,reason=self.native:_simulation_receiver(receiver,lease.world,lease.record.scope)
            if root then
                record.contact="exact-base-character"
                record.receiverIsRoot=self.cadence.same_checked(root,receiver)
                record.source=self.native:_simulation_component(source,bullet,lease.world)
                record.receiver=self.native:_simulation_component(component,receiver,lease.world,source)
                record.applicable=self.native:_call("projectile-damage-applicability",self.native.utility,
                    "IsApplicableDamage",bullet,receiver,component)
                if type(record.applicable)~="boolean" then error(ERROR,0) end
            else
                record.reason=reason
            end
        end
        -- HitResult is deliberately never decoded, retained, or passed back through reflection.
        self:_record("hit",record)
    end)
    if not ok then lease:unresolved("projectile-hit-native-fault") end
end

return Observer
