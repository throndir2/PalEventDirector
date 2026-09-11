return function(test,equal,truthy)
    local Survey=require("ped.surface_survey")
    local Native=require("ped.custom_assault_native")
    local WATER_CLASS="/Game/Others/FluidInteractionTool/Blueprints/NotNeeded/BP_SimpleWater.BP_SimpleWater_C"
    local function fixture()
        local f={queries=0,clockValue=0,columnQueries=0,inventoryQueries=0,outputs={}}
        local function object(values)
            values=values or {}
            values.IsValid=function() return true end
            return values
        end
        local persistent=object()
        local world=object({PersistentLevel=persistent,IsA=function(_,path) return path=="/Script/Engine.World" end,
            GetOuter=function() return object({GetFName=function() return {ToString=function()
                return "/Game/Pal/Maps/MainWorld_5/PL_MainWorld5"
            end} end}) end})
        local mesh=object({IsA=function(_,path) return path=="/Script/Engine.StaticMesh" end,
            GetFullName=function() return "StaticMesh /Game/Others/FluidInteractionTool/Meshes/S_WaterMesh.S_WaterMesh" end})
        local function component(owner,kind,properties)
            local c=object(properties)
            c.BoundsScale=1
            c.GetOwner=function() return owner end
            c.GetWorld=function() return world end
            c.GetCollisionEnabled=function() return 3 end
            c.GetCollisionObjectType=function() return c.objectType or 0 end
            c.GetCollisionResponseToChannel=function(_,to)
                if to==7 then return kind=="surface" and 2 or 0 end
                return c.toSource or 2
            end
            c.IsA=function(_,path)
                if path=="/Script/Engine.PrimitiveComponent" then return true end
                if kind=="volume" then return path=="/Script/Engine.BoxComponent" or path=="/Script/Engine.ShapeComponent" end
                if kind=="surface" then
                    return path=="/Script/Engine.StaticMeshComponent" or path=="/Script/Engine.InstancedStaticMeshComponent"
                end
                return kind=="solid" and path=="/Script/Engine.StaticMeshComponent"
            end
            return c
        end
        local actors={}
        local counts={1,1,4,4,4,4,4,4,1681,356}
        for index=1,10 do
            local actor=object({IsA=function(_,path) return path==WATER_CLASS or path=="/Script/Engine.Actor" end,
                GetOuter=function() return persistent end,GetWorld=function() return world end,
                K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end,bWorldOceanPlane=index==1})
            actor.SwimmingVolume=component(actor,"volume",{center={X=0,Y=0,Z=-500},extent={X=10000,Y=10000,Z=500}})
            actor.HierarchicalInstancedStaticMesh=component(actor,"surface",{
                StaticMesh=mesh,center={X=0,Y=0,Z=0},extent={X=10000,Y=10000,Z=0},
                GetInstanceCount=function() return counts[index] end,
            })
            actors[index]=actor
        end
        f.actors,f.mesh=actors,mesh
        local block_owner=object({GetWorld=function() return world end,IsA=function(_,path) return path=="/Script/Engine.Actor" end})
        f.blockOwner=block_owner
        f.blocker=component(block_owner,"solid",{objectType=0,toSource=2})
        f.column={actors[1].SwimmingVolume,actors[1].HierarchicalInstancedStaticMesh}
        f.capsule,f.root={},{}
        local function output_query(queries,filter,ignored,out,values)
            equal(#queries,32); equal(queries[1],0); equal(queries[32],31)
            equal(filter,nil); equal(#ignored,0); equal(#out,0)
            equal(getmetatable(out),nil)
            for _,previous in ipairs(f.outputs) do truthy(previous~=out) end
            f.outputs[#f.outputs+1]=out
            f.queries=f.queries+1
            for index,value in ipairs(values) do out[index]=value end
            return #values>0
        end
        local kismet=object({
            GetComponentBounds=function(_,c,origin,extent,sphere)
                for _,key in ipairs({"X","Y","Z"}) do origin[key]=c.center[key]; extent[key]=c.extent[key] end
                sphere.SphereRadius=20000
            end,
            BoxOverlapComponents=function(_,actual,pos,extent,queries,filter,ignored,out)
                f.columnQueries=f.columnQueries+1
                equal(actual,world); equal(pos.Z,0); equal(extent.Z,100010000)
                truthy(extent.X<=1010 and extent.Y<=1010)
                return output_query(queries,filter,ignored,out,f.column)
            end,
            CapsuleOverlapComponents=function(_,actual,pos,radius,half,queries,filter,ignored,out)
                equal(actual,world); equal(radius,30)
                if half==30 then
                    equal(pos.Z,f.height or 1000)
                    return output_query(queries,filter,ignored,out,f.root)
                end
                equal(half,95)
                equal(pos.Z,(f.height or 1000)+62)
                return output_query(queries,filter,ignored,out,f.capsule)
            end,
        })
        local gameplay=object({
            GetWorldOriginLocation=function() return f.origin or {X=0,Y=0,Z=0} end,
            GetAllActorsOfClass=function(_,actual,_,out)
                f.inventoryQueries=f.inventoryQueries+1
                equal(actual,world)
                for index=1,(f.missingWater and 9 or 10) do out[index]=actors[index] end
                if f.foreignWater then
                    out[11]=object({IsA=function() return true end,foreign=true})
                elseif f.streamedWater then
                    local extra=object({IsA=function(_,path) return path==WATER_CLASS or path=="/Script/Engine.Actor" end,streamed=true,
                        GetWorld=function() error("shadowed world helper was used") end,bWorldOceanPlane=false})
                    extra.SwimmingVolume=component(extra,"volume",{center={X=0,Y=0,Z=-500},extent={X=10000,Y=10000,Z=500}})
                    extra.HierarchicalInstancedStaticMesh=component(extra,"surface",{
                        StaticMesh=mesh,center={X=0,Y=0,Z=0},extent={X=10000,Y=10000,Z=0},
                        GetInstanceCount=function() return 1 end,
                    })
                    out[11]=extra
                end
            end,
        })
        local state=object({IsA=function() return true end,GetWorld=function() return world end})
        local native={utility=object({
            GetPalGameStateInGame=function() return state end,GetWorldOceanPlaneZ=function() return 0 end,
            GetEngineCollisionChannelByPalTraceType=function(_,kind)
                truthy(kind==3 or kind==4)
                return kind==3 and (f.groundChannel or 12) or 7
            end,
            GetEngineCollisionChannelByPalObjectType=function(_,kind) equal(kind,2); return f.playerPawnChannel or 16 end,
        }),bridge={}}
        native.a={valid=function(v) return type(v)=="table" and v.IsValid and v:IsValid() end,
            same=function(a,b) return a==b end,unwrap=function(v) return v end,text=function(v) return v end}
        native._signature=function() end
        native._class=function(_,path) equal(path,WATER_CLASS); return object() end
        native._call=function(_,label,owner,method,...)
            truthy(label:match("^[a-z0-9%-]+$"),"native breadcrumb labels must remain lowercase slugs")
            return owner[method](owner,...)
        end
        native.collision_profile=Native.collision_profile
        native.placement_collision_model=Native.placement_collision_model
        native.placement_mesh_policy=Native.placement_mesh_policy
        native._support_witness=Native._support_witness
        native.bridge.clock=function() return f.now or 1000 end
        native.actor_world=function(_,actor)
            if actor.foreign then return object(),object() end
            return world,actor.streamed and object() or persistent
        end
        native.bridge._static_find=function(_,path)
            if path=="/Script/Engine.Default__KismetSystemLibrary" then return kismet end
            if path=="/Script/Engine.Default__GameplayStatics" then return gameplay end
            return mesh
        end
        local cdo=object({IsA=function(_,path) return path=="/Script/Pal.PalCharacter" end})
        local source=object({IsA=function(_,path) return path=="/Script/Engine.CapsuleComponent" end,
            GetOwner=function() return cdo end,
            RelativeScale3D={X=1,Y=1,Z=1},RelativeLocation={X=0,Y=0,Z=0},RelativeRotation={Pitch=0,Yaw=0,Roll=0},
            GetScaledCapsuleRadius=function() return f.rootRadius or 30 end,
            GetScaledCapsuleHalfHeight=function() return f.rootHalfHeight or 30 end,
            GetCollisionEnabled=function() return 3 end,GetCollisionObjectType=function() return 2 end,
            GetCollisionProfileName=function() return "Pawn" end,
            GetCollisionResponseToChannel=function() return f.ignoreSource and 0 or 2 end})
        cdo.K2_GetRootComponent=function() return source end
        cdo.Mesh=object({IsA=function(_,path) return path=="/Script/Engine.SkeletalMeshComponent" end,
            GetOwner=function() return cdo end,AttachParent=source,
            RelativeLocation={X=0,Y=0,Z=-33},RelativeScale3D={X=1,Y=1,Z=1},RelativeRotation={Pitch=0,Yaw=0,Roll=0},
            GetCollisionEnabled=function() return f.meshEnabled or 0 end,GetCollisionObjectType=function() return f.meshType or 0 end,
            GetCollisionProfileName=function() return f.meshProfile or "NoCollision" end,
            GetCollisionResponseToChannel=function() return f.meshResponse or 0 end})
        f.cdo=cdo
        native._placement_shape=function() return {cdo=cdo,capsule=source,radius=30,halfHeight=30,walkableZ=0.7,bodyProxy={templateOnly=true,
            radius=30,halfHeight=95,centerOffsetZ=62,lowerFootOffsetZ=-33,meshOffsetZ=-33}} end
        native.startup_floor=function() return {X=100,Y=200,Z=f.height or 1000} end
        f.survey=Survey.new(native,{world=world,positions={{X=100,Y=200,Z=1000}},origin={X=0,Y=0,Z=1000}},
            {clock=function() f.clockValue=f.clockValue+(f.clockStep or 0); return f.clockValue end})
        function f:local_probe(shape,witness)
            local probe=Survey.new(native,self.survey.scope,{
                supportWitness=witness,
                clock=function() self.clockValue=self.clockValue+(self.clockStep or 0); return self.clockValue end})
            return probe:local_proxy({X=100,Y=200,Z=self.height or 1000},shape or native:_placement_shape()),probe
        end
        function f:witness(hit_z)
            local point={X=100,Y=200,Z=self.height or 1000}
            local start={X=point.X,Y=point.Y,Z=point.Z+5}
            local finish={X=point.X,Y=point.Y,Z=point.Z-5}
            local hit={Time=(start.Z-(hit_z or point.Z))/10,Distance=start.Z-(hit_z or point.Z),
                TraceStart=start,TraceEnd=finish,Location={X=point.X,Y=point.Y,Z=hit_z or point.Z}}
            local metrics=Native.support_contact_metrics(start,finish,point,hit)
            return native:_support_witness(self.survey.scope,native:_placement_shape(),point,self.blocker,{
                startOverlap={groundChannel=12,ready=true},clearanceBlocked=false,contact=metrics})
        end
        return f
    end

    test("surface survey observes complete stock water geometry but never authorizes an NPC",function()
        local f=fixture()
        local result=f.survey:run()
        equal(result.complete,true); equal(result.classification,"proxy-clear")
        equal(result.spawnQualified,false); equal(result.queries,3); equal(result.columnOceanWitness,true)
        equal(result.footAboveWaterCm,967)
        equal(result.point,nil); equal(result.position,nil); equal(f.survey.point.Z,1000)
        equal(#f.survey.sourceCollision.responses,32)
    end)

    test("local proxy prefilter uses the full offset enclosure without a column or water inventory",function()
        local f=fixture()
        local result,probe=f:local_probe()
        equal(result.complete,true); equal(result.classification,"proxy-clear")
        equal(result.localOnly,true); equal(result.templateOnly,true); equal(result.spawnQualified,false)
        equal(result.bodyProxy.radius,30); equal(result.bodyProxy.halfHeight,95); equal(result.bodyProxy.centerOffsetZ,62)
        equal(result.queries,2); equal(f.columnQueries,0); equal(f.inventoryQueries,0)
        equal(result.point,nil); equal(result.position,nil)
        equal(pcall(probe.local_proxy,probe,{X=100,Y=200,Z=1000},f.survey.native:_placement_shape()),false)
        equal(f.queries,2)
        f=fixture(); f.height=-2000
        equal(f:local_probe().classification,"proxy-clear")
        equal(f.survey:run().classification,"wet")
    end)

    test("local and full surveys share two-way blockers and name-free component categories",function()
        local f=fixture(); f.root={f.blocker}
        local local_result=f:local_probe()
        local full=f.survey:run()
        equal(local_result.classification,"blocked"); equal(full.classification,local_result.classification)
        equal(local_result.mutualBlockers,1); equal(local_result.rootClearance.componentCategories.staticMesh.components,1)
        equal(local_result.rootClearance.componentCategories.staticMesh.mutualBlockers,1)
        local encoded=require("ped.json").encode(local_result)
        equal(encoded:find("actorName",1,true),nil); equal(encoded:find("worldLocation",1,true),nil)
        for _,response in ipairs({0,1}) do
            f=fixture(); f.root={f.blocker}; f.blocker.toSource=response
            equal(f:local_probe().classification,"proxy-clear")
        end
        f=fixture(); f.root={f.blocker}; f.ignoreSource=true
        equal(f:local_probe().classification,"proxy-clear")
    end)

    test("support association distinguishes exact component matches from owner-only matches and duplicates",function()
        local f=fixture()
        local witness=f:witness()
        local other=require("ped.util").shallow_copy(f.blocker)
        f.root={f.blocker,f.blocker,other,other}
        local result=f:local_probe(nil,witness)
        equal(result.classification,"blocked"); equal(result.mutualBlockers,4)
        local root=result.rootClearance
        equal(root.components,4); equal(root.distinctComponents,2); equal(root.duplicateComponents,2)
        equal(root.distinctMutualBlockers,2); equal(root.duplicateMutualBlockers,2)
        equal(root.supportAssociation.matchingSupportBlockers,1)
        equal(root.supportAssociation.otherBlockers,1); equal(root.supportAssociation.label,"OTHER_BLOCKERS")
        equal(root.componentCategories.staticMesh.distinctMutualBlockers,2)
        equal(root.componentCategories.staticMesh.matchingSupportBlockers,1)
        equal(root.componentCategories.staticMesh.otherBlockers,1)
        f=fixture(); witness=f:witness(); other=require("ped.util").shallow_copy(f.blocker)
        f.root={other}
        result=f:local_probe(nil,witness)
        equal(result.rootClearance.supportAssociation.matchingSupportBlockers,0)
        equal(result.rootClearance.supportAssociation.otherBlockers,1)
        equal(result.classification,"blocked")
    end)

    test("before at and arbitrarily small past TOI associations remain diagnostic and blocked",function()
        for _,delta in ipairs({0,0.000023,-0.000023,-0.000000001}) do
            local f=fixture()
            f.root={f.blocker,f.blocker}
            local witness=f:witness(1000-delta)
            local result=f:local_probe(nil,witness)
            local association=result.rootClearance.supportAssociation
            equal(association.label,delta<0 and "PAST_TOI_AMBIGUOUS" or "CONTACT_CANDIDATE")
            equal(association.trace.atOrBeforeReportedTOI,delta>=0)
            equal(association.matchingSupportBlockers,1); equal(association.otherBlockers,0)
            equal(association.bodyScopeQualified,false); equal(association.contactExceptionEnabled,false)
            equal(result.classification,"blocked"); equal(result.spawnQualified,false)
            equal(f.queries,2)
        end
    end)

    test("stale wrong-scope shape point and filter witnesses never become contact permission",function()
        for _,change in ipairs({
            function(f,w) f.now=1003 end,
            function(_,w) w.radius=31 end,
            function(_,w) w.point.Z=w.point.Z+0.0000001 end,
            function(_,w) w.world={} end,
            function(_,w) w.scope={} end,
            function(_,w) w.groundChannel=11 end,
            function(_,w) w.owner={} end,
            function(_,w) w.qualified=false end,
        }) do
            local f=fixture(); f.root={f.blocker}
            local witness=f:witness()
            change(f,witness)
            local result=f:local_probe(nil,witness)
            equal(result.rootClearance.supportAssociation.witnessQualified,false)
            equal(result.rootClearance.supportAssociation.matchingSupportBlockers,0)
            equal(result.classification,"blocked"); equal(result.spawnQualified,false)
        end
    end)

    test("support witness objects and hit coordinates never enter local or final survey results",function()
        local f=fixture(); f.root={f.blocker}
        local witness=f:witness()
        witness.metrics.privateHit={Location={X=100,Y=200,Z=1000},Component=f.blocker}
        local result=f:local_probe(nil,witness)
        local function plain(value)
            if type(value)=="table" then
                equal(value.IsValid,nil); equal(value.GetWorld,nil); equal(value.GetOwner,nil)
                for _,item in pairs(value) do plain(item) end
            else truthy(type(value)~="userdata" and type(value)~="function") end
        end
        plain(result)
        local encoded=require("ped.json").encode(result)
        equal(encoded:find("privateHit",1,true),nil); equal(encoded:find('"component":',1,true),nil)
        equal(encoded:find('"TraceStart":',1,true),nil); equal(encoded:find('"observedAt":',1,true),nil)
        local survey=Survey.new(f.survey.native,f.survey.scope,{point={X=100,Y=200,Z=1000},supportWitness=witness})
        local full=survey:run()
        equal(full.rootClearance.supportAssociation.label,"CONTACT_CANDIDATE")
        equal(full.classification,"blocked"); equal(full.spawnQualified,false)
        plain(full)
    end)

    test("disabled mesh body-only solid contact never becomes an invented root blocker",function()
        local f=fixture(); f.capsule={f.blocker}
        local result=f:local_probe()
        equal(result.complete,true); equal(result.classification,"proxy-clear")
        equal(result.rootCapsuleComponents,0); equal(result.waterProxyComponents,1)
        equal(result.rootClearance.mutualBlockers,0); equal(result.waterProxy.mutualBlockers,0)
        equal(result.waterProxy.nonWaterContacts,1); equal(result.waterProxy.componentCategories.staticMesh.nonWaterContacts,1)
        equal(result.physicalPolicy.rootCapsule.halfHeight,30); equal(result.physicalPolicy.mesh.collision.enabled,0)
        equal(result.physicalPolicy.mesh.collision.profileName,"nocollision")
        equal(result.bodyProxy.halfHeight,95); equal(result.bodyProxy.centerOffsetZ,62); equal(result.bodyProxy.lowerFootOffsetZ,-33)
        equal(result.spawnQualified,false); equal(result.localOnly,true)
        local full=f.survey:run()
        equal(full.classification,"proxy-clear"); equal(full.waterProxyComponents,1); equal(full.rootClearance.mutualBlockers,0)
    end)

    test("root blocking and water contacts in either envelope remain independent vetoes",function()
        local f=fixture(); f.root={f.blocker}; f.capsule={}
        local result=f:local_probe()
        equal(result.classification,"blocked"); equal(result.rootClearance.mutualBlockers,1); equal(result.waterProxy.components,0)
        for _,query in ipairs({"root","capsule"}) do
            f=fixture(); f.ignoreSource=true; f[query]={f.column[1]}
            result=f:local_probe()
            equal(result.classification,"wet"); equal(result.waterContacts,1)
            equal(result.rootClearance.waterContacts,query=="root" and 1 or 0)
            equal(result.waterProxy.waterContacts,query=="capsule" and 1 or 0)
            equal(result.mutualBlockers,0)
        end
    end)

    test("unknown enabled or transformed owned mesh policies cannot authorize root-only clearance",function()
        for _,change in ipairs({
            function(f) f.meshEnabled=1 end,
            function(f) f.meshType=2 end,
            function(f) f.meshProfile="Custom" end,
            function(f) f.meshResponse=1 end,
            function(f) f.cdo.Mesh.RelativeScale3D.Z=2 end,
            function(f) f.cdo.Mesh.GetOwner=function() return {} end end,
            function(f) f.cdo.Mesh.IsA=function() return false end end,
            function(f) f.cdo.Mesh.AttachParent=nil end,
            function(f) f.rootRadius=31 end,
        }) do
            local f=fixture()
            change(f)
            local result=f:local_probe()
            equal(result.complete,false); equal(result.classification,"unsupported")
            equal(f.queries,0); equal(result.spawnQualified,false)
        end
    end)

    test("local and full proxy models conservatively overlay the resolved PlayerPawn channel without setters",function()
        local f=fixture()
        f.ignoreSource=true; f.blocker.objectType=16; f.root={f.blocker}
        local result,probe=f:local_probe()
        equal(result.classification,"blocked"); equal(result.collisionPolicy.palObjectSelector,2)
        equal(result.collisionPolicy.playerPawnChannel,16); equal(result.collisionPolicy.templateResponse,0)
        equal(probe.sourceCollision.responses[17],0); equal(probe.effectiveSourceCollision.responses[17],2)
        local full=f.survey:run()
        equal(full.classification,"blocked"); equal(full.collisionPolicy.playerPawnChannel,16)
        equal(f.survey.sourceCollision.responses[17],0); equal(f.survey.effectiveSourceCollision.responses[17],2)
        f=fixture()
        f.ignoreSource=true; f.playerPawnChannel=18; f.blocker.objectType=16; f.root={f.blocker}
        equal(f:local_probe().classification,"proxy-clear")
        f.blocker.objectType=18
        equal(f:local_probe().classification,"blocked")
        f=fixture(); f.playerPawnChannel=32
        equal(pcall(f.local_probe,f),false); equal(f.queries,0)
    end)

    test("local proxy vetoes water volumes and surfaces even when root responses ignore them",function()
        for _,index in ipairs({1,2}) do
            local f=fixture(); f.ignoreSource=true; f.capsule={f.column[index]}
            local result=f:local_probe()
            equal(result.classification,"wet"); equal(result.waterContacts,1); equal(result.mutualBlockers,0)
            equal(f.columnQueries,0); equal(f.inventoryQueries,0); equal(result.spawnQualified,false)
        end
    end)

    test("local proxy refuses unknown bodies and unrecognized water without filtering by root response",function()
        for _,kind in ipairs({"instanced","skinned","other"}) do
            local f=fixture(); f.ignoreSource=true
            f.blocker.IsA=function(_,path)
                return path=="/Script/Engine.PrimitiveComponent"
                    or (kind=="instanced" and path=="/Script/Engine.InstancedStaticMeshComponent")
                    or (kind=="skinned" and path=="/Script/Engine.SkinnedMeshComponent")
            end
            f.capsule={f.blocker}
            local result=f:local_probe()
            equal(result.classification,"unsupported"); equal(result.unqualifiedBodies,1)
            equal(result.spawnQualified,false)
        end
        local f=fixture(); f.capsule={f.blocker}
        f.blocker.GetCollisionResponseToChannel=function() return 2 end
        local result=f:local_probe()
        equal(result.complete,false); equal(result.code,"water-representation-unqualified")
        equal(result.classification,"unsupported"); equal(result.unqualifiedBodies,1)
    end)

    test("local proxy rejects foreign scopes excessive output and invalid capsule sizes",function()
        for _,kind in ipairs({"foreign-owner","foreign-component","worldless","wrong-owner"}) do
            local f=fixture(); f.capsule={f.blocker}
            if kind=="foreign-owner" then f.blockOwner.foreign=true end
            if kind=="foreign-component" then f.blocker.GetWorld=function() return {} end end
            if kind=="worldless" then f.survey.native.actor_world=function() return nil end end
            if kind=="wrong-owner" then f.blockOwner.IsA=function() return false end end
            equal(pcall(f.local_probe,f),false); equal(f.columnQueries,0)
        end
        local f=fixture()
        for index=1,129 do f.capsule[index]=f.blocker end
        local result=f:local_probe()
        equal(result.complete,false); equal(result.code,"water-proxy-over-cap"); equal(result.waterProxyComponents,129)
        equal(result.spawnQualified,false); equal(f.columnQueries,0)
        f=fixture()
        for index=1,129 do f.root[index]=f.blocker end
        result=f:local_probe()
        equal(result.complete,false); equal(result.code,"root-capsule-over-cap"); equal(result.rootCapsuleComponents,129)
        equal(result.waterProxyComponents,nil); equal(f.queries,1)
        for _,entry in ipairs({{"radius",0},{"radius",1001},{"halfHeight",2001},{"halfHeight",29},{"centerOffsetZ",1000}}) do
            f=fixture()
            local shape=f.survey.native:_placement_shape()
            shape.bodyProxy[entry[1]]=entry[2]
            result=f:local_probe(shape)
            equal(result.complete,false); equal(result.code,"survey-proxy-limit"); equal(f.queries,0)
        end
    end)

    test("an exact private survey point cannot drift to another floor or silently use a fallback",function()
        local f=fixture()
        local survey=Survey.new(f.survey.native,f.survey.scope,{point={X=100,Y=200,Z=1001}})
        local result=survey:run()
        equal(result.complete,false); equal(result.code,"survey-floor-moved")
        equal(result.spawnQualified,false); equal(survey.point,nil); equal(f.queries,0)
    end)

    test("whole-column water evidence rejects deep underwater points even with no local overlap",function()
        local f=fixture()
        f.height=-2000
        local result=f.survey:run()
        equal(result.complete,true); equal(result.classification,"wet")
        equal(result.waterContacts,0); truthy(result.footAboveWaterCm<0)
        equal(result.spawnQualified,false)
    end)

    test("surface inventory includes supported streamed water while retaining the persistent certificate",function()
        local f=fixture(); f.streamedWater=true
        local result=f.survey:run()
        equal(result.complete,true); equal(result.waterActors,11)
        equal(result.persistentWaterActors,10); equal(result.otherLevelWaterActors,1)
        equal(result.foreignWorldWaterActors,0); equal(result.worldlessWaterActors,0)
        equal(result.spawnQualified,false)
    end)

    test("water shape refusal separates query ownership and mesh mismatch without relaxing admission",function()
        for _,kind in ipairs({"volume-query","surface-query","volume-owner","surface-owner","mesh","private-mesh-name"}) do
            local f=fixture()
            local actor=f.actors[2]
            if kind=="volume-query" then actor.SwimmingVolume.GetCollisionEnabled=function() return 0 end end
            if kind=="surface-query" then actor.HierarchicalInstancedStaticMesh.GetCollisionEnabled=function() return 0 end end
            if kind=="volume-owner" then actor.SwimmingVolume.GetOwner=function() return f.actors[1] end end
            if kind=="surface-owner" then actor.HierarchicalInstancedStaticMesh.GetOwner=function() return f.actors[1] end end
            if kind=="mesh" or kind=="private-mesh-name" then
                actor.HierarchicalInstancedStaticMesh.StaticMesh={
                    IsValid=function() return true end,
                    IsA=function(_,path) return path=="/Script/Engine.StaticMesh" end,
                    GetFullName=function()
                        return kind=="mesh" and "StaticMesh /Game/Water/S_Alternate.S_Alternate"
                            or "StaticMesh /Temp/PRIVATE_RUNTIME_OBJECT"
                    end,
                }
            end
            local result=f.survey:run()
            equal(result.complete,false); equal(result.spawnQualified,false); equal(result.code,"water-shape-scope")
            equal(result.queries,0)
            local detail=result.waterShapeScope
            equal(detail.actorOrdinal,2); equal(detail.persistent,true)
            equal(detail.volumeQueryQualified,kind~="volume-query")
            equal(detail.surfaceQueryQualified,kind~="surface-query")
            equal(detail.volumeOwnerMatches,kind~="volume-query" and kind~="volume-owner")
            equal(detail.surfaceOwnerMatches,kind~="surface-query" and kind~="surface-owner")
            equal(detail.expectedMeshMatches,kind~="mesh" and kind~="private-mesh-name")
            local expected_asset=kind=="mesh" and "/Game/Water/S_Alternate.S_Alternate"
                or kind~="private-mesh-name" and "/Game/Others/FluidInteractionTool/Meshes/S_WaterMesh.S_WaterMesh" or nil
            equal(detail.actualMeshAsset,expected_asset)
            equal(require("ped.json").encode(result):find("PRIVATE_RUNTIME_OBJECT",1,true),nil)
        end
    end)

    test("surface survey checks both operative responses and never filters away water contact",function()
        local f=fixture()
        f.root={f.blocker}
        equal(f.survey:run().classification,"blocked")
        f=fixture(); f.root={f.blocker}; f.blocker.toSource=1
        equal(f.survey:run().classification,"proxy-clear")
        f=fixture(); f.ignoreSource=true; f.capsule={f.column[2]}
        equal(f.survey:run().classification,"wet")
    end)

    test("surface survey refuses missing witnesses changed origins excessive outputs and slow initial queries",function()
        local f=fixture(); f.missingWater=true
        local result=f.survey:run()
        equal(result.code,"water-cohort-incomplete"); equal(f.queries,0)
        equal(result.waterActors,9); equal(result.persistentWaterActors,9); equal(result.otherLevelWaterActors,0)
        truthy(result.bodyProxy)
        f=fixture(); f.origin={X=1,Y=0,Z=0}
        equal(f.survey:run().code,"world-origin-unqualified"); equal(f.queries,0)
        f=fixture()
        for index=3,129 do f.column[index]=f.column[1] end
        equal(f.survey:run().code,"column-over-cap"); equal(f.queries,1)
        f=fixture(); f.clockStep=0.3
        equal(f.survey:run().code,"column-slow"); equal(f.queries,1)
        f=fixture(); f.foreignWater=true
        result=f.survey:run()
        equal(result.code,"water-cohort-world-mismatch"); equal(result.foreignWorldWaterActors,1)
        equal(result.persistentWaterActors,10); equal(f.queries,0)
    end)
end
