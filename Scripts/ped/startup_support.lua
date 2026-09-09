local Layout = require("ped.native_layout")
local Raid = require("ped.native_raid")

local Support = {}
Support.__index = Support
local ERROR = "Startup support scope is invalid"
local SIGNATURE = "Startup support signature is unsupported"
local TRANSFORM = { Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1} }

function Support.new(native, scopes)
    return setmetatable({native=native,bridge=native.bridge,a=native.a,scopes=scopes,records={}},Support)
end

function Support:prepare()
    return self.bridge:_native_step("startup-support-layouts",function()
        local n = self.native
        self.bindings = Raid.prepare(self.bridge,self.a)
        self.actorClass = n:_class("/Script/Engine.TargetPoint")
        self.sourceClass = n:_class("/Script/Engine.WorldPartitionStreamingSourceComponent")
        local partitionClass = n:_class("/Script/Engine.WorldPartitionSubsystem")
        local subsystemLibrary = self.bridge:_static_find("/Script/Engine.Default__SubsystemBlueprintLibrary")
        if not self.a.valid(subsystemLibrary) then error(ERROR,0) end
        n:_signature("/Script/Engine.SubsystemBlueprintLibrary:GetWorldSubsystem",{
            ContextObject={"ObjectProperty",0},Class={"ClassProperty",8},ReturnValue={"ObjectProperty",16},
        })
        n:_signature("/Script/Engine.Actor:AddComponentByClass",{
            Class={"ClassProperty",0},bManualAttachment={"BoolProperty",8},RelativeTransform={"StructProperty",16},
            bDeferredFinish={"BoolProperty",112},ReturnValue={"ObjectProperty",120},
        })
        n:_signature("/Script/Engine.Actor:FinishAddComponent",{
            Component={"ObjectProperty",0},bManualAttachment={"BoolProperty",8},RelativeTransform={"StructProperty",16},
        })
        n:_signature("/Script/Engine.Actor:K2_DestroyActor",{})
        n:_signature("/Script/Engine.Actor:IsActorBeingDestroyed",{ReturnValue={"BoolProperty",0}})
        for _, name in ipairs({"EnableStreamingSource","DisableStreamingSource"}) do
            n:_signature("/Script/Engine.WorldPartitionStreamingSourceComponent:"..name,{})
        end
        for _, name in ipairs({"IsStreamingSourceEnabled","IsStreamingCompleted"}) do
            n:_signature("/Script/Engine.WorldPartitionStreamingSourceComponent:"..name,{ReturnValue={"BoolProperty",0}})
        end
        n:_signature("/Script/NavigationSystem.NavigationSystemV1:GetNavigationSystem",{
            WorldContextObject={"ObjectProperty",0},ReturnValue={"ObjectProperty",8},
        })
        n:_signature("/Script/NavigationSystem.NavigationSystemV1:RegisterNavigationInvoker",{
            Invoker={"ObjectProperty",0},TileGenerationRadius={"FloatProperty",8},TileRemovalRadius={"FloatProperty",12},
        })
        n:_signature("/Script/NavigationSystem.NavigationSystemV1:UnregisterNavigationInvoker",{Invoker={"ObjectProperty",0}})
        local shape = self.bridge:_static_find("/Script/Engine.StreamingSourceShape")
        if not self.a.valid(shape) then error(SIGNATURE,0) end
        Layout.expect(shape,{
            bUseGridLoadingRange={"BoolProperty",0},Radius={"FloatProperty",4},bIsSector={"BoolProperty",8},
            SectorAngle={"FloatProperty",12},Location={"StructProperty",16},Rotation={"StructProperty",40},
        },self.a.valid,SIGNATURE)
        self.world = self.scopes[1].world
        local subsystem = n:_call("support-partition",subsystemLibrary,"GetWorldSubsystem",self.world,partitionClass)
        self.navigation = n:_call("support-navigation",n.navigationLibrary,"GetNavigationSystem",self.world)
        if not self.a.valid(subsystem) or not self.a.valid(self.navigation) then return false end
        if not self.a.same(n:_call("support-subsystem-world",subsystem,"GetWorld"),self.world)
            or not self.a.same(n:_call("support-nav-world",self.navigation,"GetWorld"),self.world) then error(ERROR,0) end
        return true
    end)
end

function Support:begin(index)
    return self.bridge:_native_step("startup-support-spawn",function()
        if self.records[index] then error(ERROR,0) end
        local scope = self.scopes[index]
        local transform = {Rotation=TRANSFORM.Rotation,Scale3D=TRANSFORM.Scale3D,Translation=scope.origin}
        local actor = self.native:_call("support-deferred",self.bindings.library,"BeginDeferredActorSpawnFromClass",
            scope.world,self.actorClass,transform,1,nil)
        if not self.a.valid(actor) then error(ERROR,0) end
        self.records[index] = {actor=actor,world=scope.world,transform=transform,name=actor:GetFName():ToString()}
        return { actorAddress=self.a.address(actor), actorName=actor:GetFName():ToString() }
    end)
end

function Support:_record(index)
    local record = self.records[index]
    if not record or not self.a.valid(record.actor) or not record.actor:IsA("/Script/Engine.TargetPoint")
        or record.actor:GetFName():ToString() ~= record.name
        or not self.a.same(self.native:actor_world(record.actor),record.world) then error(ERROR,0) end
    return record
