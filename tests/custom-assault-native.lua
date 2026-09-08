return function(test, equal, truthy)
    local Native = require("ped.custom_assault_native")
    local Config = require("ped.config")
    local util = require("ped.util")

    local function recovered(engine, members)
        return engine:cleanup_recovered(members, function() return true end)
    end

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
        local world = object()
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
        local parameter = object({
            SaveParameter = { IsPlayer = false, OwnerPlayerUId = util.deep_copy(zero), OldOwnerPlayerUIds = {} },
            GetPalId = function() return identity end,
            GetCharacterID = function() return f.wrong_character and "UnrelatedCharacter" or "BOSS_Hunter_Rifle" end,
            GetMaxHP = function() return 1000 end,
            IsDead = function() return f.dead end,
        })
        local actor = object({
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
                IsA = function(_, path) return path == "/Script/AIModule.PawnAction" or path:find("NPC_CombatBase", 1, true) ~= nil end,
                TargetActor = target,
                CombatModule = not without_module and object({ GetTargetActor = function() return module_target end }) or nil,
            })
        end
        local ok, result = engine:spawn(scope, member)
        truthy(ok, result)
        member.handle = result
        callback(engine, member, f, parameter, actor, scope)
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
        fixture(function(engine, member, f, _, _, scope)
            local defender = f:defender_at(500)
            scope.players = { { controller = { IsValid = function() return true end, GetPawn = function() return defender end } } }
            truthy(engine:engage(scope, member))
            equal(f.npc_target, defender)
            equal(f.action_class, engine.classes.encounter)
            equal(f.action_parameter.GeneralActor1, defender)
            equal(f.player_target, nil)
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
end
