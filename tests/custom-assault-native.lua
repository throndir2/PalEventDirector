return function(test, equal, truthy)
    local Native = require("ped.custom_assault_native")
    local Config = require("ped.config")
    local util = require("ped.util")

    local function recovered(engine, members)
        return engine:cleanup_recovered(members, function() return true end)
    end

    test("explicit startup base selection never substitutes a later available base",function()
        local ids={"first","second","third"}
        local selected=Native.startup_base_ids(ids,1,2)
        equal(#selected,1); equal(selected[1],"second")
        equal(Native.startup_base_ids(ids,2,3),nil)
        selected=Native.startup_base_ids(ids,2,2)
        equal(selected[1],"second"); equal(selected[2],"third")
        equal(Native.startup_base_ids(ids,1,nil),ids)
        equal(pcall(Native.startup_base_ids,ids,1,0),false)
    end)

    local function fixture(callback)
        local f = { initialized = true, active = true, dead = false, capturing = false, calls = {}, spawns = 0 }
        local zero = { A = 0, B = 0, C = 0, D = 0 }
        local identity = { PlayerUId = util.deep_copy(zero), InstanceId = { A = 1, B = 2, C = 3, D = 4 }, DebugName = "PRIVATE" }
        local function object(values)
            values = values or {}
            values.IsValid = function() return true end
            return values
        end
        local function id(value)
            if not value or not value.A then return nil end
            if value.A == 0 and value.B == 0 and value.C == 0 and value.D == 0 then return nil end
            return table.concat({ value.A, value.B, value.C, value.D }, "-")
        end
        local world = object({IsA=function(_,path) return path=="/Script/Engine.World" end})
        local level=object({IsA=function(_,path) return path=="/Script/Engine.Level" end,OwningWorld=world})
        f.levels={}
        local component = object({ GetIsCapturedProcessing = function() return f.capturing end })
        local actions = object({
            GetCurrentAction_BP = function() return f.current_action end,
            TerminateCurrentActionByClass = function() f.terminated = (f.terminated or 0) + 1 end,
            SetActionClassParameter = function(_, class, parameter)
                f.action_class, f.action_parameter = class, parameter
                return object()
            end,
        })
        local blackboard = object()
        local controller = object({
            CustomTimeDilation=1,MinAIActionComponentTickInterval=0,IsActiveAI=function() return true end,
            GetAIActionComponent = function() if f.ai_pending then return nil end; return actions end,
            GetMyPalBlackboard = function() return blackboard end,
            StopMovement = function() f.stops = (f.stops or 0) + 1 end,
            AddTargetNPC = function(_, target) f.npc_target = target end,
            AddTargetPlayer_ForEnemy = function(_, target) f.player_target = target end,
            PalMoveToLocation = function(_, ...)
                equal(select("#", ...), 8)
                local _, radius, stop, path, project, strafe, filter, partial = ...
                equal(radius, 150); equal(stop, true); equal(path, true); equal(project, true)
                equal(strafe, false); equal(filter, nil); equal(partial, false)
                f.moves = (f.moves or 0) + 1
                if f.move_result ~= nil then return f.move_result end
                return 2
            end,
        })
        actions.GetOwner=function() return controller end
        actions.GetComponentTickInterval=function() return f.tick_interval or 0 end
        actions.IsComponentTickEnabled=function() return true end
        local parameter = object({
            SaveParameter = { IsPlayer = false, OwnerPlayerUId = util.deep_copy(zero), OldOwnerPlayerUIds = {} },
            GetPalId = function() return identity end,
            GetCharacterID = function() return f.wrong_character and "UnrelatedCharacter" or "BOSS_Hunter_Rifle" end,
            GetMaxHP = function() return 1000 end,
            IsDead = function() return f.dead end,
        })
        local actor = object({
            ImportanceType=0,
            IsA = function(_, path) return path == "/Script/Pal.PalCharacter" end,
            GetWorld = function() return f.foreign_world and object() or world end,
            GetCharacterParameterComponent = function() return component end,
            IsInitialized = function() return f.initialized end,
            GetController = function() return controller end,
            K2_GetActorLocation = function() return f.location or { X = 0, Y = 0, Z = 0 } end,
            IsActorBeingDestroyed = function() return f.destroying == true end,
            GetActionComponent = function() return object({
                ActionIsEmpty = function() return f.body_busy ~= true end,
                PlayAction = function(_, target)
                    equal(target, f.building)
                    f.attacks = (f.attacks or 0) + 1
                    return object()
                end,
            }) end,
            GetComponentByClass = function() return object({
                ActivateInvoker = function() f.nav_active = true end,
            }) end,
            bIsPalActiveActor = true,
        })
        local handle = object({
            GetIndividualID = function()
                if f.id_pending then return {PlayerUId=util.deep_copy(zero),InstanceId=util.deep_copy(zero)} end
                return identity
            end,
            TryGetIndividualParameter = function() return parameter end,
            TryGetIndividualActor = function()
                if f.missing or f.actor_missing then return nil end
                return f.replacement or actor
            end,
        })
        local character_manager = object({
            GetIndividualHandle = function(_, actual)
                equal(id(actual.InstanceId), id(identity.InstanceId))
                equal(actual.DebugName, "")
                f.reacquired = (f.reacquired or 0) + 1
                if f.missing then return nil end
                return handle
            end,
            DespawnCharacterByHandle = function(_, actual_handle, delegate)
                equal(actual_handle, handle); equal(delegate, nil)
                f.despawns = (f.despawns or 0) + 1
                if not f.async_cleanup then f.missing, f.destroying = true, true end
            end,
        })
        local npc_manager = object({
            SpawnNPCForServer = function(_, ...)
                equal(select("#", ...), 2)
                local info, delegate = ...
                equal(delegate, nil)
                equal(info.CharacterID, "BOSS_Hunter_Rifle")
                equal(info.Level, 30)
                equal(info.Squad, nil)
                f.spawns = f.spawns + 1
                return handle
            end,
        })
        local bridge = { config = Config.defaults(), logger = { info = function() end }, clock = function() return f.now or 1000 end }
        function bridge:_native_step(_, operation) return pcall(operation) end
        function bridge:_native_call(label, owner, method, ...)
            f.calls[#f.calls + 1] = label
            local args = table.pack(...)
            return pcall(function() return owner[method](owner, table.unpack(args, 1, args.n)) end)
        end
        function bridge:_static_find(path)
            if path=="/Script/Engine.Default__KismetSystemLibrary" then
                return object({GetOuterObject=function() return f.current_action end})
            end
            if path=="/Script/Engine.Actor:GetLevel" then
                return setmetatable(object(),{__call=function(_,which)
                    if f.foreign_world and which==actor then
                        return object({IsA=function() return true end,OwningWorld=object({IsA=function() return true end})})
                    end
                    return f.levels[which] or level
                end})
            end
        end
        local engine = Native.new(bridge, {
            valid = function(value) return type(value) == "table" and value.IsValid and value:IsValid() == true end,
            unwrap = function(value) return value end, same = function(a, b) return a ~= nil and a == b end,
            guid = id, text = function(value) return value end, fname = function() return function(value) return value end end,
        })
        engine.world, engine.characterManager, engine.npcManager = world, character_manager, npc_manager
        engine.controllerClass = object()
        engine.utility = object({
            GetNearestEnemyBuildObject = function() return f.building end,
            AdjustActorToFloor = function(_, actual) equal(actual, actor); return actor end,
            ChangeDefaultLandMovementModeForWalking = function() f.walking = true end,
            GeneralTurnToActor_WithMovementRotationSpeed = function(_, actual, building, dt)
                equal(actual, actor); equal(building, f.building)
                truthy(dt > 0 and dt <= 1)
                f.turns = (f.turns or 0) + 1
            end,
            InConeShapAndDitance_Actor = function(_, actual, building, degree, reach)
                equal(actual, actor); equal(building, f.building); equal(degree, 160); equal(reach, 300)
                return f.in_cone ~= false
            end,
            GetIndividualCharacterParameterByActor = function(_, target) return target.parameter end,
            GetBattleManager = function() return object({
                TargetIsPlayerOrPlayersOtomoPal = function() return f.player_defender == true end,
            }) end,
        })
        for _, key in ipairs({ "travel", "encounter", "combat", "melee", "invoker" }) do
            engine.classes[key] = object({ type = function() return "UClass" end, IsClass = function() return true end })
        end
        engine._action_class = function(_, key) return engine.classes[key] end
        local scope = { world = world, origin = { X = 0, Y = 0, Z = 0 }, range = 1000, players = {},
            baseId = "9-0-0-0", leashRadius = 1000, guildId = "8-0-0-0",
            positions = { { X = 100, Y = 0, Z = 0 } }, base = object({
                GetId = function() return { A = 9, B = 0, C = 0, D = 0 } end,
                GetGroupIdBelongTo = function() return { A = 8, B = 0, C = 0, D = 0 } end,
            }) }
        local member = { index = 1, groupId = "private-group", baseId = "9-0-0-0", slot = 1,
            characterId = "BOSS_Hunter_Rifle", level = 30 }
        function f:building_at(x, foreign_base)
            self.building = object({
                IsA = function() return false end,
                GetBaseCampIdBelongTo = function() return { A = foreign_base and 77 or 9, B = 0, C = 0, D = 0 } end,
                K2_GetActorLocation = function() return { X = x, Y = 0, Z = 0 } end,
            })
        end
        function f:defender_at(x)
            return object({
                IsA = function(_, path) return path == "/Script/Pal.PalCharacter" end,
                GetWorld = function() return world end,
                IsInitialized = function() return true end, bIsPalActiveActor = true,
                K2_GetActorLocation = function() return { X = x, Y = 0, Z = 0 } end,
                parameter = object({
                    GetBaseCampId = function() return { A = 9, B = 0, C = 0, D = 0 } end,
                    GetGroupId = function() return { A = 8, B = 0, C = 0, D = 0 } end,
                    IsDead = function() return false end,
                }),
            })
        end
        function f:combat_action(target, module_target, without_module)
            return object({
                IsA = function(_, path) return path == "/Script/AIModule.PawnAction" or path == "/Script/Pal.PalAIActionBase"
                    or path:find("NPC_CombatBase", 1, true) ~= nil end,
                IsActive=function() return true end,IsPaused=function() return f.paused==true end,
                Timer = 1, tempDeltaTime = 0.25,
                TargetActor = target,
                CombatModule = not without_module and object({ GetTargetActor = function() return module_target end }) or nil,
            })
        end
        function f:workers(...)
            local actors = { ... }
            scope.base.WorkerDirector = object({
                GetCharacterHandleSlots = function(_, slots)
                    for index, worker in ipairs(actors) do
                        slots[index] = object({ GetHandle = function()
                            return object({ TryGetIndividualActor = function() return worker end })
                        end })
                    end
                end,
            })
        end
        function f:weapon(ready)
            controller.WeaponHandle = object({
                IsEndInitialize = function() return ready end,
                GetSphereCastRadius = function()
                    truthy(ready, "unready weapon radius was queried")
                    return 5
                end,
            })
            engine.utility.LineTraceToTarget_ForAIAttack = function(_, attacker, target, radius)
                equal(attacker, actor); equal(radius, 5)
                self.visibilityChecks = (self.visibilityChecks or 0) + 1
                if self.visibilityFailure then error("fixture visibility failure") end
                return target.visible == true
            end
        end
        engine.placements[member.groupId..":"..member.index] = {scope=scope,characterId=member.characterId,
            level=member.level,slot=member.slot,position=util.shallow_copy(scope.positions[member.slot])}
        local ok, result = engine:spawn(scope, member)
        truthy(ok, result)
        member.handle = result
        callback(engine, member, f, parameter, actor, scope)
    end

    local function support_fixture(callback)
        fixture(function(engine,member,f,_,_,scope)
            local function object(values)
                values=values or {}
                values.IsValid=function() return true end
                return values
            end
            f.point={X=100,Y=0,Z=0}
            f.startComponents,f.overlapOutputs,f.overlapCenters={},{},{}
            f.supportSweeps,f.clearanceQueries,f.responseQueries=0,0,0
            f.groundChannel=12
            function f:component(kind,response)
                local owner=object({IsA=function(_,path) return path=="/Script/Engine.Actor" end,
                    GetWorld=function() error("shadowed actor world helper used") end,
                    GetLevel=function() error("shadowed actor level helper used") end})
                local component=object({owner=owner,world=scope.world,enabled=3,response=response,
                    IsA=function(_,path)
                        return path=="/Script/Engine.PrimitiveComponent"
                            or (kind=="shape" and path=="/Script/Engine.ShapeComponent")
                            or ((kind=="static" or kind=="instanced") and path=="/Script/Engine.StaticMeshComponent")
                            or (kind=="instanced" and path=="/Script/Engine.InstancedStaticMeshComponent")
                            or (kind=="skinned" and path=="/Script/Engine.SkinnedMeshComponent")
                    end,
                    GetOwner=function(self) return self.owner end,
                    GetWorld=function(self) return self.world end,
                    GetCollisionEnabled=function(self) return self.enabled end,
                    GetCollisionResponseToChannel=function(self,channel)
                        equal(channel,f.groundChannel)
                        f.responseQueries=f.responseQueries+1
                        return self.response
                    end,
                    GetWalkableSlopeOverride=function() return {WalkableSlopeBehavior=f.slopeBehavior or 0} end,
                })
                return component
            end
            local hit_component=f:component("static",2)
            engine._placement_shape=function() return {radius=30,halfHeight=80,walkableZ=0.7} end
            local previous_find=engine.bridge._static_find
            local kismet=object({CapsuleOverlapComponents=function(_,world,point,radius,half,types,filter,ignored,output)
                equal(world,scope.world); equal(radius,30); equal(half,80)
                equal(point.X,f.point.X); equal(point.Y,f.point.Y); equal(point.Z,f.point.Z+5)
                equal(#types,32); equal(getmetatable(types),nil)
                for index=1,32 do equal(types[index],index-1) end
                equal(filter,nil); equal(#ignored,0); equal(getmetatable(ignored),nil)
                equal(#output,0); equal(getmetatable(output),nil)
                for _,previous in ipairs(f.overlapOutputs) do truthy(previous~=output) end
                f.overlapOutputs[#f.overlapOutputs+1]=output
                f.overlapCenters[#f.overlapCenters+1]=util.shallow_copy(point)
                if f.overlapFault then error("fixture overlap native fault") end
                for key,value in pairs(f.startComponents) do output[key]=value end
                if f.overlapReturn~=nil then return f.overlapReturn end
                return #f.startComponents>0
            end})
            engine.bridge._static_find=function(self,path)
                if path=="/Script/Engine.Default__KismetSystemLibrary" then return kismet end
                return previous_find(self,path)
            end
            engine.utility.GetEngineCollisionChannelByPalTraceType=function(_,kind)
                equal(kind,3)
                return f.groundChannel
            end
            engine.physicsLibrary={CapsuleTraceSingleByPalTraceType=function(_,world,start,finish,radius,half,kind,complex,material,index,hit,draw)
                equal(world,scope.world); equal(radius,30); equal(half,80); equal(kind,3)
                equal(complex,false); equal(material,false); equal(index,false); equal(draw,0)
                if finish.Z>start.Z then
                    equal(start.Z,f.point.Z+2); equal(finish.Z,f.point.Z+4)
                    f.clearanceQueries=f.clearanceQueries+1
                    return f.clearanceBlocked==true
                end
                equal(start.Z,f.point.Z+5); equal(finish.Z,f.point.Z-5)
                for _,axis in ipairs({"X","Y","Z"}) do equal(start[axis],f.overlapCenters[#f.overlapCenters][axis]) end
                f.supportSweeps=f.supportSweeps+1
                local shared_byte=f.hitByte or 1
                hit.bBlockingHit,hit.bStartPenetrating=shared_byte~=0,shared_byte~=0
                hit.ImpactNormal={X=0,Y=0,Z=f.normal or 1}
                hit.Location=f.contact or util.shallow_copy(f.point)
                hit.Time=f.hitTime or 0.5
                hit.Distance=f.hitDistance or 5
                hit.TraceStart=util.shallow_copy(start)
                hit.TraceEnd=util.shallow_copy(finish)
                if f.badTraceEcho then hit.TraceStart.Z=hit.TraceStart.Z+1 end
                local function resolve() return not f.missingComponent and hit_component or nil end
                hit.Component={Get=resolve,get=resolve}
                hit.ActorName="private-hit-name"
                return f.sweepFound~=false
            end}
            function engine.bridge:_native_step(_,operation)
                if self.native_fault then return false,self.native_fault end
                local values=table.pack(pcall(operation))
                if not values[1] then self.native_fault=values[2] end
                return table.unpack(values,1,values.n)
            end
            function f:probe(surface)
                return engine.bridge:_native_step("fixture-support",function()
                    if surface then return engine:_placement_surface(scope,member,self.point) end
                    return engine:_placement_support(scope,member,self.point)
                end)
            end
            callback(engine,f,scope)
        end)
    end

    test("custom NPC adapter preserves the nil delegate and uses full manager-resolved identity", function()
        fixture(function(engine, member, f)
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "alive")
            equal(state.characterId, member.characterId)
            equal(state.targetId, "1-2-3-4")
            equal(state.playerGuid.A, 0)
            equal(state.healthBudget, 1000)
            equal(f.spawns, 1)
            equal(f.reacquired, 1)
        end)
    end)

    test("custom NPC readiness is checked on the actor rather than a nonexistent handle method", function()
        fixture(function(engine, member, f)
            f.initialized = false
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "pending")
            f.initialized = true
            ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "alive")
        end)
    end)

    test("custom NPC ownership revokes capture and pauses capture-in-progress without changing it", function()
        fixture(function(engine, member, f, parameter)
            f.capturing = true
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "capturing")
            f.capturing = false
            parameter.SaveParameter.OwnerPlayerUId.A = 7
            ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "captured")
            equal(state.actor, nil)
            equal(parameter.SaveParameter.OwnerPlayerUId.A, 7)
        end)
    end)

    test("custom NPC adapter rejects changed identity and foreign-world actors before control", function()
        for _, mode in ipairs({ "wrong_character", "foreign_world" }) do
            fixture(function(engine, member, f)
                f[mode] = true
                local ok = engine:inspect(member.handle, member)
                equal(ok, false)
            end)
        end
        fixture(function(engine, member, f)
            truthy(engine:inspect(member.handle, member))
            f.replacement = { IsValid = function() return true end, IsA = function() return true end,
                GetWorld = function() return engine.world end,
                GetCharacterParameterComponent = function() return { IsValid = function() return true end,
                    GetIsCapturedProcessing = function() return false end } end,
                IsInitialized = function() return true end, bIsPalActiveActor = true,
                GetController = function() return { IsValid = function() return true end,
                    GetAIActionComponent = function() return { IsValid = function() return true end } end,
                    GetMyPalBlackboard = function() return { IsValid = function() return true end } end } end }
            equal(engine:inspect(member.handle, member), false)
        end)
    end)

    test("actor scope uses reflected level ownership instead of the shadowed outer-world helpers",function()
        fixture(function(engine,member,f,_,actor,scope)
            actor.GetWorld=function() error("shadowed actor world helper was called") end
            actor.GetLevel=function() error("shadowed actor level helper was called") end
            local streamed={IsValid=function() return true end,IsA=function() return true end,OwningWorld=scope.world}
            f.levels[actor]=streamed
            local actual,level=engine:actor_world(actor)
            equal(actual,scope.world); equal(level,streamed)
            local ok,state=engine:inspect(member.handle,member)
            truthy(ok,state); equal(state.phase,"alive")
            streamed.OwningWorld=nil
            equal(engine:actor_world(actor),nil)
            equal(engine:inspect(member.handle,member),false)
        end)
    end)

    test("custom NPC adapter marks a still-owned out-of-envelope actor for guarded cleanup", function()
        fixture(function(engine, member, f)
            f.location = { X = 2000, Y = 0, Z = 0 }
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "escaped")
            equal(state.targetId, "1-2-3-4")
            equal(f.spawns, 1)
        end)
    end)

    test("custom NPC cleanup distinguishes synchronous detachment from deferred completion", function()
        fixture(function(engine, member, f, _, _, scope)
            truthy(engine:inspect(member.handle, member))
            local ok, outcome = engine:despawn(scope, member)
            truthy(ok, outcome)
            equal(outcome, "despawned")
            equal(f.despawns, 1)
        end)
        fixture(function(engine, member, f, _, _, scope)
            truthy(engine:inspect(member.handle, member))
            f.async_cleanup = true
            local ok, outcome = engine:despawn(scope, member)
            truthy(ok, outcome); equal(outcome, "pending")
            ok, outcome = engine:despawn(scope, member)
            truthy(ok, outcome); equal(outcome, "pending")
            equal(f.despawns, 1)
            f.missing, f.destroying = true, true
            local state
            ok, state = engine:inspect(member.handle, member)
            truthy(ok, state); equal(state.phase, "missing")
            equal(f.despawns, 1)
        end)
    end)

    test("inactive custom actors are not treated as confirmed despawns", function()
        fixture(function(engine, member, f, _, actor, scope)
            truthy(engine:inspect(member.handle, member))
            f.async_cleanup = true
            actor.bIsPalActiveActor = false
            local inspected, state = engine:inspect(member.handle, member)
            truthy(inspected, state)
            equal(state.phase, "inactive")
            local ok, outcome = engine:despawn(scope, member)
            truthy(ok, outcome)
            equal(outcome, "pending")
            equal(f.despawns, 1)
        end)
    end)

    test("a missing handle does not discard a still-live initialized custom actor", function()
        fixture(function(engine, member, f)
            truthy(engine:inspect(member.handle, member))
            f.missing = true
            local ok, reason = engine:inspect(member.handle, member)
            equal(ok, false)
            equal(reason, "Custom assault ownership is unreadable")
            f.destroying = true
            local state
            ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "missing")
        end)
    end)

    test("recovered custom cleanup retains full identity and does not repeat a pending request", function()
        fixture(function(engine, member, f)
            engine.records = {}
            f.async_cleanup = true
            local saved = { ["1"] = { index = member.index, baseId = member.baseId, groupId = member.groupId,
                characterId = member.characterId, spawnRequested = true, status = "initialized",
                instanceGuid = { A = 1, B = 2, C = 3, D = 4 }, playerGuid = { A = 0, B = 0, C = 0, D = 0 } } }
            local ok, result = recovered(engine, saved)
            truthy(ok, result); equal(result, "pending")
            equal(f.despawns, 1)
            ok, result = recovered(engine, saved)
            truthy(ok, result); equal(result, "pending")
            equal(f.despawns, 1)
            f.missing, f.destroying = true, true
            ok, result = recovered(engine, saved)
            truthy(ok, result); equal(result, "complete")
            equal(engine.recoveryPending, false)
            equal(f.despawns, 1)
        end)
    end)

    test("recovered custom cleanup refuses unidentified spawn outcomes instead of skipping them", function()
        fixture(function(engine, member, f)
            local ok, reason = recovered(engine, { ["1"] = { index = member.index, baseId = member.baseId,
                groupId = member.groupId, characterId = member.characterId, spawnRequested = true, status = "planned" } })
            equal(ok, false)
            equal(reason, "Custom assault recovery has an unidentified spawn outcome")
            equal(f.despawns, nil)
        end)
    end)

    test("recovered cleanup uses the configured per-poll budget even for never-spawned plans", function()
        fixture(function(engine, _, f)
            engine.bridge.config.customAssault.pollBatchSize = 1
            local saved = { ["1"] = { status = "planned" }, ["2"] = { status = "cancelled" } }
            local ok, result = recovered(engine, saved)
            truthy(ok, result); equal(result, "pending")
            equal(util.count(engine.recoveryCompleted), 1)
            ok, result = recovered(engine, saved)
            truthy(ok, result); equal(result, "complete")
            equal(f.despawns, nil)
        end)
    end)

    test("recovered placement-only intent is not mistaken for an unidentified NPC spawn", function()
        fixture(function(engine,_,f)
            local outcomes={}
            local ok,result=engine:cleanup_recovered({
                ["1"]={index=1,status="planned",lastTransition="custom_placement_intent"},
                ["2"]={index=2,status="planned",lastTransition="custom_placement_observed"},
            },function(index,outcome) outcomes[index]=outcome; return true end)
            truthy(ok,result); equal(result,"complete")
            equal(outcomes[1],"cancelled"); equal(outcomes[2],"cancelled")
            equal(f.despawns,nil)
        end)
    end)

    test("recovered cleanup cannot release an absent handle while its original actor remains alive", function()
        fixture(function(engine, member, f)
            truthy(engine:inspect(member.handle, member))
            f.missing = true
            local saved = { ["1"] = { index = member.index, groupId = member.groupId, baseId = member.baseId,
                characterId = member.characterId, spawnRequested = true, status = "initialized",
                instanceGuid = { A = 1, B = 2, C = 3, D = 4 }, playerGuid = { A = 0, B = 0, C = 0, D = 0 } } }
            local ok, reason = recovered(engine, saved)
            equal(ok, false)
            equal(reason, "Custom assault ownership is unreadable")
            equal(engine.recoveryCompleted["1"], nil)
            engine.records = {}
            ok, reason = recovered(engine, saved)
            truthy(ok, reason)
            equal(reason, "pending")
            equal(engine.recoveryCompleted["1"], nil)
            equal(engine.recoveryPending, true)
        end)
    end)

    test("recovered cleanup persists member outcomes before releasing ownership", function()
        fixture(function(engine, member, f)
            local saved = { ["1"] = { index = member.index, groupId = member.groupId, baseId = member.baseId,
                characterId = member.characterId, spawnRequested = true, status = "initialized",
                instanceGuid = { A = 1, B = 2, C = 3, D = 4 }, playerGuid = { A = 0, B = 0, C = 0, D = 0 } } }
            local ok, reason = engine:cleanup_recovered(saved, function(index, outcome)
                equal(index, 1); equal(outcome, "despawned")
                return false
            end)
            equal(ok, false)
            equal(reason, "Custom assault recovery outcome could not be persisted")
            equal(f.despawns, 1)
            equal(engine.recoveryCompleted["1"], nil)
        end)
    end)

    test("building movement consumes all native result values without treating acceptance as damage", function()
        for _, result in ipairs({ 0, 1, 2, 3 }) do
            fixture(function(engine, member, f, _, _, scope)
                f:building_at(600)
                f.move_result = result
                local ok, outcome = engine:engage(scope, member)
                equal(ok, result ~= 3)
                equal(outcome, result == 0 and "unavailable" or result == 3 and "Custom assault native action failed" or true)
                equal(f.moves, 1)
                equal(f.attacks, nil)
                equal(f.nav_active, true)
            end)
        end
    end)

    test("building strikes require stock facing and reach as well as an idle body action", function()
        fixture(function(engine, member, f, _, _, scope)
            f:building_at(200)
            f.in_cone = false
            truthy(engine:engage(scope, member))
            equal(f.turns, 1)
            equal(f.attacks, nil)
            f.now, f.in_cone, f.body_busy = 1001, true, true
            truthy(engine:engage(scope, member))
            equal(f.attacks, nil)
            f.now, f.body_busy = 1002, false
            truthy(engine:engage(scope, member))
            equal(f.attacks, 1)
        end)
    end)

    test("an unrelated building is never approached or attacked as a fallback", function()
        fixture(function(engine, member, f, _, _, scope)
            f:building_at(200, true)
            truthy(engine:engage(scope, member))
            equal(f.moves, nil)
            equal(f.attacks, nil)
            equal(f.action_class, engine.classes.travel)
            equal(f.action_parameter.GeneralActor1, nil)
            equal(f.action_parameter.GeneralVector1.X, scope.origin.X)
        end)
    end)

    test("custom combat setup targets an eligible local defender with the correct stock action", function()
        fixture(function(engine, member, f, _, actor, scope)
            local defender = f:defender_at(500)
            scope.players = { { controller = { IsValid = function() return true end, GetPawn = function() return defender end } } }
            truthy(engine:startup_travel(scope,member))
            truthy(engine:engage(scope, member))
            equal(f.npc_target, defender)
            equal(f.action_class, engine.classes.encounter)
            equal(f.action_parameter.GeneralActor1, defender)
            equal(f.player_target, nil)
            equal(actor:GetCharacterParameterComponent().bIsAttackNonCriminal, true)
            equal(f.terminated, 1)
        end)
    end)

    test("custom combat prefers a visible scoped defender over an occluded first worker", function()
        fixture(function(engine, member, f, _, _, scope)
            local hidden, visible = f:defender_at(200), f:defender_at(500)
            visible.visible = true
            f:workers(hidden, visible)
            f:weapon(true)
            truthy(engine:engage(scope, member))
            equal(f.npc_target, visible)
            equal(f.visibilityChecks, 2)
            local record = engine.records[member.groupId .. ":" .. member.index]
            equal(record.defenderSelection.eligible, 2)
            equal(record.defenderSelection.visible, true)
            truthy(engine:engage(scope, member))
            equal(f.visibilityChecks, 3)
            equal(f.terminated, 1)
            equal(record.defenderSelection.retained, true)
        end)
    end)

    test("custom combat never traces an unscoped defender and retains an occluded target without thrashing", function()
        fixture(function(engine, member, f, _, _, scope)
            local remote, hidden = f:defender_at(5000), f:defender_at(200)
            remote.visible = true
            f:workers(remote, hidden)
            f:weapon(true)
            truthy(engine:engage(scope, member))
            equal(f.npc_target, hidden)
            equal(f.visibilityChecks, 1)
            truthy(engine:engage(scope, member))
            equal(f.visibilityChecks, 2)
            equal(f.terminated, 1)
            local record = engine.records[member.groupId .. ":" .. member.index]
            equal(record.defenderSelection.visible, false)
            equal(record.defenderSelection.retained, true)
        end)
    end)

    test("custom combat can start weapon setup without calling visibility on an unready handle", function()
        fixture(function(engine, member, f, _, _, scope)
            local defender = f:defender_at(200)
            f:workers(defender)
            f:weapon(false)
            truthy(engine:engage(scope, member))
            equal(f.npc_target, defender)
            equal(f.visibilityChecks, nil)
            local record = engine.records[member.groupId .. ":" .. member.index]
            equal(record.defenderSelection.visible, nil)
            equal(record.defenderSelection.visibilityChecks, 0)
        end)
    end)

    test("custom combat stops at a visibility boundary error rather than choosing a fallback", function()
        fixture(function(engine, member, f, _, _, scope)
            f:workers(f:defender_at(200))
            f:weapon(true)
            f.visibilityFailure = true
            equal(engine:engage(scope, member), false)
            equal(f.npc_target, nil)
            equal(f.terminated, nil)
        end)
    end)

    test("custom combat replaces a completed action instead of trusting a stale requested mode", function()
        fixture(function(engine, member, f, _, _, scope)
            local defender = f:defender_at(200)
            defender.visible = true
            f:workers(defender)
            f:weapon(true)
            truthy(engine:engage(scope, member))
            equal(f.terminated, 1)
            f.now = 1001
            truthy(engine:engage(scope, member))
            equal(f.terminated, 1, "queued action was retried before its grace period")
            f.current_action = f:combat_action(defender, defender)
            f.now = 1005
            truthy(engine:engage(scope, member))
            equal(f.terminated, 1, "a running combat action was restarted")
            f.current_action = nil
            f.now = 1010
            truthy(engine:engage(scope, member))
            equal(f.terminated, 2)
            f.now = 1011
            truthy(engine:engage(scope, member))
            equal(f.terminated, 2)
        end)
    end)

    test("combat scope follows parent actions and checks the module target instead of the chosen-plan target", function()
        fixture(function(engine, member, f)
            local local_target, remote_target = f:defender_at(500), f:defender_at(5000)
            local combat = f:combat_action(local_target, local_target)
            f.current_action = { IsValid = function() return true end,
                IsA = function(_, path) return path == "/Script/AIModule.PawnAction" end, ParentAction = combat }
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state); equal(state.phase, "alive")
            combat.CombatModule.GetTargetActor = function() return remote_target end
            ok, state = engine:inspect(member.handle, member)
            truthy(ok, state); equal(state.phase, "escaped")
            equal(state.targetId, "1-2-3-4")
        end)
    end)

    test("unreadable combat ownership pauses participation then requests bounded owned cleanup", function()
        fixture(function(engine, member, f)
            f.current_action = f:combat_action(nil, nil, true)
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state); equal(state.phase, "inactive")
            f.now = 1061
            ok, state = engine:inspect(member.handle, member)
            truthy(ok, state); equal(state.phase, "escaped")
            equal(f.despawns, nil)
        end)
        fixture(function(engine, member, f)
            local action = f:combat_action(nil, nil)
            action.ParentAction, f.current_action = action, action
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state); equal(state.phase, "inactive")
        end)
    end)

    test("combat scope includes the child action which can receive ticks instead of its parent", function()
        fixture(function(engine,member,f)
            local target,remote=f:defender_at(500),f:defender_at(5000)
            local parent,child=f:combat_action(target,target),f:combat_action(target,target)
            parent.ChildAction,child.ParentAction=child,parent
            f.current_action=parent
            local ok,state=engine:inspect(member.handle,member)
            truthy(ok,state); equal(state.phase,"alive")
            child.CombatModule.GetTargetActor=function() return remote end
            ok,state=engine:inspect(member.handle,member)
            truthy(ok,state); equal(state.phase,"escaped"); equal(state.scopeReason,"combat-target")
            child.CombatModule.GetTargetActor=function() return target end
            child.ChildAction=parent
            ok,state=engine:inspect(member.handle,member)
            truthy(ok,state); equal(state.phase,"inactive")
        end)
    end)

    test("generated-class loading consumes the returned class and requires registry/load evidence", function()
        fixture(function(engine)
            local previous = rawget(_G, "LoadAsset")
            local class = { IsValid = function() return true end, IsClass = function() return true end,
                GetFName = function() return { ToString = function() return "Test_C" end } end }
            engine.bridge._static_find = function() return nil end
            _G.LoadAsset = function() return class, true, true end
            local ok, loaded = pcall(function() return engine:_class("/Game/Test.Test_C") end)
            _G.LoadAsset = previous
            truthy(ok, loaded); equal(loaded, class)
            _G.LoadAsset = function() return class, false, true end
            ok, loaded = pcall(function() return engine:_class("/Game/Test.Test_C") end)
            _G.LoadAsset = previous
            equal(ok, false); equal(loaded, "Custom assault scope is invalid")
        end)
    end)

    test("a capture that changes the manager lookup key releases only the exact original instance", function()
        fixture(function(engine, member, f, parameter, actor)
            truthy(engine:inspect(member.handle, member))
            actor.parameter, f.missing, f.capturing = parameter, true, true
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state); equal(state.phase, "capturing")
            f.capturing = false
            parameter.SaveParameter.OwnerPlayerUId.A = 7
            parameter.GetPalId = function() return { PlayerUId = { A = 7, B = 0, C = 0, D = 0 },
                InstanceId = { A = 1, B = 2, C = 3, D = 4 } } end
            ok, state = engine:inspect(member.handle, member)
            truthy(ok, state); equal(state.phase, "captured")
            equal(state.playerGuid, nil)
            equal(f.despawns, nil)
            parameter.GetPalId = function() return { PlayerUId = { A = 7, B = 0, C = 0, D = 0 },
                InstanceId = { A = 77, B = 2, C = 3, D = 4 } } end
            equal(engine:inspect(member.handle, member), false)
        end)
    end)

    test("exact parameter death survives actor detachment without querying torn-down components", function()
        fixture(function(engine, member, f)
            truthy(engine:inspect(member.handle, member))
            f.dead, f.actor_missing, f.destroying = true, true, true
            local before = #f.calls
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "dead")
            equal(state.targetId, "1-2-3-4")
            equal(state.actor, nil)
            for index = before + 1, #f.calls do
                equal(f.calls[index] == "custom-parameter-component", false)
                equal(f.calls[index] == "custom-capture-processing", false)
            end
        end)
    end)

    test("NPC handles may acquire their individual ID after the spawn call returns", function()
        fixture(function(engine, member, f)
            f.id_pending = true
            equal(engine:startup_identity(member).instanceGuid, nil)
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "pending")
            equal(f.reacquired, nil)
            equal(f.spawns, 1)
            f.id_pending = false
            ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            equal(state.phase, "alive")
            equal(engine:startup_identity(member).instanceGuid.A, 1)
            equal(f.spawns, 1)
            f.id_pending = true
            equal(engine:inspect(member.handle, member), false)
            equal(f.spawns, 1)
        end)
    end)

    test("startup floor and navigation require positive bounded physical results", function()
        fixture(function(engine, _, f)
            local pawn = {IsValid=function() return true end,GetCDO=function()
                return {IsValid=function() return f.cdo_missing ~= true end}
            end}
            engine.startupPawnClass = {IsValid=function() return false end}
            local lookups=0
            engine._class=function() lookups=lookups+1; return pawn end
            engine.utility.CanAdjustLocationToFloorFromCDO = function(_,world,class,point,up,out,short)
                equal(world,engine.world); equal(class,pawn); equal(up,100); equal(short,true)
                out.X,out.Y,out.Z=point.X,point.Y,point.Z+(f.floor_offset or 80)
                return f.floor_missing ~= true
            end
            engine.navigationLibrary={IsValid=function() return true end,
                K2_ProjectPointToNavigation=function(_,world,point,out,nav,filter,extent)
                    equal(world,engine.world); equal(nav,nil); equal(filter,nil); equal(extent.Z,300)
                    out.X,out.Y,out.Z=point.X+(f.nav_offset or 0),point.Y,point.Z
                    return f.nav_missing ~= true
                end}
            local point={X=100,Y=200,Z=300}
            equal(engine:startup_floor(engine.world,point).Z,380)
            f.floor_missing=true
            equal(engine:startup_floor(engine.world,point),nil)
            f.floor_missing=false; f.floor_offset=-10000
            equal(engine:startup_floor(engine.world,point),nil)
            equal(lookups,3)
            f.cdo_missing=true
            equal(pcall(engine.startup_floor,engine,engine.world,point),false)
            f.cdo_missing=false
            truthy(engine:startup_nav(engine.world,point))
            f.nav_missing=true
            equal(engine:startup_nav(engine.world,point),nil)
            f.nav_missing=false; f.nav_offset=10000
            equal(engine:startup_nav(engine.world,point),nil)
            engine.physicsLibrary={IsValid=function() return true end,
                LineTraceSingleByPalTraceType=function(_,world,start_point,end_point,kind,complex,material,trace_index,hit,draw)
                    equal(world,engine.world); equal(start_point.Z,800); equal(end_point.Z,-200)
                    equal(kind,3); equal(complex,false); equal(material,false); equal(trace_index,false); equal(draw,0)
                    return f.trace_hit == true
                end}
            equal(engine:startup_trace(engine.world,point),false)
            f.trace_hit=true
            equal(engine:startup_trace(engine.world,point),true)
            equal(f.spawns,1)
        end)
    end)

    test("action dispatch reacquires Blueprint classes instead of trusting cached wrappers", function()
        fixture(function(engine)
            engine._action_class = Native._action_class
            local lookups, seen = 0, {}
            engine._class = function(_, class_path)
                truthy(class_path:find("TravelToBaseCamp",1,true))
                lookups=lookups+1
                return {IsValid=function() return true end,type=function() return "UClass" end,generation=lookups}
            end
            local component = {IsValid=function() return true end,SetActionClassParameter=function(_, class)
                seen[#seen+1]=class.generation
                return {IsValid=function() return true end}
            end}
            engine:_set_action(component,"travel",{X=0,Y=0,Z=0},nil)
            engine:_set_action(component,"travel",{X=0,Y=0,Z=0},nil)
            equal(lookups,2); equal(seen[1],1); equal(seen[2],2)
        end)
    end)

    test("combat observation distinguishes missing weapon readiness from firing state", function()
        fixture(function(engine,member,f,_,actor,scope)
            local ok,state=engine:inspect(member.handle,member)
            truthy(ok,state)
            state.component.GetHPRate=function() return 1 end
            state.controller.WeaponHandle={IsValid=function() return true end,IsEndInitialize=function() return false end,
                GetRemainingBullet=function() error("unready weapon was queried") end}
            local action=f:combat_action(nil,nil)
            action.GetClass=function() return {IsValid=function() return true end,
                GetFName=function() return {ToString=function() return "BP_AIAction_NPC_Combat_Gun_C" end} end} end
            action.IsStopTick=false
            f.current_action=action
            engine._class=function() return {} end
            actor.GetComponentByClass=function() return {IsValid=function() return true end,GetHasWeapon=function() return nil end,
                CanShoot=function() error("unready shooter was queried") end} end
            local observed,result=engine:startup_combat_observation(scope,member)
            truthy(observed,result)
            equal(result.weaponHandle,true)
            equal(result.weaponReady,false)
            equal(result.equippedWeapon,false)
            equal(result.remainingBullets,nil)
            equal(result.canShoot,nil)
            equal(result.currentAction,"BP_AIAction_NPC_Combat_Gun_C")
        end)
    end)

    test("tick observation records sparse cadence and the component owner's clock without forcing delivery", function()
        fixture(function(engine,member,f)
            local ok,state=engine:inspect(member.handle,member)
            truthy(ok,state)
            f.tick_interval,f.paused=10,true
            state.controller.CustomTimeDilation=0.5
            local action=f:combat_action(nil,nil)
            local result=engine:_tick_observation(state,state.controller:GetAIActionComponent(),action)
            equal(result.intervalSeconds,10); equal(result.ownerTimeDilation,0.5)
            equal(result.actionPaused,true); equal(result.enabled,true); equal(result.childAction,false)
            equal(f.spawns,1); equal(f.terminated,nil)
        end)
    end)

    test("movement evidence reads the owned component and preserves signed vertical state", function()
        fixture(function(engine, member, _, _, actor)
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            local root = {IsValid=function() return true end}
            actor.RootComponent = root
            actor.CharacterMovement = {
                IsValid=function() return true end, IsA=function() return true end,
                GetOwner=function() return actor end, UpdatedComponent=root,
                MovementMode=3, CustomMovementMode=0, Velocity={X=0,Y=0,Z=900},
                IsMovingOnGround=function() return false end, IsFalling=function() return true end,
                IsFlying=function() return false end, GetCurrentAcceleration=function() return {X=0,Y=0,Z=0} end,
            }
            actor.GetPendingMovementInputVector=function() return {X=0,Y=0,Z=120} end
            actor.GetLastMovementInputVector=function() return {X=0,Y=0,Z=-80} end
            actor.K2_GetActorRotation=function() return {Pitch=0,Yaw=10,Roll=0} end
            local result=engine:_movement_observation(state)
            equal(result.mode,3); equal(result.falling,true); equal(result.flying,false)
            equal(result.velocityZ,900); equal(result.accelerationZ,0)
            equal(result.pendingInputZ,120); equal(result.lastInputZ,-80); equal(result.updatedRoot,true)
            actor.CharacterMovement.GetOwner=function() return {} end
            equal(pcall(engine._movement_observation,engine,state),false)
        end)
    end)

    test("startup arrival requires grounded feet near the actual navigation goal, not just matching XY", function()
        fixture(function(engine,member,f,_,actor,scope)
            scope.leashRadius=10000
            local capsule={IsValid=function() return true end,IsA=function() return true end,
                GetScaledCapsuleHalfHeight=function() return 80 end}
            actor.CapsuleComponent,actor.RootComponent=capsule,capsule
            engine._movement_observation=function()
                return {available=true,updatedRoot=true,grounded=not f.airborne,falling=f.airborne==true,flying=false}
            end
            f.location={X=500,Y=0,Z=1600}
            local ok,result=engine:startup_arrival(scope,member)
            truthy(ok,result); equal(result.arrived,false); equal(result.feetHeightDelta,1520)
            f.location.Z=80
            f.airborne=true
            ok,result=engine:startup_arrival(scope,member)
            truthy(ok,result); equal(result.arrived,false)
            f.airborne=false
            ok,result=engine:startup_arrival(scope,member)
            truthy(ok,result); equal(result.arrived,true); equal(result.feetHeightDelta,0)
        end)
    end)

    test("native spawns require exact class-specific floor and navigation approval and consume it once", function()
        fixture(function(engine, member, f, _, _, scope)
            local plan=util.shallow_copy(member)
            plan.index=2
            local floor_calls=0
            engine.startup_floor=function(_,world,point,character_id)
                equal(world,scope.world); equal(character_id,plan.characterId)
                floor_calls=floor_calls+1
                if f.floor_missing then return nil end
                return util.shallow_copy(point)
            end
            engine.startup_nav=function(_,world,point)
                equal(world,scope.world)
                if f.nav_missing then return nil end
                return util.shallow_copy(point)
            end
            engine._placement_surface=function() return {ready=true} end
            engine._placement_path=function() return {ready=true} end
            equal(engine:spawn(scope,plan),false)
            f.floor_missing=true
            local ok,result=engine:prepare_spawn(scope,plan)
            truthy(ok,result); equal(result.ready,false)
            equal(engine:spawn(scope,plan),false)
            equal(f.spawns,1)
            f.floor_missing=false; f.nav_missing=true
            ok,result=engine:prepare_spawn(scope,plan)
            truthy(ok,result); equal(result.reason,"navigation-unavailable")
            f.nav_missing=false
            ok,result=engine:prepare_spawn(scope,plan)
            truthy(ok,result); equal(result.ready,true)
            scope.positions[1].X=scope.positions[1].X+10
            equal(engine:spawn(scope,plan),false)
            truthy(engine:prepare_spawn(scope,plan))
            truthy(engine:spawn(scope,plan))
            equal(engine:spawn(scope,plan),false)
            equal(f.spawns,2)
            truthy(floor_calls>=5)
        end)
    end)

    test("native placement rejects an unreachable approach and selects only a validated in-base surface", function()
        fixture(function(engine,member,f,_,_,scope)
            local plan=util.shallow_copy(member)
            plan.index=2
            scope.positions[1]={X=900,Y=0,Z=0}
            engine.startup_floor=function(_,_,position) return util.shallow_copy(position) end
            engine.startup_nav=function(_,_,position) return util.shallow_copy(position) end
            local surface_checks,path_checks=0,0
            engine._placement_surface=function(_,actual,_,position)
                equal(actual,scope); surface_checks=surface_checks+1
                return {ready=surface_checks ~= 2,reason="water-or-unsupported-surface"}
            end
            engine._placement_path=function(_,actual,_,position)
                equal(actual,scope); path_checks=path_checks+1
                return {ready=position.X ~= 900,reason="path-unreachable"}
            end
            local result
            for _=1,9 do
                local ok
                ok,result=engine:prepare_spawn(scope,plan)
                truthy(ok,result)
                if not result.pending then break end
            end
            equal(result.ready,true); equal(result.mode,"in-base"); equal(result.fallbackReason,"path-unreachable")
            truthy(surface_checks>1); truthy(path_checks<surface_checks)
            equal(f.spawns,1)
            truthy(engine:spawn(scope,plan)); equal(f.spawns,2)
            local record=engine.records[plan.groupId..":"..plan.index]
            equal(record.placementMode,"in-base"); equal(record.goal.X,scope.origin.X)
            truthy(engine:startup_travel(scope,plan))
            for _,label in ipairs(f.calls) do equal(label=="custom-adjust-floor",false) end
        end)
    end)

    test("placement paths use the reflected validity predicate and reject partial or out-of-envelope routes", function()
        fixture(function(engine,member,f,_,_,scope)
            engine._placement_shape=function() return {radius=30,halfHeight=80} end
            engine.navigationLibrary={IsValid=function() return true end}
            local points={{X=100,Y=0,Z=0},{X=0,Y=0,Z=0}}
            local count,reads=2,0
            local array=setmetatable({GetArrayNum=function() return count end},{
                __index=function(_,index) reads=reads+1; return points[index] end,
            })
            local route={IsValid=function() return true end,IsA=function() return true end,PathPoints=array}
            local valid,partial=true,false
            engine.bridge._static_find=function(_,path)
                return setmetatable({IsValid=function() return true end},{__call=function(_,receiver,...)
                    if path:match(":FindPathToLocationSynchronously$") then
                        equal(receiver,engine.navigationLibrary)
                        local args=table.pack(...)
                        equal(args.n,5); equal(args[1],scope.world); equal(args[4],nil); equal(args[5],nil)
                        return route
                    end
                    equal(receiver,route)
                    if path:match(":IsValid$") then return valid end
                    if path:match(":IsPartial$") then return partial end
                    if path:match(":GetPathLength$") then return 100 end
                    error("unexpected reflected query")
                end})
            end
            local function query() return engine:_placement_path(scope,member,points[1],scope.origin) end
            truthy(query().ready); equal(reads,2)
            valid=false
            equal(query().reason,"path-unreachable"); equal(reads,2)
            valid,partial=true,true
            equal(query().reason,"path-partial"); equal(reads,2)
            partial=false; count=65
            equal(query().reason,"path-point-limit"); equal(reads,2)
            count=3; points[3]={X=2000,Y=0,Z=0}
            equal(query().reason,"path-outside-envelope")
            equal(f.spawns,1)
        end)
    end)

    test("placement shape qualifies only the exact upright owned CDO capsule and independent nav dimensions", function()
        fixture(function(engine,member)
            local function object(values)
                values.IsValid=function() return true end
                values.IsA=function() return true end
                return values
            end
            local capsule=object({RelativeScale3D={X=1,Y=1,Z=1},RelativeLocation={X=0,Y=0,Z=0},
                RelativeRotation={Pitch=0,Yaw=0,Roll=0},GetScaledCapsuleRadius=function() return 30 end,
                GetScaledCapsuleHalfHeight=function() return 80 end})
            local movement=object({WalkableFloorZ=0.7,NavAgentProps={AgentRadius=30,AgentHeight=160}})
            local cdo=object({CapsuleComponent=capsule,CharacterMovement=movement,
                K2_GetRootComponent=function() return capsule end,GetMovementComponent=function() return movement end})
            capsule.GetOwner=function() return cdo end
            movement.GetOwner=function() return cdo end
            cdo.StaticCharacterParameterComponent=object({MeshCapsuleRadius=30,MeshCapsuleHalfHeight=95,
                MeshRelativeLocation={X=0,Y=0,Z=-97},GetOwner=function() return cdo end})
            cdo.Mesh=object({RelativeLocation={X=0,Y=0,Z=-33},RelativeScale3D={X=1,Y=1,Z=1},
                GetOwner=function() return cdo end})
            engine._class=function() return object({GetCDO=function() return cdo end}) end
            local shape=engine:_placement_shape(member.characterId)
            equal(shape.radius,30); equal(shape.halfHeight,80); equal(shape.navContext,cdo)
            equal(shape.bodyProxy.centerOffsetZ,38.5); equal(shape.bodyProxy.halfHeight,118.5)
            equal(shape.bodyProxy.meshOffsetZ,-33); equal(shape.bodyProxy.authoredOffsetZ,-97)
            equal(shape.bodyProxy.lowerFootOffsetZ,-80); equal(shape.bodyProxy.templateOnly,true)
            movement.NavAgentProps.AgentHeight=100
            shape=engine:_placement_shape(member.characterId)
            equal(shape.navContext,nil); equal(shape.halfHeight,80)
            capsule.RelativeScale3D.Z=2
            local absent,reason=engine:_placement_shape(member.characterId)
            equal(absent,nil); equal(reason,"pawn-shape-transform")
            capsule.RelativeScale3D.Z=1
            capsule.GetOwner=function() return {} end
            absent,reason=engine:_placement_shape(member.characterId)
            equal(absent,nil); equal(reason,"pawn-shape-ownership")
        end)
    end)

    test("copied hit byte one sets both flags but independent clear start and valid support can proceed",function()
        support_fixture(function(_,f)
            f.hitByte=1
            local ok,result=f:probe()
            truthy(ok,result); equal(result.ready,true)
            equal(result.support.copiedHitFlags.trust,"UNTRUSTED")
            equal(result.support.copiedHitFlags.blockingHit,true); equal(result.support.copiedHitFlags.startPenetrating,true)
            equal(result.support.startPenetrating,nil); equal(result.support.blockingHit,nil)
            equal(result.support.startOverlap.classification,"CLEAR"); equal(result.support.startOverlap.components,0)
            equal(result.support.startOffsetZ,5); equal(f.supportSweeps,1); equal(f.clearanceQueries,1)
            equal(result.support.contactDelta.Z,0); equal(result.support.impactNormal.Z,1)
            equal(result.support.Component,nil); equal(result.support.ActorName,nil); equal(result.support.Location,nil)
            ok,result=f:probe(true)
            truthy(ok,result); equal(result.ready,false); equal(result.reason,"dry-clearance-unqualified")
            equal(#f.overlapOutputs,2); equal(f.spawns,1)
            f.hitByte=0
            ok,result=f:probe()
            truthy(ok,result); equal(result.ready,true)
            equal(result.support.copiedHitFlags.blockingHit,false)
        end)

        test("copied weak hit components are resolved once without the generic unwrap helper",function()
            support_fixture(function(engine,f)
                local previous=engine.a.unwrap
                local weak_unwraps=0
                engine.a.unwrap=function(value)
                    if type(value)=="table" and type(value.get)=="function" then
                        weak_unwraps=weak_unwraps+1
                        return value:get()
                    end
                    return previous(value)
                end
                local ok,result=f:probe()
                truthy(ok,result); equal(result.ready,true); equal(weak_unwraps,0)
                equal(f.clearanceQueries,1)
            end)
        end)
    end)

    test("support contact metrics retain signed TOI evidence without changing support acceptance",function()
        for _,delta in ipairs({0,0.000023,-0.000023}) do
            support_fixture(function(_,f)
                f.contact={X=f.point.X,Y=f.point.Y,Z=f.point.Z-delta}
                f.hitTime=(5+delta)/10; f.hitDistance=5+delta
                local ok,result,witness=f:probe()
                truthy(ok,result); equal(result.ready,true)
                local contact=result.support.contact
                equal(contact.diagnosticOnly,true); equal(contact.contactExceptionEnabled,false)
                truthy(contact.positiveTimeDistance); equal(contact.traceEchoAgreement,true)
                truthy(contact.reconstructionErrorCm<0.000001)
                equal(contact.atOrBeforeReportedTOI,delta>=0)
                truthy(math.abs(contact.signedProposedMinusHitZ-delta)<0.00000001)
                truthy(witness.component); equal(result.support.component,nil); equal(result.support.witness,nil)
                equal(f.supportSweeps,1); equal(f.clearanceQueries,1); equal(#f.overlapOutputs,1)
            end)
        end
        support_fixture(function(_,f)
            f.hitTime,f.hitDistance=0,0
            local ok,result=f:probe()
            truthy(ok,result); equal(result.ready,true); equal(result.support.contact.positiveTimeDistance,false)
        end)
        support_fixture(function(_,f)
            f.badTraceEcho=true
            local ok,result=f:probe()
            truthy(ok,result); equal(result.ready,true); equal(result.support.contact.traceEchoAgreement,false)
        end)
        support_fixture(function(_,f)
            f.hitTime=0.4
            local ok,result=f:probe()
            truthy(ok,result); equal(result.ready,true); equal(result.support.contact.reconstructionAgreement,false)
        end)
    end)

    test("start overlaps use the actual ground trace response and never a pawn profile or packed flag",function()
        support_fixture(function(_,f)
            f.hitByte=0
            f.startComponents={f:component("static",2)}
            local ok,result=f:probe()
            truthy(ok,result); equal(result.ready,false); equal(result.reason,"support-penetrating")
            equal(result.support.startOverlap.classification,"BLOCKED"); equal(result.support.startOverlap.blockers,1)
            equal(result.support.copiedHitFlags,nil); equal(f.supportSweeps,0); equal(f.clearanceQueries,0)
            equal(f.responseQueries,1)
        end)
        support_fixture(function(_,f)
            f.startComponents={f:component("static",0),f:component("shape",1)}
            local ok,result=f:probe()
            truthy(ok,result); equal(result.ready,true)
            equal(result.support.startOverlap.blockers,0); equal(f.responseQueries,3)
        end)
    end)

    test("start overlap fails closed on unknown multibody query state and response semantics",function()
        for _,kind in ipairs({"instanced","skinned","unknown","disabled","response"}) do
            support_fixture(function(_,f)
                local component=f:component((kind=="disabled" or kind=="response") and "static" or kind,0)
                if kind=="disabled" then component.enabled=2 end
                if kind=="response" then component.response=3 end
                f.startComponents={component}
                local ok,result=f:probe()
                truthy(ok,result); equal(result.ready,false); equal(result.reason,"support-start-overlap-unqualified")
                equal(result.support.startOverlap.classification,"UNSUPPORTED")
                equal(result.support.startOverlap.unqualifiedBodies,1); equal(f.supportSweeps,0)
            end)
        end
    end)

    test("start overlap rejects oversized malformed foreign and worldless results before a support sweep",function()
        support_fixture(function(_,f)
            for index=1,129 do f.startComponents[index]=f:component("static",0) end
            local ok,result=f:probe()
            truthy(ok,result); equal(result.ready,false); equal(result.reason,"support-start-overlap-over-cap")
            equal(result.support.startOverlap.components,129); equal(f.responseQueries,0); equal(f.supportSweeps,0)
        end)
        for _,kind in ipairs({"foreign-component","foreign-owner","worldless-owner","wrong-owner","sparse","boolean","channel"}) do
            support_fixture(function(_,f)
                local component=f:component("static",0)
                f.startComponents={component}
                local world={IsValid=function() return true end,IsA=function() return true end}
                if kind=="foreign-component" then component.world=world end
                if kind=="foreign-owner" or kind=="worldless-owner" then
                    f.levels[component.owner]={IsValid=function() return true end,IsA=function() return true end,
                        OwningWorld=kind=="foreign-owner" and world or nil}
                end
                if kind=="wrong-owner" then component.owner.IsA=function() return false end end
                if kind=="sparse" then f.startComponents={[2]=component} end
                if kind=="boolean" then f.overlapReturn=false end
                if kind=="channel" then f.groundChannel=32 end
                equal(f:probe(),false); equal(f.supportSweeps,0)
                local calls=#f.calls
                equal(f:probe(),false); equal(#f.calls,calls)
            end)
        end
    end)

    test("independent start clearance does not replace support normal displacement slope or final clearance",function()
        for _,case in ipairs({
            {field="sweepFound",value=false,reason="no-solid-support"},
            {field="normal",value=0.2,reason="support-not-walkable"},
            {field="contact",value={X=100,Y=0,Z=20},reason="support-moved"},
            {field="slopeBehavior",value=1,reason="support-slope-override"},
            {field="missingComponent",value=true,reason="support-component-unavailable"},
            {field="clearanceBlocked",value=true,reason="capsule-obstructed"},
        }) do
            support_fixture(function(_,f)
                f[case.field]=case.value
                local ok,result=f:probe()
                truthy(ok,result); equal(result.ready,false); equal(result.reason,case.reason)
                equal(result.support.startOverlap.classification,"CLEAR")
                equal(f.supportSweeps,1)
            end)
        end
        support_fixture(function(_,f)
            f.contact={X=100000,Y=200000,Z=300000}
            local ok,result=f:probe()
            truthy(ok,result); equal(result.ready,false); equal(result.reason,"support-moved")
            equal(result.support.contactDelta,nil)
        end)
    end)

    test("a native start-overlap failure cannot retry or proceed into the support sweep",function()
        support_fixture(function(_,f)
            f.overlapFault=true
            equal(f:probe(),false); equal(f.supportSweeps,0)
            local calls=#f.calls
            equal(f:probe(),false); equal(#f.calls,calls); equal(#f.overlapOutputs,1)
        end)
    end)

    test("native startup qualifies support overlap contracts before any survey or candidate",function()
        fixture(function(engine)
            local signatures={}
            local function fields(expected)
                local result={}
                for name in pairs(expected) do result[name]={field={}} end
                return result
            end
            engine._signature=function(_,name,expected) signatures[name]=expected; return fields(expected) end
            engine._struct=function(_,_,_,expected) return fields(expected) end
            truthy(engine:qualify())
            local overlap=signatures["/Script/Engine.KismetSystemLibrary:CapsuleOverlapComponents"]
            equal(overlap.CapsulePos[2],8); equal(overlap.Radius[2],32); equal(overlap.HalfHeight[2],36)
            equal(overlap.ObjectTypes[1],"ArrayProperty"); equal(overlap.ObjectTypes[2],40)
            equal(overlap.OutComponents[2],80); equal(overlap.ReturnValue[2],96)
            local converter=signatures["/Script/Pal.PalUtility:GetEngineCollisionChannelByPalTraceType"]
            equal(converter.type[1],"EnumProperty"); equal(converter.ReturnValue[2],1)
            truthy(signatures["/Script/Engine.PrimitiveComponent:GetCollisionEnabled"])
            local response=signatures["/Script/Engine.PrimitiveComponent:GetCollisionResponseToChannel"]
            equal(response.Channel[2],0); equal(response.ReturnValue[2],1)
        end)
    end)

    test("floor qualification resolves the planned pawn class and never falls back for an unknown bounty", function()
        fixture(function(engine)
            local expected=require("ped.bounties").pawn_class("BOSS_Ninja")
            local class={IsValid=function() return true end,GetCDO=function() return {IsValid=function() return true end} end}
            local lookups=0
            engine._class=function(_,class_path)
                equal(class_path,expected); lookups=lookups+1; return class
            end
            engine.utility.CanAdjustLocationToFloorFromCDO=function(_,_,pawn,point,_,out)
                equal(pawn,class)
                out.X,out.Y,out.Z=point.X,point.Y,point.Z
                return true
            end
            truthy(engine:startup_floor(engine.world,{X=0,Y=0,Z=0},"BOSS_Ninja"))
            equal(pcall(engine.startup_floor,engine,engine.world,{X=0,Y=0,Z=0},"not-a-bounty"),false)
            equal(lookups,1)
        end)
    end)

    test("fire-state evidence uses the actual action target and separates aim from shoot eligibility", function()
        fixture(function(engine, member, f, _, actor, scope)
            local ok, state = engine:inspect(member.handle, member)
            truthy(ok, state)
            state.component.GetHPRate = function() return 1 end
            local target, requested = f:defender_at(200), f:defender_at(500)
            f:weapon(true)
            local weapon = state.controller.WeaponHandle
            weapon.ShooterHuman = actor
            weapon.GetRemainingBullet = function() return 30 end
            weapon.IsMagazineEmpty = function() return false end
            target.visible = true
            local function class(name)
                return {IsValid=function() return true end,GetFName=function() return {ToString=function() return name end} end}
            end
            local fire = {IsValid=function() return true end,Timer=-0.1,Interval=0.1,ShootCount=0,
                ShootAbleTimer=0,temp_DeltaTime=0.25,GetClass=function() return class("BP_AINPC_CombatGunState_FireMove_C") end}
            local action = f:combat_action(target,target)
            action.SelfActor, action.IsStopTick = actor,false
            action.GetClass=function() return class("BP_AIAction_NPC_Combat_Gun_C") end
            action.StateMachine={IsValid=function() return true end,GetCurrentState=function() return fire end}
            f.current_action=action
            engine.records[member.groupId..":"..member.index].target=requested
            engine._class=function() return {} end
            local shooter={IsValid=function() return true end,NPCWeapon=weapon,GetHasWeapon=function() return weapon end,
                CanShoot=function() return true end,CanAim=function() return false end}
            for _,method in ipairs({"IsShooting","IsReloading","IsAiming","IsRequestAiming","IsPlayShootingAnimation"}) do
                shooter[method]=function() return false end
            end
            shooter.IsAiming_Layered=function(_,priority) equal(priority,0); return false end
            shooter.IsRequestAiming_Layered=function(_,priority) equal(priority,0); return true end
            actor.GetComponentByClass=function() return shooter end
            engine.utility.InFanShap=function(_,self_actor,actual,degree)
                equal(self_actor,actor); equal(actual,target); equal(degree,5); return true
            end
            engine.utility.InFanShapAimTarget=function(_,_,actual) equal(actual,target); return false end
            engine.utility.IsAIAttackAbleByPlayerCamera=function(_,_,actual) equal(actual,target); return true end
            local observed,result=engine:startup_combat_observation(scope,member)
            truthy(observed,result)
            equal(result.fireState.Timer,-0.1); equal(result.fireState.ShootCount,0)
            equal(result.outerTimer,1); equal(result.outerDeltaTime,0.25)
            equal(result.tick.stateOuterMatches,true); equal(result.tick.actionActive,true)
            equal(result.requestedTargetMatches,false); equal(result.actualTargetDistanceCm,200)
            equal(result.storedShooterMatches,true); equal(result.canShoot,true); equal(result.canAim,false)
            equal(result.rootFacing,true); equal(result.aimFacing,false)
            equal(result.layerZeroAiming,false); equal(result.layerZeroRequest,true)
            equal(f.spawns,1); equal(f.despawns,nil); equal(f.action_parameter,nil)
        end)
    end)
end
