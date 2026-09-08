return function(test, equal, truthy)
    local Config = require("ped.config")
    local Director = require("ped.director")
    local Bridge = require("ped.palworld")
    local util = require("ped.util")

    local function fixture(callback, use_core)
        local config = Config.defaults()
        config.capabilities.startAllInvasions = true
        config.capabilities.observeCombat = true
        config.capabilities.observeInvasions = true
        config.capabilities.substituteBountyMembers = true
        local state = { now = 1000, records = {}, messages = {}, cleanup = 0, handles = {}, phases = {}, spawns = {}, despawns = 0 }
        local bridge = {
            preflight_environment = function() return true end,
            preflight_start = function() return true end,
            begin_event_discovery = function()
                return { "base-a", "base-b" }, { { uid = "private-player", name = "Player" } }
            end,
            send_chat = function(_, message) state.messages[#state.messages + 1] = message; return true end,
            announce = function(_, message) state.messages[#state.messages + 1] = message; return true end,
            list_online_players = function() return { { uid = "private-player", name = "Player" } } end,
            active_invasion_count = function() return 0 end,
            end_event_tracking = function() state.closed = true end,
            close_custom_assault = function()
                if state.cleanup == 0 then equal(state.records[#state.records], "custom_cleanup_intent") end
                state.cleanup = state.cleanup + 1
                if state.on_cleanup then state.on_cleanup() end
                if state.fail_cleanup then return false, "owned actor cleanup is pending" end
                if state.defer_cleanup and not state.cleanup_confirmed then return true, "pending" end
                return true
            end,
        }
        local director
        bridge.start_all_invasions = function()
            local planned, reason = director:on_custom_assault_record("custom_assault_plan", { members = {
                { index = 1, baseId = "base-a", groupId = "group-a", slot = 1, characterId = "BOSS_Ninja", name = "Fumble", level = 30 },
                { index = 2, baseId = "base-b", groupId = "group-b", slot = 1, characterId = "BOSS_Hunter_Rifle", name = "Hawk", level = 30 },
            } })
            if not planned then return false, reason end
            director:on_composition_result("base-a", 1, 1, nil, { "BOSS_Ninja" })
            director:on_composition_result("base-b", 1, 1, nil, { "BOSS_Hunter_Rifle" })
            return true, { custom = true, requested = 2, phase = "custom", requests = {
                { baseId = "base-a", phase = "custom", status = "custom_spawn_queued", targetIndex = 1, targetCount = 2 },
                { baseId = "base-b", phase = "custom", status = "custom_spawn_queued", targetIndex = 2, targetCount = 2 },
            } }
        end
        if use_core then
            config.customAssault.membersPerBase, config.customAssault.spawnBatchSize = 2, 2
            local engine = {}
            function engine:spawn(scope, plan)
                equal(scope.baseId, plan.baseId)
                local handle = { index = plan.index, actor = { key = "custom-target-" .. plan.index } }
                state.handles[plan.index] = handle
                state.spawns[#state.spawns + 1] = plan.baseId
                return true, handle
            end
            function engine:inspect(handle, plan)
                local phase = state.phases[plan.index] or "alive"
                if phase == "missing" or phase == "captured" or phase == "despawning" then return true, { phase = phase } end
                return true, { phase = phase, actor = not state.scalar_death and handle.actor or nil, targetId = handle.actor.key,
                    characterId = plan.characterId, healthBudget = 1000,
                    instanceGuid = { A = plan.index, B = 2, C = 3, D = 4 },
                    playerGuid = { A = 0, B = 0, C = 0, D = 0 } }
            end
            function engine:engage(_, plan)
                state.engages = (state.engages or 0) + 1
                return true, state.unavailable_base == plan.baseId and "unavailable" or nil
            end
            function engine:despawn(_, plan)
                state.despawns = state.despawns + 1
                state.phases[plan.index] = state.defer_cleanup and "despawning" or "missing"
                return true, state.defer_cleanup and "pending" or "despawned"
            end
            function engine:cleanup_recovered(members, on_outcome)
                for _, member in pairs(members) do
                    if member.spawnRequested then state.despawns = state.despawns + 1 end
                    local accepted, reason = on_outcome(member.index, member.spawnRequested and "despawned" or "cancelled")
                    if not accepted then return false, reason end
                end
                return true, "complete"
            end
            function engine:actorKey(actor) return actor.key end
            function engine:sameActor(left, right) return left == right end
            bridge.config, bridge.custom_engine = config, engine
            bridge.clock = function() return state.now end
            bridge.native_start_guard = function() return true end
            bridge._custom_engine = function() return engine end
            bridge.start_all_invasions = Bridge._start_custom_assault
            bridge.close_custom_assault = Bridge.close_custom_assault
            bridge.has_custom_assault_members = Bridge.has_custom_assault_members
            bridge.poll_invasion_progress = Bridge.poll_invasion_progress
            bridge.begin_event_discovery = function(_, profile, occurrence)
                bridge.profile_id, bridge.custom_occurrence_id = profile, occurrence
                bridge.event_open, bridge.owned_groups = true, {}
                bridge.expected_bases = { ["base-a"] = true, ["base-b"] = true }
                bridge.custom_targets = { { id = "base-a", scope = { baseId = "base-a" } },
                    { id = "base-b", scope = { baseId = "base-b" } } }
                return { "base-a", "base-b" }, { { uid = "private-player", name = "Player" } }
            end
            bridge.end_event_tracking = function()
                equal(bridge:has_custom_assault_members(), false, "tracking closed before owned cleanup")
                state.closed = true
            end
        end
        director = Director.new({
            config = config, bridge = bridge, clock = function() return state.now end,
            logger = { info = function() end, warn = function() end, error = function() end },
            store = { load_snapshot = function() return nil end,
                save_snapshot = function(_, snapshot) state.saved = util.deep_copy(snapshot); return true end,
                append = function(_, kind)
                    state.records[#state.records + 1] = kind
                    return kind ~= state.fail_record
                end },
        })
        bridge.director, bridge.logger = director, director.logger
        truthy(director:arm_start("test", "all-bounty", 0, true, { requesterUid = "private-player" }))
        callback(director, bridge, state)
    end

    test("all-bounty director uses simultaneous custom routing without native probe fanout", function()
        fixture(function(director, _, state)
            local event = director.state.event
            equal(event.backend, "custom-assault")
            equal(event.nativeRoute, "custom-assault")
            equal(event.fanoutDispatched, true)
            equal(event.customAssault.planned, 2)
            equal(event.bases["base-a"].dispatchStatus, "custom_spawn_queued")
            equal(event.bases["base-b"].dispatchStatus, "custom_spawn_queued")
            equal(event.confirmedBaseCount, 0)
            truthy(director:on_invasion_start("base-a", "group-a"))
            truthy(director:on_invasion_start("base-b", "group-b"))
            equal(event.confirmedBaseCount, 2)
            truthy(table.concat(state.messages, "\n"):find("CUSTOM ASSAULT STARTED", 1, true))
            equal(table.concat(state.messages, "\n"):find("A native invasion is confirmed", 1, true), nil)
        end)
    end)

    test("custom spawn identities and capture outcomes persist without overwriting the plan", function()
        fixture(function(director)
            truthy(director:on_custom_assault_record("custom_spawn_intent", { index = 1, baseId = "base-a" }))
            truthy(director:on_custom_assault_record("custom_member_initialized", {
                index = 1, baseId = "base-a", characterId = "BOSS_Ninja", targetId = "private-target",
                healthBudget = 1000, instanceGuid = { A = 1, B = 2, C = 3, D = 4 },
                playerGuid = { A = 0, B = 0, C = 0, D = 0 },
            }))
            local member = director.state.event.customAssault.members["1"]
            equal(member.spawnRequested, true)
            equal(member.status, "initialized")
            equal(member.playerGuid.A, 0)
            equal(member.instanceGuid.D, 4)
            equal(director:on_custom_assault_record("custom_spawn_returned", { index = 1, baseId = "base-b" }), false)
            equal(member.baseId, "base-a")
        end)
    end)

    test("custom assault completion journals cleanup before final settlement", function()
        fixture(function(director, _, state)
            truthy(director:on_invasion_start("base-a", "group-a"))
            truthy(director:on_invasion_start("base-b", "group-b"))
            truthy(director:on_custom_assault_finished("base-a", "group-a", "completed"))
            truthy(director:on_custom_assault_finished("base-b", "group-b", "completed"))
            state.now = 1020
            director:tick()
            equal(state.cleanup, 1)
            equal(director.state.status, "completed")
            equal(director.state.event.customCleanupComplete, true)
            equal(state.closed, true)
        end)
    end)

    test("failed custom cleanup preserves recovery and does not falsely close tracking", function()
        fixture(function(director, _, state)
            state.fail_cleanup = true
            local ok = director:abort("operator")
            equal(ok, false)
            equal(director.state.status, "recovery_required")
            equal(director.state.event.customCleanupComplete, nil)
            equal(state.closed, nil)
            equal(state.cleanup, 1)
        end)
    end)

    test("failed custom journal transition stops the event for recovery", function()
        fixture(function(director, _, state)
            state.fail_record = "custom_spawn_intent"
            equal(director:on_custom_assault_record("custom_spawn_intent", { index = 1, baseId = "base-a" }), false)
            equal(director.state.status, "recovery_required")
            equal(director.state.event.customAssault.members["1"].spawnRequested, true)
        end)
    end)

    test("custom abort waits for native cleanup completion without claiming an early finish", function()
        fixture(function(director, _, state)
            state.defer_cleanup = true
            truthy(director:abort("operator"))
            equal(director.state.event.customCleanupComplete, nil)
            truthy(director.state.event.customCleanupPending)
            equal(director:_active_event(), nil)
            equal(state.closed, nil)
            state.cleanup_confirmed = true
            state.now = 1001
            director:tick()
            equal(director.state.status, "aborted")
            equal(director.state.event.customCleanupComplete, true)
            equal(state.closed, true)
            equal(state.cleanup, 2)
        end)
    end)

    test("custom resolve resumes only after delayed cleanup and settles once", function()
        fixture(function(director, _, state)
            truthy(director:on_invasion_start("base-a", "group-a"))
            state.defer_cleanup = true
            truthy(director:resolve("operator"))
            equal(director.state.status, "resolving")
            equal(state.closed, nil)
            state.cleanup_confirmed = true
            state.now = 1001
            director:tick()
            equal(director.state.status, "completed")
            equal(state.closed, true)
            equal(state.cleanup, 2)
        end)
    end)

    test("custom cleanup can unrank composition while resolving but rejects a stale occurrence", function()
        fixture(function(director, _, state)
            truthy(director:on_invasion_start("base-a", "group-a"))
            local event = director.state.event
            state.on_cleanup = function()
                equal(director:_active_event(), nil)
                equal(director:on_custom_assault_composition("base-a", {}, "cancelled", "another-occurrence"), false)
                truthy(director:on_custom_assault_composition("base-a", {}, "cancelled", event.id))
                equal(event.bases["base-a"].ranked, false)
            end
            truthy(director:resolve("operator"))
            equal(director.state.status, "completed")
            equal(event.compositionFailed, true)
            equal(director:on_custom_assault_composition("base-a", {}, nil, event.id), false)
        end)
    end)

    test("custom start timeout retains tracking until its owned cleanup finishes", function()
        fixture(function(director, bridge, state)
            bridge.capture_start_timeout = function() error("custom timeout must not inspect native incidents") end
            state.defer_cleanup = true
            state.now = director.state.event.startConfirmationDeadline + 1
            director:tick()
            equal(state.cleanup, 1)
            equal(state.closed, nil)
            equal(director.state.status, "starting")
            equal(director.state.event.customCleanupPending.resume, "fail_start")
            state.cleanup_confirmed = true
            state.now = state.now + 1
            director:tick()
            equal(director.state.status, "aborted")
            equal(director.state.event.customCleanupComplete, true)
            equal(director.state.event.bases["base-a"].status, "custom_start_missing")
            equal(state.closed, true)
        end)
    end)

    test("native discovery expiry does not reclassify pending custom bases", function()
        fixture(function(director, _, state)
            truthy(director:on_invasion_start("base-a", "group-a"))
            state.now = director.state.event.discoveryDeadline + 1
            director:tick()
            equal(director.state.event.bases["base-b"].status, "pending")
            equal(state.cleanup, 0)
            equal(director.state.status, "active")
        end)
    end)

    test("a failed asynchronous cleanup stops automatic attempts and preserves recovery", function()
        fixture(function(director, _, state)
            state.defer_cleanup = true
            truthy(director:abort("operator"))
            state.fail_cleanup = true
            director:tick()
            equal(director.state.status, "recovery_required")
            equal(director.state.event.customCleanupPending, nil)
            director:tick()
            equal(state.cleanup, 2)
            equal(state.closed, nil)
        end)
    end)

    test("restored custom cleanup requires fresh operator intent rather than automatic replay", function()
        fixture(function(director, bridge, state)
            state.defer_cleanup = true
            truthy(director:abort("operator"))
            local saved = util.deep_copy(state.saved)
            local restored = Director.new({
                config = director.config, bridge = bridge, clock = function() return state.now end,
                logger = director.logger,
                store = { load_snapshot = function() return saved end, save_snapshot = function() return true end,
                    append = function() return true end },
            })
            equal(restored.state.status, "recovery_required")
            truthy(restored.state.event.customCleanupPending)
            restored:tick()
            equal(state.cleanup, 1)
            equal(state.closed, nil)
        end)
    end)

    test("real custom core interleaves both bases and resolves through scoped composition cleanup", function()
        fixture(function(director, bridge, state)
            equal(#state.spawns, 0)
            director:tick()
            equal(#state.spawns, 2)
            equal(state.spawns[1], "base-a")
            equal(state.spawns[2], "base-b")
            equal(director.state.event.confirmedBaseCount, 2)
            truthy(director:resolve("operator"))
            equal(state.despawns, 2)
            equal(bridge.custom_assault.closed, true)
            equal(director.state.status, "completed")
            equal(director.state.event.compositionFailed, true)
            equal(state.closed, true)
        end, true)
    end)

    test("real custom core abort waits for all pending despawns without repeating native cleanup", function()
        fixture(function(director, bridge, state)
            director:tick()
            director:tick()
            state.defer_cleanup = true
            truthy(director:abort("operator"))
            equal(state.despawns, 4)
            equal(bridge.custom_assault.closed, false)
            equal(state.closed, nil)
            director:tick()
            equal(state.despawns, 4)
            for index = 1, 4 do state.phases[index] = "missing" end
            state.now = state.now + 1
            director:tick()
            equal(state.despawns, 4)
            equal(bridge.custom_assault.closed, true)
            equal(director.state.status, "aborted")
            equal(state.closed, true)
        end, true)
    end)

    test("real custom core starts another base without waiting for the first to initialize", function()
        fixture(function(director, _, state)
            state.phases[1] = "pending"
            director:tick()
            equal(#state.spawns, 2)
            equal(director.state.event.bases["base-a"].status, "pending")
            equal(director.state.event.bases["base-b"].status, "active")
            equal(director.state.event.confirmedBaseCount, 1)
            equal(director.state.event.customAssault.members["1"].instanceGuid.A, 1)
            equal(director.state.event.customAssault.members["1"].healthBudget, nil)
        end, true)
    end)

    test("failed start-confirmation persistence halts real custom work with owned outcomes retained", function()
        fixture(function(director, bridge, state)
            state.fail_record = "event_start_confirmed"
            director:tick()
            equal(director.state.status, "recovery_required")
            equal(state.engages, 1)
            equal(#state.spawns, 2)
            truthy(bridge:has_custom_assault_members())
            director:tick()
            equal(#state.spawns, 2)
            equal(state.closed, nil)
        end, true)
    end)

    test("a never-confirmed terminal custom base does not prevent settlement of the other base", function()
        fixture(function(director, bridge, state)
            state.phases[1], state.phases[3] = "captured", "captured"
            director:tick()
            director:tick()
            equal(director.state.event.bases["base-a"].status, "custom_start_failed")
            equal(director.state.event.confirmedBaseCount, 1)
            state.scalar_death = true
            state.phases[2], state.phases[4] = "dead", "dead"
            state.now = 1001
            director:tick()
            equal(bridge:has_custom_assault_members(), false)
            equal(director.state.event.bases["base-b"].status, "completed")
            state.now = 1020
            director:tick()
            equal(director.state.status, "completed")
            equal(director.state.event.confirmedBaseCount, 1)
        end, true)
    end)

    test("resolving a recovered custom event closes and un-ranks cleaned targets before rewards", function()
        fixture(function(director, bridge, state)
            director:tick()
            director:tick()
            local target_id = state.handles[1].actor.key
            truthy(director:on_damage({
                record_sequence = 1, target_id = target_id, base_id = "base-a",
                group_id = director.state.event.bases["base-a"].groupId, health_budget = 1000, actual_damage = 1000,
                source_kind = "direct_player", player_uid = "private-player", player_name = "Player",
            }))
            truthy(director:_persist("checkpoint", {}))
            local saved = util.deep_copy(state.saved)
            bridge.custom_assault = nil
            local restored = Director.new({
                config = director.config, bridge = bridge, clock = function() return state.now end,
                logger = director.logger,
                store = { load_snapshot = function() return saved end, save_snapshot = function() return true end,
                    append = function() return true end },
            })
            bridge.director = restored
            equal(restored.state.status, "recovery_required")
            truthy(restored:resolve("operator"))
            local target = restored.scoreboard.state.targets[target_id]
            equal(target.closed, true)
            equal(target.ranked, false)
            equal(restored.state.status, "completed")
            equal(util.count(restored.rewards.state.obligations), 0)
            equal(state.despawns, 4)
        end, true)
    end)

    test("an unavailable local action cleans that custom member without confirming or blocking other bases", function()
        fixture(function(director, _, state)
            state.unavailable_base = "base-a"
            director:tick()
            director:tick()
            equal(state.despawns, 2)
            equal(director.state.event.bases["base-a"].status, "custom_start_failed")
            equal(director.state.event.bases["base-b"].status, "active")
            equal(director.state.event.confirmedBaseCount, 1)
            equal(director.state.status, "active")
        end, true)
    end)
end
