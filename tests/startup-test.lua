return function(test, equal, truthy)
    local Startup = require("ped.startup_test")
    local Shape = require("ped.shape_qualification")
    local util = require("ped.util")
    local function fixture(case)
        local f = { now = 1000, records = {}, spawns = 0, despawns = 0, travels = 0, phases = {}, actors = {} }
        local store = { sequence = 0 }
        function store:append(kind, _, state)
            f.records[#f.records + 1] = kind
            if f.fail_record == kind then return false end
            self.sequence = self.sequence + 1
            f.saved = util.deep_copy(state)
            return true
        end
        function store:save_snapshot() return not f.fail_snapshot end
        local engine = {}
        function engine:startup_catalog_entry(id) return true,{characterId=id,cdoAvailable=true} end
        function engine:startup_surface_survey()
            equal(f.records[#f.records],"startup_surface_survey_intent")
            f.surveys=(f.surveys or 0)+1
            return true,{complete=not f.survey_blocked,spawnQualified=false,code="fixture-survey"}
        end
        function engine:startup_prepare(count)
            if f.not_ready then return true, nil end
            if f.prepare_fault then return false, "Native operation stopped [custom-assault-scope]" end
            if f.physical_block then return true, {blockedCode="floor-or-navigation-unavailable",physical={floor=0},
                candidates={{baseId="private-base-1",origin={X=0,Y=0,Z=0}}}} end
            local scopes = {}
            for index = 1, count do scopes[index] = { baseId = "private-base-" .. index, origin = { X=0,Y=0,Z=0 } } end
            return true, { scopes = scopes, availableBases = 10 }
        end
        function engine:prepare_spawn(_, member)
            f.prepares=(f.prepares or 0)+1
            if Shape.contract(f.runner.state.case) then
                if f.shape_pending then
                    return true,{ready=f.shape_pending_ready==true,pending=true,spawnQualified=false,experiment=Shape.contract(f.runner.state.case),
                        reason=f.shape_pending,attempts=2,selection={candidateLimit=17,candidatesVisited=2,rejections={
                            {candidate=1,reason="support-penetrating",support={startOverlap={classification="BLOCKED",blockers=1}}}}}}
                end
                return true,{ready=not f.shape_placement_blocked,pending=false,spawnQualified=false,experiment=Shape.contract(f.runner.state.case),
                    reason=f.shape_reason or "shape-fixture-blocked",surfaceSurvey={spawnQualified=false,templateOnly=true},
                    plannedGeometry={fixture=true}}
            end
            if f.placement_pending then return true,{ready=false,pending=true,reason="floor-unavailable"} end
            if f.in_base then return true,{ready=true,mode="in-base",position={X=500,Y=0,Z=0},goal={X=0,Y=0,Z=0}} end
            return true,{ready=member.index ~= f.unavailablePlacement,reason="floor-unavailable"}
        end
        function engine:spawn(_, member)
            equal(f.records[#f.records], "startup_spawn_intent")
            f.spawns = f.spawns + 1
            if f.spawn_fault then return false, "Native operation stopped [custom-assault-initialization]" end
            return true, { index = member.index }
        end
        function engine:startup_identity(member)
            if f.id_pending then return {} end
            return { instanceGuid = { A=member.index,B=0,C=0,D=0 }, playerGuid = { A=0,B=0,C=0,D=0 } }
        end
        function engine:startup_support()
            return {
                native=engine,
                prepare=function() return true,true end,
                begin=function() f.helpers=(f.helpers or 0)+1; return true,{actorAddress="private-address"} end,
                finish=function() return true,true end,
                poll=function() return true,{enabled=true,streamingComplete=true,ready=f.physical_ready==true} end,
                close=function() f.helper_closes=(f.helper_closes or 0)+1; return true,not f.helper_pending end,
            }
        end
        function engine:startup_shape_observation()
            equal(f.records[#f.records],"startup_shape_observation_intent")
            equal(f.runner.state.helpersCleaned,0)
            f.shape_observations=(f.shape_observations or 0)+1
            if f.capture_at_observation then f.phases[1]="capturing" end
            local result={comparison=f.shape_result or "MATCH",instanceOnly=true,spawnQualified=false,
                actual={root={radius=30,halfHeight=30},body={radius=30,halfHeight=95}}}
            if f.runner.state.case==Shape.ENGAGEMENT_CASE then
                local state=f.runner.state
                result.receipt={sample=f.shape_observations,runId=state.runId,case=state.case,experiment=state.experiment,
                    artifactSha256=state.artifactSha256,memberIndex=1,actorAddress="fixture-actor",observedAt=f.now}
            end
            return true,result
        end
        function engine:inspect(_, member)
            f.actors[member.index]=f.actors[member.index] or {}
            return true, { phase = f.phases[member.index] or "alive", healthBudget = 1000, targetId = "private-target-" .. member.index,
                actor=f.actors[member.index],
                actorAddress="fixture-actor",
                location = { X=f.arrived and 500 or 4000,Y=0,Z=0 } }
        end
        function engine:engage()
            if f.runner.state.case==Shape.ENGAGEMENT_CASE then
                equal(f.activePermit,true); equal(#f.runner.state.shapeObservations,2)
            end
            f.engages=(f.engages or 0)+1
            return true,f.engagementUnavailable and "unavailable" or true
        end
        function engine:startup_test_stage_changed(_,stage)
            if stage~="engagement" then f.activePermit=false end
        end
        function engine:startup_arm_qualified_engagement()
            equal(f.records[#f.records],"startup_qualified_engagement_arm_intent")
            equal(#f.runner.state.shapeObservations,2)
            for _,observation in ipairs(f.runner.state.shapeObservations) do equal(observation.comparison,"MATCH") end
            equal(f.runner.state.helpersCleaned,0)
            f.arms=(f.arms or 0)+1
            f.activePermit=not f.armBlocked
            local state=f.runner.state
            return true,{armed=f.activePermit,reason="engagement-ownership-unavailable",runId=state.runId,case=state.case,
                experiment=state.experiment,artifactSha256=state.artifactSha256,memberIndex=1,samples=2,
                baseId=state.members[1].baseId,actorAddress="fixture-actor"}
        end
        function engine:startup_qualified_damage_target(_,_,attacker,defender)
            return true,{active=f.activePermit==true,allowed=attacker==f.actors[1] and defender==f.legal_target}
        end
        function engine:startup_behavior() return "combat" end
        function engine:startup_combat_observation(_, _, movement_only)
            f.observations = (f.observations or 0) + 1
            f.movement_only = movement_only
            return true,{currentAction="fixture-combat",healthRatio=1}
        end
        function engine:sameActor(a,b) return a==b end
        function engine:startup_damage_target(_, actor) return true,actor==f.legal_target end
        function engine:startup_travel()
            equal(f.records[#f.records], "startup_movement_intent")
            f.travels = f.travels + 1
            return true
        end
        function engine:startup_arrival()
            return true,{arrived=not f.airborne,grounded=not f.airborne}
        end
        function engine:despawn(_, member)
            equal(f.records[#f.records], "startup_cleanup_intent")
            f.despawns = f.despawns + 1
            f.phases[member.index] = f.pending_cleanup and "despawning" or "missing"
            return true, f.pending_cleanup and "pending" or "despawned"
        end
        f.runner = Startup.new({ plan = { schemaVersion=1, runId="fixture-run", case=case or "spawn-cleanup",
            experiment=Shape.contract(case),
            sourceRevision=string.rep("1",40), artifactSha256=string.rep("2",64) }, store=store, engine=engine, clock=function() return f.now end,
            logger={ info=function() end, error=function() end } })
        function f:tick(count)
            for _ = 1, count or 1 do self.runner:tick(); self.now = self.now + 1 end
        end
        return f
    end

    test("startup test waits for a world without requiring a player or spawning early", function()
        local f = fixture()
        f.not_ready = true
        f:tick(10)
        equal(f.spawns, 0)
        equal(f.runner.state.stage, "world")
        f.now = 1120
        f:tick()
        equal(f.runner.state.status, "blocked")
        equal(f.runner.state.cleanupComplete, true)
    end)

    test("startup spawn smoke requires initialized actors and confirmed cleanup", function()
        local f = fixture()
        f:tick(8)
        equal(f.runner.state.status, "passed")
        equal(f.spawns, 1)
        equal(f.despawns, 1)
        equal(f.runner.state.initialized, 1)
        equal(f.runner.state.cleanupComplete, true)
        local calls = #f.records
        f:tick(5)
        equal(#f.records, calls)
    end)

    test("startup placement loss cleans prior owned actors and never despawns unrequested plans", function()
        local f=fixture("two-base-movement")
        f.unavailablePlacement=2
        f:tick(8)
        equal(f.runner.state.status,"blocked")
        equal(f.runner.state.code,"spawn-physical-unavailable")
        equal(f.spawns,1); equal(f.despawns,1)
        equal(f.runner.state.cleaned,1)
        equal(f.runner.state.members[2].skipped,true)
        equal(f.runner.state.members[2].spawnRequested,nil)
        equal(f.runner.state.cleanupComplete,true)
    end)

    test("startup placement loss waits for a prior pending identity before requesting owned cleanup", function()
        local f=fixture("two-base-movement")
        f.unavailablePlacement, f.id_pending, f.phases[1] = 2, true, "pending"
        f:tick(5)
        equal(f.spawns,1); equal(f.despawns,0)
        equal(f.runner.state.members[1].cleanupRequested,nil)
        equal(f.runner.state.members[1].instanceGuid,nil)
        f.id_pending, f.phases[1] = false,"alive"
        f:tick()
        equal(f.despawns,1)
        equal(f.runner.state.members[1].instanceGuid.A,1)
        equal(f.runner.state.status,"blocked")
        equal(f.runner.state.cleanupComplete,true)
    end)

    test("startup waits for a bounded surface search without submitting duplicate spawn intent", function()
        local f=fixture()
        f.placement_pending=true
        f:tick(5)
        equal(f.spawns,0)
        f.placement_pending=false
        f:tick(6)
        equal(f.spawns,1)
        equal(f.runner.state.status,"passed")
    end)

    test("in-base engagement does not fabricate travel proof or require an impossible outside approach", function()
        local f=fixture("engagement")
        f.in_base=true
        f:tick(6)
        equal(f.runner.state.stage,"engagement")
        equal(f.runner.state.moved,0)
        equal(f.travels,0)
        equal(f.runner.state.status,"running")
        f.legal_target={}
        f.runner:on_damage(f.actors[1],f.legal_target,1)
        f:tick(3)
        equal(f.runner.state.status,"passed")
        equal(f.runner.state.dealtDamageEvents,1)
    end)

    test("startup movement does not pass merely because an action returned", function()
        local f = fixture("movement")
        f:tick(6)
        equal(f.travels, 1)
        equal(f.runner.state.status, "running")
        equal(f.runner.state.moved, 0)
        f.arrived = true
        f:tick(3)
        equal(f.runner.state.status, "passed")
        equal(f.runner.state.moved, 1)
    end)

    test("startup movement rejects planar proximity while airborne or on the wrong level", function()
        local f=fixture("movement")
        f:tick(6)
        f.arrived,f.airborne=true,true
        f:tick(3)
        equal(f.runner.state.moved,0)
        equal(f.runner.state.status,"running")
        equal(f.runner.state.members[1].arrivalObservation.grounded,false)
        f.airborne=false
        f:tick(3)
        equal(f.runner.state.status,"passed")
        equal(f.runner.state.moved,1)
    end)

    test("startup multi-base qualification observes both actors before cleanup", function()
        local f = fixture("two-base-movement")
        f:tick(7)
        equal(f.spawns, 2)
        equal(f.runner.state.initialized, 2)
        equal(f.runner.state.simultaneous, true)
        equal(f.travels, 2)
        f.arrived = true
        f:tick(4)
        equal(f.runner.state.status, "passed")
        equal(f.despawns, 2)
    end)

    test("startup cleanup polls pending work without issuing another despawn", function()
        local f = fixture()
        f.pending_cleanup = true
        f:tick(9)
        equal(f.despawns, 1)
        equal(f.runner.state.cleanupComplete, false)
        f.phases[1] = "missing"
        f:tick()
        equal(f.runner.state.status, "passed")
        equal(f.despawns, 1)
    end)

    test("startup cleanup dispatches both requests before awaiting either actor", function()
        local f = fixture("two-base-movement")
        f.pending_cleanup=true
        f:tick(7)
        f.arrived=true
        f:tick(3)
        equal(f.despawns,2)
        local members=f.runner.state.members
        equal(members[1].cleanupRequestedAt,members[2].cleanupRequestedAt)
        f.phases[1]="missing"
        f.now=members[2].cleanupRequestedAt+40
        f:tick()
        equal(f.runner.state.cleaned,1)
        equal(f.runner.state.status,"running")
        f.phases[2]="missing"
        f:tick()
        equal(f.runner.state.status,"passed")
        equal(f.despawns,2)
    end)

    test("startup faults preserve uncertain spawn intent and never retry", function()
        local f = fixture()
        f.spawn_fault = true
        f:tick(8)
        equal(f.runner.state.status, "failed")
        equal(f.runner.state.cleanupComplete, false)
        equal(f.spawns, 1)
        equal(f.despawns, 0)
        equal(f.runner.state.code, "custom-assault-initialization")
    end)

    test("shape helper finalization is pinned to the no-NPC fault and preserves its failed artifact",function()
        local state={schemaVersion=1,runId="20260909-074037-19fcb48d81ce4063b5c8fe64017c1b9c",
            sourceRevision="10fb2eb52a351eed9b8ec5432d30a47991149e4d",
            artifactSha256="6c90bc5493830d7178cdb444426fde15feab416afdd21aba856a3fc538b95c0a",
            case=Shape.CASE,experiment=Shape.CONTRACT,status="failed",stage="spawn",code="unclassified-lua-error",
            spawned=0,initialized=0,cleaned=0,moved=0,helpersCreated=1,helpersCleaned=0,
            mutationStarted=true,cleanupComplete=false,members={{phase="planned"}}}
        local written
        local store={records={{kind="startup_test_failed",state=state}},
            append=function(_,kind,_,value) equal(kind,"startup_shape_support_runtime_finalized"); written=value; return true end,
            save_snapshot=function() return true end}
        local proof={processExitVerified=true,runId=state.runId,
            certificateSha256="47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f",
            serverExecutableSha256="61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02",
            serverPakSha256="2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe"}
        truthy(Startup.finalize_shape_support_fault(store,proof))
        equal(written.helpersCleaned,0); equal(written.helpersFinalized,1); equal(written.spawned,0)
        equal(written.cleanupComplete,true); equal(written.failedArtifactSha256,state.artifactSha256)
        equal(state.status,"failed"); equal(state.cleanupComplete,false)
        proof.processExitVerified=false
        equal(pcall(Startup.finalize_shape_support_fault,store,proof),false)
        proof.processExitVerified=true
        store.records[1].kind="startup_spawn_intent"
        equal(pcall(Startup.finalize_shape_support_fault,store,proof),false)
        store.records[1].kind="startup_test_failed"; state.members[1].spawnRequested=true
        equal(pcall(Startup.finalize_shape_support_fault,store,proof),false)
    end)

    test("startup durability failure prevents the corresponding native call", function()
        local f = fixture()
        f.fail_record = "startup_spawn_intent"
        f:tick(5)
        equal(f.spawns, 0)
        equal(f.runner.state.status, "failed")
    end)

    test("startup class failure is terminal without claiming an entity was spawned", function()
        local f = fixture()
        f.prepare_fault = true
        f:tick(5)
        equal(f.runner.state.status, "failed")
        equal(f.runner.state.cleanupComplete, true)
        equal(f.spawns, 0)
    end)

    test("startup class catalog qualifies all entries without requesting a world or NPC", function()
        local f = fixture("class-catalog")
        f.not_ready = true
        f:tick(35)
        equal(f.runner.state.status,"passed")
        equal(#f.runner.state.catalog,34)
        equal(f.spawns,0)
        equal(f.runner.state.mutationStarted,false)
    end)

    test("surface survey executes once with owned support but never requests an NPC", function()
        local f=fixture("surface-survey")
        f.physical_block,f.physical_ready=true,true
        f:tick(15)
        equal(f.runner.state.status,"passed"); equal(f.spawns,0); equal(f.despawns,0)
        equal(f.surveys,1); equal(f.runner.state.helpersCleaned,1)
        equal(f.runner.state.surfaceSurvey.spawnQualified,false)
        f:tick(5); equal(f.surveys,1)
    end)

    test("qualified engagement waits for two samples and an arm before dispatch without fabricated movement",function()
        local f=fixture(Shape.ENGAGEMENT_CASE)
        f.physical_ready=true
        for _=1,20 do
            f:tick()
            if f.shape_observations==1 then break end
        end
        equal(f.shape_observations,1); equal(f.engages,nil); equal(f.arms,nil); equal(f.runner.state.helpersCleaned,0)
        f:tick()
        equal(f.shape_observations,2); equal(f.runner.state.stage,"engagement"); equal(f.engages,nil)
        f.runner:on_damage(f.actors[1],{},100)
        equal(#f.runner.damageQueue,0)
        f:tick()
        equal(f.arms,1); equal(f.engages,nil)
        f:tick(3)
        truthy(f.engages>0); truthy(f.observations>0)
        equal(f.spawns,1); equal(f.runner.state.moved,0); equal(f.travels,0)
        equal(f.runner.state.status,"running")
    end)

    test("qualified engagement passes only on positive outgoing scoped character damage and complete cleanup",function()
        local f=fixture(Shape.ENGAGEMENT_CASE)
        f.physical_ready=true
        f:tick(20)
        equal(f.runner.state.stage,"engagement")
        f.runner:on_damage({},f.actors[1],10)
        f.runner:on_damage(f.actors[1],{},100)
        f:tick()
        equal(f.runner.state.receivedDamageEvents,1); equal(f.runner.state.dealtDamageEvents,nil)
        equal(f.runner.state.status,"running")
        f.legal_target={}
        f.runner:on_damage(f.actors[1],f.legal_target,25)
        f:tick(5)
        equal(f.runner.state.status,"passed"); equal(f.runner.state.code,"qualified-engagement-damage-observed")
        equal(f.runner.state.dealtDamageEvents,1); equal(f.runner.state.dealtDamage,25)
        equal(f.runner.state.cleaned,1); equal(f.runner.state.helpersCleaned,1)
        equal(f.runner.state.moved,0); equal(f.activePermit,false)
        truthy(Startup.validate_state(f.runner.state,"fixture-run"))
    end)

    test("qualified engagement without outgoing damage times out with exact NPC and helper cleanup",function()
        local f=fixture(Shape.ENGAGEMENT_CASE)
        f.physical_ready=true
        f:tick(20)
        local engages=f.engages
        f.now=f.runner.state.stageStartedAt+60
        f:tick(5)
        equal(f.runner.state.status,"blocked"); equal(f.runner.state.code,"engagement-timeout")
        equal(f.engages,engages); equal(f.despawns,1); equal(f.runner.state.helpersCleaned,1)
        equal(f.runner.state.cleanupComplete,true); equal(f.activePermit,false)
    end)

    test("bad shape samples block qualified engagement before any gameplay arm",function()
        for _,comparison in ipairs({"MISMATCH","UNSUPPORTED"}) do
            local f=fixture(Shape.ENGAGEMENT_CASE)
            f.physical_ready,f.shape_result=true,comparison
            f:tick(25)
            equal(f.runner.state.status,"blocked"); equal(f.arms,nil); equal(f.engages,nil)
            equal(f.spawns,1); equal(f.despawns,1); equal(f.runner.state.helpersCleaned,1)
        end
    end)

    test("qualified engagement evidence rejects old contracts one sample and damage-free passes",function()
        local f=fixture(Shape.ENGAGEMENT_CASE)
        f.physical_ready=true
        f:tick(20)
        f.legal_target={}
        f.runner:on_damage(f.actors[1],f.legal_target,1)
        f:tick(5)
        truthy(Startup.validate_state(f.runner.state,"fixture-run"))
        for _,change in ipairs({
            function(state) state.experiment=Shape.CONTRACT end,
            function(state) state.shapeObservations[2]=nil end,
            function(state) state.shapeObservations[2].receipt.runId="previous-run" end,
            function(state) state.dealtDamageEvents=0 end,
            function(state) state.dealtDamage=0 end,
        }) do
            local state=util.deep_copy(f.runner.state)
            change(state)
            equal(pcall(Startup.validate_state,state,"fixture-run"),false)
        end
    end)

    test("shape qualification always retains a helper for one NPC and two read-only samples",function()
        local f=fixture(Shape.CASE)
        f.physical_ready=true
        f:tick(25)
        equal(f.spawns,1); equal(f.shape_observations,2); equal(f.despawns,1)
        equal(f.travels,0); equal(f.engages,nil)
        equal(f.runner.state.status,"passed"); equal(f.runner.state.code,"shape-instance-only")
        equal(f.runner.state.helpersCreated,1); equal(f.runner.state.helpersCleaned,1)
        equal(f.runner.state.surfaceSurvey.spawnQualified,false)
        truthy(Startup.validate_state(f.runner.state,"fixture-run"))
        f.runner:on_damage(f.actors[1],{},100)
        f:tick(10)
        equal(f.spawns,1); equal(f.shape_observations,2); equal(f.runner.state.dealtDamageEvents,nil)
    end)

    test("shape mismatch cleans only its owned NPC and holds support until pending cleanup completes",function()
        local f=fixture(Shape.CASE)
        f.physical_ready,f.pending_cleanup,f.shape_result=true,true,"MISMATCH"
        f:tick(25)
        equal(f.spawns,1); equal(f.shape_observations,1); equal(f.despawns,1)
        equal(f.runner.state.stage,"cleanup"); equal(f.runner.state.helpersCleaned,0)
        f.phases[1]="missing"
        f:tick(3)
        equal(f.runner.state.status,"blocked"); equal(f.runner.state.code,"shape-mismatch")
        equal(f.runner.state.cleanupComplete,true); equal(f.helper_closes,1)
        equal(f.travels,0); equal(f.engages,nil)
    end)

    test("unsupported actual shape and failed scene evidence never promote normal readiness",function()
        local f=fixture(Shape.CASE)
        f.physical_ready,f.shape_result=true,"UNSUPPORTED"
        f:tick(25)
        equal(f.runner.state.status,"blocked"); equal(f.runner.state.code,"shape-unsupported")
        equal(f.despawns,1); equal(f.shape_observations,1)
        f=fixture(Shape.CASE)
        f.physical_ready,f.shape_placement_blocked=true,true
        f:tick(25)
        equal(f.spawns,0); equal(f.shape_observations,nil); equal(f.runner.state.helpersCleaned,1)
        equal(f.runner.state.code,"shape-fixture-blocked")
    end)

    test("shape harness journals pending site rejections and cleans its helper on exhaustion",function()
        local f=fixture(Shape.CASE)
        f.physical_ready,f.shape_pending=true,"shape-site-search-pending"
        f:tick(12)
        equal(f.spawns,0); equal(f.runner.state.stage,"spawn"); equal(f.runner.state.helpersCleaned,0)
        local selection=f.runner.state.members[1].siteSelection
        equal(selection.candidatesVisited,2); equal(selection.rejections[1].support.startOverlap.classification,"BLOCKED")
        f.shape_pending,f.shape_placement_blocked,f.shape_reason=nil,true,"shape-sites-exhausted"
        f:tick(5)
        equal(f.runner.state.status,"blocked"); equal(f.runner.state.code,"shape-sites-exhausted")
        equal(f.spawns,0); equal(f.runner.state.helpersCleaned,1); equal(f.runner.state.cleanupComplete,true)
    end)

    test("shape harness cannot start late geometry or spawn work after the preparation deadline",function()
        local f=fixture(Shape.CASE)
        f.physical_ready,f.shape_pending=true,"shape-residency-pending"
        f:tick(12)
        local prepares=f.prepares
        f.now=f.runner.state.members[1].placementStartedAt+120
        f.shape_pending=nil
        f:tick(5)
        equal(f.prepares,prepares); equal(f.spawns,0)
        equal(f.runner.state.status,"blocked"); equal(f.runner.state.code,"spawn-placement-timeout")
        equal(f.runner.state.helpersCleaned,1); equal(f.runner.state.cleanupComplete,true)
    end)

    test("shape harness rejects anonymous pending states and a ready-pending proof",function()
        for _,reason in ipairs({"shape-site-search-pending","unqualified-pending"}) do
            local f=fixture(Shape.CASE)
            f.physical_ready,f.shape_pending=true,reason
            f.shape_pending_ready=reason=="shape-site-search-pending"
            f:tick(12)
            equal(f.runner.state.status,"failed"); equal(f.spawns,0)
        end
    end)

    test("shape startup waits for an assigned identity without duplicate NPC requests",function()
        local f=fixture(Shape.CASE)
        f.physical_ready,f.id_pending,f.phases[1]=true,true,"pending"
        f:tick(25)
        equal(f.spawns,1); equal(f.despawns,0); equal(f.shape_observations,nil)
        equal(f.runner.state.helpersCleaned,0); equal(f.runner.state.members[1].instanceGuid,nil)
        f.id_pending,f.phases[1]=false,"alive"
        f:tick(15)
        equal(f.runner.state.status,"passed"); equal(f.spawns,1)
        equal(f.runner.state.members[1].instanceGuid.A,1)
    end)

    test("shape timeout keeps the original pending handle and waits for identity before cleanup",function()
        local f=fixture(Shape.CASE)
        f.physical_ready,f.id_pending,f.phases[1]=true,true,"pending"
        f:tick(85)
        equal(f.runner.state.stage,"cleanup"); equal(f.spawns,1); equal(f.despawns,0)
        equal(f.runner.state.helpersCleaned,0)
        f.id_pending,f.phases[1]=false,"alive"
        f:tick(5)
        equal(f.runner.state.status,"blocked"); equal(f.runner.state.code,"initialize-timeout")
        equal(f.despawns,1); equal(f.shape_observations,nil); equal(f.runner.state.cleanupComplete,true)
    end)

    test("shape cleanup pauses during capture processing without another spawn or despawn",function()
        local f=fixture(Shape.CASE)
        f.physical_ready,f.capture_at_observation,f.shape_result=true,true,"MISMATCH"
        f:tick(25)
        equal(f.runner.state.stage,"cleanup"); equal(f.despawns,0); equal(f.runner.state.helpersCleaned,0)
        f.phases[1]="alive"
        f:tick(5)
        equal(f.despawns,1); equal(f.runner.state.status,"blocked")
        equal(f.spawns,1); equal(f.shape_observations,1)
    end)

    test("failed shape observation intent prevents native observation and automatic cleanup",function()
        local f=fixture(Shape.CASE)
        f.physical_ready,f.fail_record=true,"startup_shape_observation_intent"
        f:tick(25)
        equal(f.runner.state.status,"failed"); equal(f.runner.state.cleanupComplete,false)
        equal(f.spawns,1); equal(f.shape_observations,nil); equal(f.despawns,0)
        equal(f.helper_closes,nil)
    end)

    test("shape outcomes cannot claim a pass from one sample a mismatch or a gameplay certificate",function()
        local f=fixture(Shape.CASE)
        f.physical_ready=true
        f:tick(25)
        for _,change in ipairs({
            function(state) state.shapeObservations[2]=nil end,
            function(state) state.shapeObservations[2].comparison="MISMATCH" end,
            function(state) state.shapeObservations[2].spawnQualified=true end,
            function(state) state.moved=1 end,
            function(state) state.experiment=nil end,
        }) do
            local state=util.deep_copy(f.runner.state)
            change(state)
            equal(pcall(Startup.validate_state,state,"fixture-run"),false)
        end
    end)

    test("startup physical placement failure blocks before any NPC request", function()
        local f = fixture("movement")
        f.physical_block = true
        f:tick(140)
        equal(f.runner.state.status,"blocked")
        equal(f.runner.state.code,"physical-prewarm-timeout")
        equal(f.runner.state.helpersCreated,1)
        equal(f.runner.state.helpersCleaned,1)
        equal(f.spawns,0)
    end)

    test("startup prewarm does not mistake streaming completion for physical readiness", function()
        local f = fixture("prewarm")
        f.physical_block=true
        f:tick(140)
        equal(f.runner.state.status,"blocked")
        equal(f.runner.state.code,"physical-prewarm-timeout")
        equal(f.helpers,1)
        equal(f.helper_closes,1)
        equal(f.spawns,0)
        equal(f.runner.state.cleanupComplete,true)
    end)

    test("startup prewarm finishes only after support cleanup is observed", function()
        local f = fixture("prewarm")
        f.physical_block, f.physical_ready, f.helper_pending = true,true,true
        f:tick(12)
        equal(f.runner.state.helpersCreated,1)
        equal(f.runner.state.helpersCleaned,0)
        equal(f.runner.state.cleanupComplete,false)
        f.helper_pending=false
        f:tick()
        equal(f.runner.state.status,"passed")
        equal(f.runner.state.physicalPrewarmPassed,true)
        equal(f.runner.state.helpersCleaned,1)
        equal(f.spawns,0)
    end)

    test("startup movement retains prewarm support through NPC cleanup", function()
        local f = fixture("movement")
        f.physical_block, f.physical_ready = true,true
        f:tick(11)
        equal(f.spawns,1)
        equal(f.runner.state.helpersCleaned,0)
        f.arrived=true
        f:tick(8)
        equal(f.runner.state.status,"passed")
        equal(f.runner.state.cleaned,1)
        equal(f.runner.state.helpersCleaned,1)
    end)

    test("startup engagement samples between dispatches and captures escape without more combat", function()
        local f = fixture("engagement")
        f:tick(6)
        f.arrived = true
        f:tick(3)
        local before, engages = f.observations, f.engages
        f:tick(2)
        equal(f.observations, before + 2)
        equal(f.engages, engages)
        f.phases[1] = "escaped"
        f:tick()
        equal(f.movement_only, true)
        equal(f.engages, engages)
        equal(f.runner.state.stage, "cleanup")
    end)

    test("startup engagement requires a real positive damage callback to a scoped defender", function()
        local f = fixture("engagement")
        f:tick(6)
        f.arrived=true
        f:tick(3)
        equal(f.runner.state.stage,"engagement")
        truthy(f.engages>0)
        equal(f.runner.state.dealtDamageEvents,nil)
        f.runner:on_damage({},f.actors[1],10)
        f:tick()
        equal(f.runner.state.stage,"engagement")
        equal(f.runner.state.receivedDamageEvents,1)
        f.runner:on_damage(f.actors[1],{},100)
        f:tick()
        equal(f.runner.state.dealtDamageEvents,nil)
        f.legal_target={}
        f.runner:on_damage(f.actors[1],f.legal_target,100)
        f:tick(3)
        equal(f.runner.state.dealtDamageEvents,1)
        equal(f.runner.state.dealtDamage,100)
        equal(f.runner.state.status,"passed")
        equal(f.despawns,1)
    end)

    test("streaming support validates bounded shape writes and destroys only its owned helper once", function()
        local Support = require("ped.startup_support")
        local world, scope = {}, {origin={X=10,Y=20,Z=30},positions={{X=100,Y=200,Z=30}}}
        scope.world=world
        local destroyed, unregistered, cleared = 0,0,0
        local actor = {
            IsValid=function() return true end, IsA=function(_,name) return name=="/Script/Engine.TargetPoint" end,
            GetFName=function() return {ToString=function() return "OwnedHelper" end} end,
            GetWorld=function() return world end, K2_GetActorLocation=function() return scope.origin end,
            K2_DestroyActor=function() destroyed=destroyed+1 end, IsActorBeingDestroyed=function() return destroyed>0 end,
        }
        local source = {IsValid=function() return true end,GetOwner=function() return actor end}
        source._shapes = {Empty=function() cleared=cleared+1 end}
        setmetatable(source,{
            __index=function(self,key) if key=="Shapes" then return self._shapes end end,
            __newindex=function(self,key,value)
                if key=="Shapes" then
                    equal(cleared,1); equal(#value,1)
                    rawset(self,"_shapes",{
                        GetArrayNum=function() return 1 end,
                        [1]={Location={X=0,Y=0,Z=0},Rotation={Pitch=0,Yaw=0,Roll=0}},
                    })
                else rawset(self,key,value) end
            end,
        })
        function source:DisableStreamingSource() self.enabled=false end
        function source:EnableStreamingSource() self.enabled=true end
        function source:IsStreamingSourceEnabled() return self.enabled end
        function source:IsStreamingCompleted() return self.complete==true end
        actor.AddComponentByClass=function(_,_,manual,_,deferred) equal(manual,false); equal(deferred,true); return source end
        actor.FinishAddComponent=function() equal(source.Shapes[1].Radius,12000); equal(source.Shapes[1].bUseGridLoadingRange,false) end
        local nav = {RegisterNavigationInvoker=function(_,which,generation,removal)
            equal(which,actor); equal(generation,10000); equal(removal,12000) end,
            UnregisterNavigationInvoker=function(_,which) equal(which,actor); unregistered=unregistered+1 end}
        local bridge={_native_step=function(_,_,fn) return pcall(fn) end}
        local native={bridge=bridge,a={
            valid=function(v) return type(v)=="table" and type(v.IsValid)=="function" and v:IsValid() end,
            same=function(a,b) return a==b end,fname=function() return function(v) return v end end,
        }}
        function native:_call(_,owner,name,...) return owner[name](owner,...) end
        function native:actor_world(which) equal(which,actor); return world end
        local support = Support.new(native,{scope})
        support.navigation=nav
        support.sourceClass={}
        support.bindings={library={FinishSpawningActor=function(_,which) return which end}}
        support.records[1]={actor=actor,world=world,name="OwnedHelper",transform={}}
        truthy(support:finish(1))
        equal(source.Shapes[1].bIsSector,false)
        local queries=0
        native.startup_floor=function(_,actual)
            equal(actual,world)
            queries=queries+1
            return nil
        end
        native.startup_nav=function() return nil end
        local observed, result = support:poll(1)
        truthy(observed,result); equal(result.ready,false); equal(result.physicalQueried,false)
        equal(queries,0)
        source.complete=true
        observed,result=support:residency(1)
        truthy(observed,result); equal(result.streamingComplete,true)
        equal(result.ready,false); equal(result.physicalQueried,false); equal(queries,0)
        equal(result.placementQualified,false)
        observed,result=support:poll(1)
        truthy(observed,result); equal(result.ready,false); equal(result.physicalQueried,true)
        equal(queries,2)
        equal(result.placementQualified,false)
        truthy(support:close(1))
        truthy(support:close(1))
        equal(destroyed,1)
        equal(unregistered,1)
        equal(source.enabled,false)
    end)

    test("startup quarantine uses the checksummed journal rather than an altered snapshot", function()
        local Store, json, path = require("ped.store"), require("ped.json"), require("ped.path")
        local files = {}
        local fs = {
            ensure_directory=function() return true end,
            exists=function(name) return files[name] ~= nil end,
            read=function(name) return files[name] end,
            write=function(name, text) files[name]=text; return true end,
            append=function(name, text) files[name]=(files[name] or "")..text; return true end,
            remove=function(name) files[name]=nil; return true end,
            rename=function(a,b) files[b]=files[a]; files[a]=nil; return true end,
        }
        local root = "private-test-data"
        local directory = path.join(root, "startup-tests", "fixture-run")
        local logger = {info=function() end,warn=function() end,error=function() end}
        local store = Store.new(directory, logger, fs)
        local state = { schemaVersion=1,runId="fixture-run",case="spawn-cleanup",artifactSha256=string.rep("2",64),
            status="running",mutationStarted=true,cleanupComplete=false,spawned=1,initialized=0,cleaned=0,moved=0 }
        truthy(store:append("startup_spawn_intent", {}, state))
        truthy(store:save_snapshot(state))
        local altered = json.decode(files[store.snapshot_path])
        altered.payload.cleanupComplete, altered.payload.mutationStarted = true, false
        files[store.snapshot_path] = json.encode(altered)
        files[path.join(root,"startup-tests","active.json")] = json.encode({runId="fixture-run"})
        local bridge = {logger=logger}
        Startup.attach(bridge, root, {filesystem=fs,getenv=function() return nil end})
        truthy(bridge.startup_quarantine)
        equal(Startup.read_state(directory,"fixture-run",logger,fs).cleanupComplete,false)
    end)

    test("legacy finalization requires audited parameters and verified full-process exit", function()
        local original = { schemaVersion=1,runId="legacy-run",case="spawn-cleanup",
            sourceRevision="f671c2200ba6a83ba879e19c2b7acbf92d2fcbc8",
            artifactSha256="de3f829239dda321796229d5b40274b9587a8fe7c17e764ab898b10a639d6643",
            status="failed",stage="spawn",code="custom-assault-identity",mutationStarted=true,cleanupComplete=false,
            spawned=0,initialized=0,moved=0,cleaned=0,members={{characterId="BOSS_Hunter_Rifle",level=30,spawnRequested=true}} }
        local written
        local store = {records={{state=original}},append=function(_,kind,_,state)
            equal(kind,"startup_legacy_runtime_finalized"); written=state; return true end,
            save_snapshot=function() return true end}
        local proof = {runId="legacy-run",processExitVerified=false,
            certificateSha256="47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f",
            serverExecutableSha256="61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02",
            serverPakSha256="2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe"}
        equal(pcall(Startup.finalize_legacy_spawn,store,proof),false)
        equal(written,nil)
        proof.processExitVerified=true
        truthy(Startup.finalize_legacy_spawn(store,proof))
        equal(written.status,"blocked")
        equal(written.cleanupComplete,true)
        equal(written.failedArtifactSha256,original.artifactSha256)
        equal(original.cleanupComplete,false)
        equal(written.spawned,0)
        original.members[1].characterId="unrelated-character"
        equal(pcall(Startup.finalize_legacy_spawn,store,proof),false)
    end)

    test("support-only crash finalization preserves failure and rejects any NPC intent", function()
        local state = {schemaVersion=1,runId="support-crash",case="two-base-movement",status="running",stage="support-wait",
            sourceRevision="122eea9932ff9bd8286277a2525d9d78828de601",
            artifactSha256="c60075ba179ef7d5d01f493b8cf9b13fa191ceb4aad967a0f8e3865d8c57f30f",
            mutationStarted=true,cleanupComplete=false,spawned=0,initialized=0,moved=0,cleaned=0,members={},
            helpersCreated=2,helpersCleaned=0}
        local proof = {runId="support-crash",processExitVerified=true,
            dumpSha256="d9e0840ab4d5d1f3e375daba5f47bb85eea46b49b28377b5ceeb184bd872985a",
            serverExecutableSha256="61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02",
            serverPakSha256="2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe"}
        local written
        local store = {records={{kind="startup_support_observation",state=state}},
            append=function(_,kind,_,value) equal(kind,"startup_support_runtime_finalized"); written=value; return true end,
            save_snapshot=function() return true end}
        truthy(Startup.finalize_support_only(store,proof))
        equal(written.helpersCleaned,0); equal(written.helpersFinalized,2)
        equal(written.status,"blocked"); equal(written.cleanupComplete,true)
        equal(state.cleanupComplete,false)
        store.records[1].kind="startup_spawn_intent"
        equal(pcall(Startup.finalize_support_only,store,proof),false)
    end)

    test("pending cleanup finalization distinguishes observed cleanup from world teardown", function()
        local state={schemaVersion=1,runId="pending-run",case="two-base-movement",status="failed",stage="cleanup",
            code="custom-assault-despawn",sourceRevision="e4c8cc8dcc7ff3bbd8c5eff93168d5b756170cf3",
            artifactSha256="0f24085e4719a967e45ffcf665c0a8b55ca982c66673537e80ff85454a37640f",
            mutationStarted=true,cleanupComplete=false,spawned=2,initialized=2,moved=2,cleaned=1,
            helpersCreated=2,helpersCleaned=0,members={}}
        for i=1,2 do state.members[i]={characterId="BOSS_Hunter_Rifle",level=30,cleanupRequested=true,
            instanceGuid={A=i,B=0,C=0,D=0},playerGuid={A=0,B=0,C=0,D=0}} end
        local proof={runId="pending-run",processExitVerified=true,
            certificateSha256="47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f",
            serverExecutableSha256="61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02",
            serverPakSha256="2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe"}
        local written
        local store={records={{state=state}},append=function(_,_,_,value) written=value; return true end,
            save_snapshot=function() return true end}
        truthy(Startup.finalize_pending_cleanup(store,proof))
        equal(written.cleaned,1); equal(written.npcsFinalized,1); equal(written.helpersFinalized,2)
        equal(written.status,"blocked"); truthy(Startup.validate_state(written,"pending-run"))
        proof.processExitVerified=false
        equal(pcall(Startup.finalize_pending_cleanup,store,proof),false)
    end)
end