end

function Support:finish(index)
    return self.bridge:_native_step("startup-support-configure",function()
        local n, record = self.native, self:_record(index)
        local actor = n:_call("support-finish",self.bindings.library,"FinishSpawningActor",record.actor,record.transform)
        if not self.a.same(actor,record.actor) then error(ERROR,0) end
        local location = n:_call("support-location",actor,"K2_GetActorLocation")
        for _, key in ipairs({"X","Y","Z"}) do
            if type(location[key]) ~= "number" or math.abs(location[key]-self.scopes[index].origin[key]) > 1 then error(ERROR,0) end
        end
        local source = n:_call("support-add-source",actor,"AddComponentByClass",self.sourceClass,false,TRANSFORM,true)
        if not self.a.valid(source) then error(ERROR,0) end
        record.source = source
        if not self.a.same(n:_call("support-source-owner",source,"GetOwner"),actor) then error(ERROR,0) end
        n:_call("support-disable-source",source,"DisableStreamingSource")
        source.Shapes:Empty()
        source.Shapes = {{}}
        local shapes = source.Shapes
        if shapes:GetArrayNum() ~= 1 then error(ERROR,0) end
        local shape = shapes[1]
        shape.bUseGridLoadingRange,shape.Radius,shape.bIsSector,shape.SectorAngle=false,12000,false,360
        if shape.bUseGridLoadingRange ~= false or shape.Radius ~= 12000 or shape.bIsSector ~= false then error(ERROR,0) end
        for _, key in ipairs({"X","Y","Z"}) do if shape.Location[key] ~= 0 then error(ERROR,0) end end
        for _, key in ipairs({"Pitch","Yaw","Roll"}) do if shape.Rotation[key] ~= 0 then error(ERROR,0) end end
        local fname = n.a.fname()
        if not fname then error(ERROR,0) end
        source.TargetGrid,source.TargetHLODLayer = fname("None",1),nil
        source.TargetState,source.Priority = 1,128
        if source.TargetState ~= 1 or source.Priority ~= 128 then error(ERROR,0) end
        n:_call("support-finish-component",actor,"FinishAddComponent",source,false,TRANSFORM)
        n:_call("support-enable-source",source,"EnableStreamingSource")
        if n:_call("support-enabled",source,"IsStreamingSourceEnabled") ~= true then error(ERROR,0) end
        n:_call("support-register-nav",self.navigation,"RegisterNavigationInvoker",actor,10000,12000)
        record.navigationRegistered = true
        return true
    end)
end

function Support:_residency(index)
    local record, n = self:_record(index), self.native
    if not self.a.valid(record.source) then error(ERROR,0) end
    local enabled = n:_call("support-enabled",record.source,"IsStreamingSourceEnabled")
    local complete = n:_call("support-streaming-complete",record.source,"IsStreamingCompleted")
    if type(enabled) ~= "boolean" or type(complete) ~= "boolean" then error(ERROR,0) end
    return {enabled=enabled,streamingComplete=complete,physicalQueried=false,ready=false,placementQualified=false}
end

function Support:residency(index)
    return self.bridge:_native_step("startup-support-residency",function() return self:_residency(index) end)
end

function Support:poll(index)
    return self.bridge:_native_step("startup-support-readiness",function()
        local observation=self:_residency(index)
        if not observation.enabled or not observation.streamingComplete then return observation end
        local n,scope=self.native,self.scopes[index]
        local floor=scope.positions[1] and n:startup_floor(scope.world,scope.positions[1]) or nil
        if not floor then floor=n:startup_floor(scope.world,scope.origin) end
        local nav=floor and n:startup_nav(scope.world,floor) or nil
        local goal=n:startup_nav(scope.world,scope.origin)
        return {enabled=observation.enabled,streamingComplete=observation.streamingComplete,physicalQueried=true,ready=nav~=nil and goal~=nil,
            floor=floor~=nil,nav=nav~=nil,goal=goal~=nil,placementQualified=false}
    end)
end

function Support:close(index)
    return self.bridge:_native_step("startup-support-cleanup",function()
        local record, n = self.records[index], self.native
        if not record then error(ERROR,0) end
        if not self.a.valid(record.actor) then return true end
        if not record.destroyRequested then
            self:_record(index)
            if self.a.valid(record.source) then
                if not self.a.same(n:_call("support-cleanup-owner",record.source,"GetOwner"),record.actor) then error(ERROR,0) end
                n:_call("support-cleanup-disable",record.source,"DisableStreamingSource")
                if n:_call("support-cleanup-disabled",record.source,"IsStreamingSourceEnabled") ~= false then error(ERROR,0) end
            end
            if record.navigationRegistered then
                n:_call("support-unregister-nav",self.navigation,"UnregisterNavigationInvoker",record.actor)
            end
            record.destroyRequested = true
            n:_call("support-destroy",record.actor,"K2_DestroyActor")
        end
        return not self.a.valid(record.actor) or n:_call("support-destroying",record.actor,"IsActorBeingDestroyed") == true
    end)
end

return Support
