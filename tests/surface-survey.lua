return function(test,equal,truthy)
    local Survey=require("ped.surface_survey")
    local WATER_CLASS="/Game/Others/FluidInteractionTool/Blueprints/NotNeeded/BP_SimpleWater.BP_SimpleWater_C"
    local function fixture()
        local f={queries=0,clockValue=0}
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
        local mesh=object()
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
                if kind=="volume" then return path=="/Script/Engine.BoxComponent" end
                if kind=="surface" then
                    return path=="/Script/Engine.StaticMeshComponent" or path=="/Script/Engine.InstancedStaticMeshComponent"
                end
                return false
            end
            return c
        end
        local actors={}
        local counts={1,1,4,4,4,4,4,4,1681,356}
        for index=1,10 do
            local actor=object({IsA=function(_,path) return path==WATER_CLASS end,
                GetOuter=function() return persistent end,GetWorld=function() return world end,
                K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end,bWorldOceanPlane=index==1})
            actor.SwimmingVolume=component(actor,"volume",{center={X=0,Y=0,Z=-500},extent={X=10000,Y=10000,Z=500}})
            actor.HierarchicalInstancedStaticMesh=component(actor,"surface",{
                StaticMesh=mesh,center={X=0,Y=0,Z=0},extent={X=10000,Y=10000,Z=0},
                GetInstanceCount=function() return counts[index] end,
            })
            actors[index]=actor
        end
        local block_owner=object({GetWorld=function() return world end})
        f.blocker=component(block_owner,"solid",{objectType=0,toSource=2})
        f.column={actors[1].SwimmingVolume,actors[1].HierarchicalInstancedStaticMesh}
        f.capsule={}
        local function output_query(queries,filter,ignored,out,values)
            equal(#queries,32); equal(queries[1],0); equal(queries[32],31)
            equal(filter,nil); equal(#ignored,0); equal(#out,0)
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
                equal(actual,world); equal(pos.Z,0); equal(extent.Z,100010000)
                truthy(extent.X<=1010 and extent.Y<=1010)
                return output_query(queries,filter,ignored,out,f.column)
            end,
            CapsuleOverlapComponents=function(_,actual,pos,radius,half,queries,filter,ignored,out)
                equal(actual,world); equal(radius,30); equal(half,95)
                equal(pos.Z,(f.height or 1000)+62)
                return output_query(queries,filter,ignored,out,f.capsule)
            end,
        })
        local gameplay=object({
            GetWorldOriginLocation=function() return f.origin or {X=0,Y=0,Z=0} end,
            GetAllActorsOfClass=function(_,actual,_,out)
                equal(actual,world)
                for index=1,(f.missingWater and 9 or 10) do out[index]=actors[index] end
                if f.foreignWater then
                    out[11]=object({IsA=function() return true end,foreign=true})
                elseif f.streamedWater then
                    local extra=object({IsA=function(_,path) return path==WATER_CLASS end,streamed=true,
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
            GetEngineCollisionChannelByPalTraceType=function(_,kind) equal(kind,4); return 7 end,
        }),bridge={}}
        native.a={valid=function(v) return type(v)=="table" and v.IsValid and v:IsValid() end,
            same=function(a,b) return a==b end,unwrap=function(v) return v end}
        native._signature=function() end
        native._class=function(_,path) equal(path,WATER_CLASS); return object() end
        native._call=function(_,_,owner,method,...) return owner[method](owner,...) end
        native.actor_world=function(_,actor)
            if actor.foreign then return object(),object() end
            return world,actor.streamed and object() or persistent
        end
        native.bridge._static_find=function(_,path)
            if path=="/Script/Engine.Default__KismetSystemLibrary" then return kismet end
            if path=="/Script/Engine.Default__GameplayStatics" then return gameplay end
            return mesh
        end
        local source=object({GetCollisionEnabled=function() return 3 end,GetCollisionObjectType=function() return 2 end,
            GetCollisionResponseToChannel=function() return f.ignoreSource and 0 or 2 end})
        native._placement_shape=function() return {capsule=source,bodyProxy={templateOnly=true,
            radius=30,halfHeight=95,centerOffsetZ=62,lowerFootOffsetZ=-33}} end
        native.startup_floor=function() return {X=100,Y=200,Z=f.height or 1000} end
        f.survey=Survey.new(native,{world=world,positions={{X=100,Y=200,Z=1000}},origin={X=0,Y=0,Z=1000}},
            {clock=function() f.clockValue=f.clockValue+(f.clockStep or 0); return f.clockValue end})
        return f
    end

    test("surface survey observes complete stock water geometry but never authorizes an NPC",function()
        local f=fixture()
        local result=f.survey:run()
        equal(result.complete,true); equal(result.classification,"proxy-clear")
        equal(result.spawnQualified,false); equal(result.queries,2); equal(result.columnOceanWitness,true)
        equal(result.footAboveWaterCm,967)
        equal(result.point,nil); equal(result.position,nil); equal(f.survey.point.Z,1000)
        equal(#f.survey.sourceCollision.responses,32)
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

    test("surface survey checks both operative responses and never filters away water contact",function()
        local f=fixture()
        f.capsule={f.blocker}
        equal(f.survey:run().classification,"blocked")
        f=fixture(); f.capsule={f.blocker}; f.blocker.toSource=1
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
