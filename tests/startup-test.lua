return function(test, equal, truthy)
    local Startup = require("ped.startup_test")
    local util = require("ped.util")
    local function fixture(case)
        local f = { now = 1000, records = {}, spawns = 0, despawns = 0, travels = 0, phases = {} }
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
        function engine:startup_prepare(count)
            if f.not_ready then return true, nil end
            if f.prepare_fault then return false, "Native operation stopped [custom-assault-scope]" end
            if f.physical_block then return true, {blockedCode="floor-or-navigation-unavailable",physical={floor=0},
                candidates={{baseId="private-base-1",origin={X=0,Y=0,Z=0}}}} end
            local scopes = {}
            for index = 1, count do scopes[index] = { baseId = "private-base-" .. index, origin = { X=0,Y=0,Z=0 } } end
            return true, { scopes = scopes, availableBases = 10 }
        end
        function engine:spawn(_, member)
            equal(f.records[#f.records], "startup_spawn_intent")
            f.spawns = f.spawns + 1
            if f.spawn_fault then return false, "Native operation stopped [custom-assault-initialization]" end
            return true, { index = member.index }
        end
        function engine:startup_identity(member)
            return { instanceGuid = { A=member.index,B=0,C=0,D=0 }, playerGuid = { A=0,B=0,C=0,D=0 } }
        end
        function engine:startup_support()
            return {
                prepare=function() return true,true end,
                begin=function() f.helpers=(f.helpers or 0)+1; return true,{actorAddress="private-address"} end,
                finish=function() return true,true end,
                poll=function() return true,{enabled=true,streamingComplete=true,ready=f.physical_ready==true} end,
                close=function() f.helper_closes=(f.helper_closes or 0)+1; return true,not f.helper_pending end,
            }
        end
        function engine:inspect(_, member)
            return true, { phase = f.phases[member.index] or "alive", healthBudget = 1000, targetId = "private-target-" .. member.index,
                location = { X=f.arrived and 500 or 4000,Y=0,Z=0 } }
        end
        function engine:startup_travel()
            equal(f.records[#f.records], "startup_movement_intent")
            f.travels = f.travels + 1
            return true
        end
        function engine:despawn(_, member)
            equal(f.records[#f.records], "startup_cleanup_intent")
            f.despawns = f.despawns + 1
            f.phases[member.index] = f.pending_cleanup and "despawning" or "missing"
            return true, f.pending_cleanup and "pending" or "despawned"
        end
        f.runner = Startup.new({ plan = { schemaVersion=1, runId="fixture-run", case=case or "spawn-cleanup",
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
        local support = Support.new(native,{scope})
        support.navigation=nav
        support.sourceClass={}
        support.bindings={library={FinishSpawningActor=function(_,which) return which end}}
        support.records[1]={actor=actor,world=world,name="OwnedHelper",transform={}}
        truthy(support:finish(1))
        equal(source.Shapes[1].bIsSector,false)
        local queries=0
        native.startup_floor=function() queries=queries+1; return nil end
        native.startup_nav=function() return nil end
        native.startup_trace=function() return false end
        local observed, result = support:poll(1)
        truthy(observed,result); equal(result.ready,false); equal(result.physicalQueried,false)
        equal(queries,0)
        source.complete=true
        observed,result=support:poll(1)
        truthy(observed,result); equal(result.ready,false); equal(result.physicalQueried,true)
        equal(queries,1)
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
end
