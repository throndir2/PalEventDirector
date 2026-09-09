local json = require("ped.json")
local path = require("ped.path")
local util = require("ped.util")
local filesystem = require("ped.filesystem")
local Store = require("ped.store")
local Diagnostic = require("ped.preflight_diagnostic")
local bounties = require("ped.bounties")
local Shape = require("ped.shape_qualification")
local Cadence = require("ped.cadence_trial")

local Test = {}
Test.__index = Test

local CASES = { ["spawn-cleanup"] = 1, movement = 1, ["two-base-movement"] = 2, prewarm = 1, engagement = 1,
    ["class-catalog"] = 1, ["surface-survey"] = 1, [Shape.CASE] = 1, [Shape.ENGAGEMENT_CASE] = 1, [Cadence.CASE] = 1 }
local TERMINAL = { passed = true, failed = true, blocked = true }
local WORLD_FINALIZED = {
    runId="20260909-221539-b5664f1858dd4afcab2f296570f197e1",
    sourceRevision="29bea671d8cafc3588fa1c12bcf7c0ecbee0db48",
    artifactSha256="d3b4a9b6628189cbfa0545e6ca4ce593fedfa19265e708e645695aa2e79cf274",
    certificateSha256="45a3328ee826697958f997f26356953ad469eabfb2eb34e1fbe25222427455ae",
    journalSha256="0d92fee98b9bfd3adbebccf143a2cd44bc05cb87ec97e6eb7dcbad5a2736aa1b",
    snapshotSha256="a5610801008d136212a48aa75e4781f8e56122eb0bc0b65988339326fac7768c",
    evidenceManifestSha256="82a0f705074dde66b8c73e32d54c03afef1a774f0f720831add56f39ad1defb3",
    breadcrumbsSha256="5192e3d3378d6fc205edb15b510e2c1774d644e7866608deb6f2b4e021c7aad1",
    missingAfterStep="1788992144-2197-start-projectile-creation-observation",
}

local function world_finalization_proof(state,evidence)
    if type(evidence)~="table" or state.case~=Cadence.CASE then return false end
    for _,key in ipairs({"runId","sourceRevision","artifactSha256"}) do
        if state[key]~=WORLD_FINALIZED[key] then return false end
    end
    for _,key in ipairs({"runId","certificateSha256","journalSha256","snapshotSha256",
        "evidenceManifestSha256","breadcrumbsSha256","missingAfterStep"}) do
        if evidence[key]~=WORLD_FINALIZED[key] then return false end
    end
    return evidence.processExitVerified==true and evidence.installationProcessTreeEmpty==true
        and evidence.oldRootPid==14328 and evidence.instanceOnlyLeaseVerified==true and evidence.noReplay==true
        and evidence.preserveSavedTransfers==true and evidence.noExternalReapply==true and evidence.nativeCalls==0
        and evidence.serverExecutableSha256=="61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256=="2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe"
end

function Test.validate_state(state, run_id)
    assert(type(state) == "table" and state.schemaVersion == 1 and state.runId == run_id and CASES[state.case]
        and (state.status == "running" or TERMINAL[state.status])
        and type(state.mutationStarted) == "boolean" and type(state.cleanupComplete) == "boolean"
        and type(state.artifactSha256) == "string" and #state.artifactSha256 == 64 and state.artifactSha256:match("^%x+$"),
        "Startup test outcome is invalid")
    assert(Cadence.plan_valid(state),"Cadence capture policy is invalid")
    if state.case==Cadence.CASE and state.cleanupComplete then
        assert(Cadence.settled(state.cadence),"Cadence lease cleanup is unresolved")
        if state.status=="passed" then assert(Cadence.passed(state.cadence),"Cadence lease was not restored or disposed") end
        if state.cadence.runtimeDisposition=="WORLD_FINALIZED" then
            assert(state.status=="blocked" and state.code=="cadence-world-finalized"
                and state.failedArtifactSha256==state.artifactSha256 and state.npcsFinalized==1 and state.helpersFinalized==1
                and state.spawned==1 and state.initialized==1 and state.cleaned==0
                and state.helpersCreated==1 and state.helpersCleaned==0
                and world_finalization_proof(state,state.finalization), "Cadence world finalization evidence is invalid")
        end
    end
    assert(state.baseOrdinal==nil or (util.is_integer(state.baseOrdinal) and state.baseOrdinal>=1
        and state.baseOrdinal<=64 and state.case~="class-catalog"),"Startup test base selection is invalid")
    for _, field in ipairs({ "spawned", "initialized", "cleaned", "moved" }) do
        assert(util.is_integer(state[field]) and state[field] >= 0 and state[field] <= CASES[state.case], "Startup test counts are invalid")
    end
    assert(state.cleaned <= state.spawned and state.initialized <= state.spawned
        and (state.mutationStarted or state.spawned == 0), "Startup test ownership counts are inconsistent")
    assert(util.is_integer(state.npcsFinalized or 0) and (state.npcsFinalized or 0) >= 0
        and state.cleaned + (state.npcsFinalized or 0) <= state.spawned, "Startup NPC finalization counts are invalid")
    if Shape.contract(state.case) then
        assert(state.experiment==Shape.contract(state.case) and state.moved==0 and #state.members<=1
            and #(state.shapeObservations or {})<=2, "Startup shape experiment outcome is invalid")
        if state.status=="passed" then
            assert(state.spawned==1 and state.initialized==1 and state.cleaned==1 and state.helpersCreated==1
                and state.helpersCleaned==1 and #(state.shapeObservations or {})==2, "Startup shape evidence is incomplete")
            for index,observation in ipairs(state.shapeObservations) do
                assert(observation.comparison=="MATCH" and observation.instanceOnly==true
                    and observation.spawnQualified==false, "Startup shape evidence is not a qualification")
                if Shape.is_engagement(state.case) then
                    local receipt=observation.receipt
                    assert(type(receipt)=="table" and receipt.sample==index and receipt.runId==state.runId
                        and receipt.case==state.case and receipt.experiment==state.experiment and receipt.artifactSha256==state.artifactSha256
                        and receipt.memberIndex==1 and receipt.actorAddress~=nil and receipt.actorAddress==state.members[1].actorAddress,
                        "Qualified engagement receipt is invalid")
                end
            end
            if Shape.is_engagement(state.case) then
                local authorization=state.engagementAuthorization
                assert(type(authorization)=="table" and authorization.armed==true and authorization.runId==state.runId
                    and authorization.case==state.case and authorization.experiment==state.experiment
                    and authorization.artifactSha256==state.artifactSha256 and authorization.memberIndex==1
                    and authorization.samples==2 and authorization.baseId==state.members[1].baseId
                    and authorization.actorAddress==state.members[1].actorAddress, "Qualified engagement authorization is invalid")
                assert(state.qualifiedEngagementArmed==true and util.is_integer(state.dealtDamageEvents) and state.dealtDamageEvents>0
                    and util.is_integer(state.dealtDamage) and state.dealtDamage>0,
                    "Qualified engagement requires observed outgoing damage")
            end
        end
    end
    if state.cleanupComplete and state.mutationStarted then
        assert((state.status == "passed" or state.status == "blocked") and state.cleaned + (state.npcsFinalized or 0) == state.spawned,
            "Startup test cleanup outcome is inconsistent")
        assert((state.helpersCreated or 0) == (state.helpersCleaned or 0) + (state.helpersFinalized or 0), "Startup support cleanup is incomplete")
    end
    return state
end

function Test.read_state(directory, run_id, logger, fs)
    local store = Store.new(directory, logger, fs)
    local last = store.records[#store.records]
    if not last or not last.state then return nil end
    return Test.validate_state(last.state, run_id)
end

function Test.finalize_legacy_spawn(store, evidence)
    local last = store.records[#store.records]
    local previous = last and last.state
    assert(previous, "No startup test state is available for finalization")
    Test.validate_state(previous, previous.runId)
    assert(previous.sourceRevision == "f671c2200ba6a83ba879e19c2b7acbf92d2fcbc8"
        and previous.artifactSha256 == "de3f829239dda321796229d5b40274b9587a8fe7c17e764ab898b10a639d6643"
        and previous.case == "spawn-cleanup" and previous.status == "failed" and previous.stage == "spawn"
        and previous.code == "custom-assault-identity" and previous.spawned == 0
        and previous.initialized == 0 and previous.mutationStarted and not previous.cleanupComplete,
        "This startup failure is outside the audited legacy finalization scope")
    local member = previous.members and previous.members[1]
    assert(#previous.members == 1 and member.characterId == "BOSS_Hunter_Rifle" and member.level == 30
        and member.spawnRequested == true and not member.instanceGuid, "Legacy spawn parameters do not match")
    assert(type(evidence) == "table" and evidence.processExitVerified == true and evidence.runId == previous.runId
        and evidence.certificateSha256 == "47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f"
        and evidence.serverExecutableSha256 == "61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256 == "2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe",
        "Verified old-process teardown and the pinned native certificate are required")
    local state = util.deep_copy(previous)
    state.status, state.code, state.cleanupComplete = "blocked", "legacy-runtime-finalized", true
    state.failedArtifactSha256 = previous.artifactSha256
    state.finalization = util.deep_copy(evidence)
    state.finalization.disposition = "old-runtime-ended; ownership-transfers-preserved"
    state.finalizedRequests = 1
    local ok, reason = store:append("startup_legacy_runtime_finalized", { disposition = state.finalization.disposition }, state)
    if not ok then return false, reason end
    return store:save_snapshot(state)
end

function Test.finalize_support_only(store, evidence)
    local last = store.records[#store.records]
    local previous = last and last.state
    assert(previous, "No startup support state is available")
    Test.validate_state(previous, previous.runId)
    assert(previous.sourceRevision == "122eea9932ff9bd8286277a2525d9d78828de601"
        and previous.artifactSha256 == "c60075ba179ef7d5d01f493b8cf9b13fa191ceb4aad967a0f8e3865d8c57f30f"
        and previous.case == "two-base-movement" and previous.status == "running" and previous.stage == "support-wait"
        and previous.spawned == 0 and previous.initialized == 0 and #previous.members == 0
        and previous.helpersCreated == 2 and previous.mutationStarted and not previous.cleanupComplete,
        "This failure is outside the audited support-only finalization scope")
    for _, record in ipairs(store.records) do assert(record.kind ~= "startup_spawn_intent", "NPC work prevents support-only finalization") end
    assert(type(evidence) == "table" and evidence.processExitVerified == true and evidence.runId == previous.runId
        and evidence.dumpSha256 == "d9e0840ab4d5d1f3e375daba5f47bb85eea46b49b28377b5ceeb184bd872985a"
        and evidence.serverExecutableSha256 == "61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256 == "2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe",
        "Verified crashed-world exit and pinned support-only evidence are required")
    local state = util.deep_copy(previous)
    state.status, state.code, state.cleanupComplete = "blocked", "support-runtime-finalized", true
    state.failedArtifactSha256 = previous.artifactSha256
    state.helpersFinalized = previous.helpersCreated - previous.helpersCleaned
    state.finalization = util.deep_copy(evidence)
    state.finalization.disposition = "noncharacter-support-world-ended"
    local ok, reason = store:append("startup_support_runtime_finalized", {disposition=state.finalization.disposition}, state)
    if not ok then return false, reason end
    return store:save_snapshot(state)
end

function Test.finalize_pending_cleanup(store, evidence)
    local last = store.records[#store.records]
    local previous = last and last.state
    assert(previous, "No pending cleanup state is available")
    Test.validate_state(previous, previous.runId)
    assert(previous.sourceRevision == "e4c8cc8dcc7ff3bbd8c5eff93168d5b756170cf3"
        and previous.artifactSha256 == "0f24085e4719a967e45ffcf665c0a8b55ca982c66673537e80ff85454a37640f"
        and previous.case == "two-base-movement" and previous.status == "failed" and previous.stage == "cleanup"
        and previous.code == "custom-assault-despawn" and previous.spawned == 2 and previous.initialized == 2
        and previous.moved == 2 and previous.helpersCreated == 2 and not previous.cleanupComplete,
        "This cleanup timeout is outside the audited finalization scope")
    assert(#previous.members == 2, "Pending cleanup member count differs")
    for _, member in ipairs(previous.members) do
        assert(member.characterId == "BOSS_Hunter_Rifle" and member.level == 30 and member.cleanupRequested == true
            and member.instanceGuid and member.playerGuid, "Pending cleanup lacks exact identity or intent")
        local nonzero = false
        for _, key in ipairs({"A","B","C","D"}) do
            assert(util.is_integer(member.instanceGuid[key]) and member.playerGuid[key] == 0, "Pending cleanup identity is invalid")
            nonzero = nonzero or member.instanceGuid[key] ~= 0
        end
        assert(nonzero, "Pending cleanup instance identity is empty")
    end
    assert(type(evidence) == "table" and evidence.processExitVerified == true and evidence.runId == previous.runId
        and evidence.certificateSha256 == "47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f"
        and evidence.serverExecutableSha256 == "61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256 == "2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe",
        "Verified process exit and pinned runtime-finalization evidence are required")
    local state = util.deep_copy(previous)
    state.status, state.code, state.cleanupComplete = "blocked", "pending-cleanup-runtime-finalized", true
    state.failedArtifactSha256 = previous.artifactSha256
    state.npcsFinalized = previous.spawned - previous.cleaned
    state.helpersFinalized = previous.helpersCreated - previous.helpersCleaned
    state.finalization = util.deep_copy(evidence)
    state.finalization.disposition = "pending-cleanup-world-ended; ownership-transfers-preserved"
    local ok, reason = store:append("startup_pending_cleanup_runtime_finalized", {disposition=state.finalization.disposition}, state)
    if not ok then return false, reason end
    return store:save_snapshot(state)
end

function Test.finalize_shape_support_fault(store,evidence)
    local last=store.records[#store.records]
    local previous=last and last.state
    assert(previous,"No startup support state is available")
    Test.validate_state(previous,previous.runId)
    local weak_fault=previous.runId=="20260909-074037-19fcb48d81ce4063b5c8fe64017c1b9c"
        and previous.sourceRevision=="10fb2eb52a351eed9b8ec5432d30a47991149e4d"
        and previous.artifactSha256=="6c90bc5493830d7178cdb444426fde15feab416afdd21aba856a3fc538b95c0a"
        and previous.case==Shape.CASE and previous.experiment==Shape.CONTRACT
        and previous.code=="unclassified-lua-error"
    local label_fault=previous.runId=="20260909-115941-bf41c96cf6cc43908e718239be625e01"
        and previous.sourceRevision=="cdcff74ecbda2099520b468ae907fb8291ee4586"
        and previous.artifactSha256=="5ab7514eb8fabd04ca144d17254fc29742b016b4a2c2b1a40af7219fe97a208b"
        and previous.case==Shape.ENGAGEMENT_CASE and previous.experiment==Shape.ENGAGEMENT_CONTRACT
        and previous.code=="breadcrumb-before"
    assert((weak_fault or label_fault) and previous.status=="failed" and previous.stage=="spawn"
        and previous.spawned==0 and previous.initialized==0 and previous.cleaned==0
        and previous.helpersCreated==1 and previous.helpersCleaned==0 and #previous.members==1
        and not previous.members[1].spawnRequested and previous.mutationStarted and not previous.cleanupComplete,
        "This failure is outside the audited shape-support finalization scope")
    for _,record in ipairs(store.records) do
        assert(record.kind~="startup_spawn_intent","NPC work prevents support-only finalization")
    end
    assert(type(evidence)=="table" and evidence.processExitVerified==true and evidence.runId==previous.runId
        and evidence.certificateSha256=="47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f"
        and evidence.serverExecutableSha256=="61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256=="2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe",
        "Verified old-world exit and pinned support-only evidence are required")
    local state=util.deep_copy(previous)
    state.status,state.code,state.cleanupComplete="blocked","shape-support-runtime-finalized",true
    state.failedArtifactSha256=previous.artifactSha256
    state.helpersFinalized=1
    state.finalization=util.deep_copy(evidence)
    state.finalization.disposition="noncharacter-support-world-ended; no-NPC-intent"
    local ok,reason=store:append("startup_shape_support_runtime_finalized",{disposition=state.finalization.disposition},state)
    if not ok then return false,reason end
    return store:save_snapshot(state)
end

function Test.finalize_snapshot_support_fault(store,evidence)
    local last=store.records[#store.records]
    local previous=last and last.state
    assert(previous,"No startup support state is available")
    Test.validate_state(previous,previous.runId)
    assert(previous.runId=="20260909-214007-775097135892408489d264fb11408e6e"
        and previous.sourceRevision=="2292fd0ebb2e369da393304ea35adaaec78753c7"
        and previous.artifactSha256=="ac15f8183e9b488e23441fcd06df0306ea50d3361b29eccfffafc26c66ee1ba6"
        and previous.case==Cadence.CASE and previous.status=="running" and previous.stage=="support-configure"
        and previous.spawned==0 and previous.initialized==0 and previous.cleaned==0 and #previous.members==0
        and previous.helpersCreated==1 and previous.helpersCleaned==0 and #previous.helpers==1
        and previous.helpers[1].phase=="deferred" and previous.mutationStarted and not previous.cleanupComplete
        and previous.cadence.status=="NOT_ACQUIRED" and previous.cadence.active==false
        and not previous.cadence.appliedObserved
        and #previous.projectileObservation.creations==0 and #previous.projectileObservation.hits==0,
        "This failure is outside the audited snapshot-support finalization scope")
    local kinds={"startup_test_started","startup_projectile_observer_ready","startup_test_stage",
        "startup_support_intent","startup_support_created","startup_test_stage"}
    assert(#store.records==#kinds and last.sequence==6,"Unexpected snapshot-support journal extent")
    for index,kind in ipairs(kinds) do
        assert(store.records[index].kind==kind and store.records[index].sequence==index,
            "Unexpected work prevents snapshot-support finalization")
    end
    assert(type(evidence)=="table" and evidence.runId==previous.runId and evidence.processExitVerified==true
        and evidence.snapshotFailureLogged==true and evidence.snapshotSequence==5
        and evidence.journalSha256=="04b418e7282ca35df46e1d4c756d228219e1f55cd3011de95d1a76727ef64330"
        and evidence.snapshotSha256=="77465ecb421f607be11717f6ee8d78853ee9ea580f01b1f70020e108ad7c73b4"
        and evidence.evidenceManifestSha256=="8d5c0990a5f7b926426490aaf60743b2f0d013d80838cf2e172711378ca4e21b"
        and evidence.certificateSha256=="47eb24443003b8795e2c3a246a4d0728ddb0c2076fdc76db615c299e1fc4ee8f"
        and evidence.serverExecutableSha256=="61c7d285a7a5072486ae099ae7c7c9be5ef0c34d843e06e05517e1f0bd157c02"
        and evidence.serverPakSha256=="2e6a964a1fe2e8bd7d754648d35240e2c1567e780455aedd22f27dbc9dcedabe",
        "Verified stopped-world and preserved snapshot-failure evidence are required")
    local state=util.deep_copy(previous)
    state.status,state.code,state.cleanupComplete="blocked","snapshot-support-runtime-finalized",true
    state.failedArtifactSha256=previous.artifactSha256
    state.helpersFinalized=1
    state.failure="snapshot-write"
    state.finalization=util.deep_copy(evidence)
    state.finalization.disposition="deferred-noncharacter-world-ended; no-NPC-or-cadence-intent"
    local ok,reason=store:append("startup_snapshot_support_runtime_finalized",{disposition=state.finalization.disposition},state)
    if not ok then return false,reason end
    return store:save_snapshot(state)
end

function Test.finalize_cadence_world(store,evidence)
    local last=store.records[#store.records]
    local previous=last and last.state
    assert(previous,"No cadence failure state is available")
    Test.validate_state(previous,previous.runId)
    assert(world_finalization_proof(previous,evidence),"Exact cadence-world exit and serialization evidence are required")
    local cadence=previous.cadence
    assert(#store.records==44 and last.sequence==44 and last.kind=="startup_test_failed"
        and previous.status=="failed" and previous.code=="unclassified-lua-error" and previous.stage=="engagement"
        and previous.mutationStarted and not previous.cleanupComplete and previous.baseOrdinal==3
        and previous.spawned==1 and previous.initialized==1 and previous.cleaned==0
        and previous.helpersCreated==1 and previous.helpersCleaned==0
        and #previous.members==1 and #previous.helpers==1 and #previous.shapeObservations==2
        and cadence.status=="UNRESOLVED" and cadence.active==false and cadence.retired==true and cadence.generation==2
        and cadence.reason=="projectile-creation-native-fault" and cadence.appliedObserved==true
        and cadence.priorSeconds==10 and math.abs(cadence.appliedSeconds-0.1)<0.0000001
        and cadence.restorationVerified~=true and cadence.disposalVerified~=true
        and cadence.runtimeDisposition==nil, "This failure is outside the exact cadence-world finalization scope")
    local member=previous.members[1]
    assert(member.characterId=="BOSS_Hunter_Rifle" and member.level==30 and member.index==1 and member.slot==1
        and member.spawnRequested==true and member.initialized==true and not member.cleanupRequested and not member.cleaned
        and member.instanceGuid and member.playerGuid and member.actorAddress,
        "Cadence-world finalization lacks the recorded instance target")
    for index,observation in ipairs(previous.shapeObservations) do
        local receipt=observation.receipt
        assert(observation.comparison=="MATCH" and receipt and receipt.sample==index
            and receipt.runId==previous.runId and receipt.artifactSha256==previous.artifactSha256
            and receipt.actorAddress==member.actorAddress, "Cadence-world instance receipt differs")
    end
    for _,record in ipairs(store.records) do
        assert(record.kind~="startup_cadence_restore_intent" and record.kind~="startup_cadence_restored"
            and record.kind~="startup_cleanup_intent" and record.kind~="startup_cleanup_completed",
            "Unexpected runtime work prevents cadence-world finalization")
    end
    local state=util.deep_copy(previous)
    state.status,state.code,state.cleanupComplete="blocked","cadence-world-finalized",true
    state.failedArtifactSha256=previous.artifactSha256
    state.npcsFinalized,state.helpersFinalized=1,1
    state.cadence.runtimeDisposition="WORLD_FINALIZED"
    state.cadence.worldFinalizationVerified=true
    state.finalization=util.deep_copy(evidence)
    state.finalization.disposition="old-runtime-only; unresolved-restoration-preserved; saved-transfers-preserved"
    local ok,reason=store:append("startup_cadence_world_finalized",{disposition=state.finalization.disposition},state)
    if not ok then return false,reason end
    return store:save_snapshot(state)
end

function Test.new(options)
    local plan = assert(options.plan)
    assert(plan.schemaVersion == 1 and CASES[plan.case], "Startup test plan is invalid")
    assert(type(plan.runId) == "string" and plan.runId:match("^[a-z0-9%-]+$") and #plan.runId <= 80, "Startup test run identity is invalid")
    assert(type(plan.sourceRevision) == "string" and #plan.sourceRevision == 40 and plan.sourceRevision:match("^%x+$"), "Startup test source is invalid")
    assert(type(plan.artifactSha256) == "string" and #plan.artifactSha256 == 64 and plan.artifactSha256:match("^%x+$"), "Startup test artifact is invalid")
    assert(plan.baseOrdinal==nil or (util.is_integer(plan.baseOrdinal) and plan.baseOrdinal>=1 and plan.baseOrdinal<=64
        and plan.case~="class-catalog"),"Startup test base selection is invalid")
    assert(plan.experiment==Shape.contract(plan.case), "Startup shape experiment contract is invalid")
    assert(Cadence.plan_valid(plan),"Cadence trial requires its explicit capture policy and fixed interval")
    local self = setmetatable({
        engine = assert(options.engine), store = assert(options.store), logger = assert(options.logger),
        clock = options.clock or util.now_seconds, runtime = {}, cursor = 1, damageQueue = {},
        state = { schemaVersion = 1, runId = plan.runId, case = plan.case, sourceRevision = plan.sourceRevision,
            artifactSha256 = plan.artifactSha256,
            baseOrdinal=plan.baseOrdinal,
            experiment=plan.experiment, experimentalPremise=Shape.contract(plan.case) and Shape.PREMISE or nil,
            capturePolicy=plan.capturePolicy,cadenceSeconds=plan.cadenceSeconds,
            cadence=plan.case==Cadence.CASE and {status="NOT_ACQUIRED",active=false,retired=false,generation=0} or nil,
            status = "running", stage = plan.case == "class-catalog" and "class-catalog" or "world",
            startedAt = (options.clock or util.now_seconds)(),
            mutationStarted = false, cleanupComplete = false, members = {},
            spawned = 0, initialized = 0, moved = 0, cleaned = 0, simultaneous = false,
            helpers = {}, helpersCreated = 0, helpersCleaned = 0 },
    }, Test)
    assert(self.store.sequence == 0, "Startup test was already consumed; it cannot be replayed")
    self:_save("startup_test_started")
    return self
end

function Test:on_damage(attacker, defender, amount)
    if self.stopped or self.state.stage ~= "engagement" or not util.is_integer(amount) or amount <= 0 then return end
    if self.state.case~= "engagement" and not Shape.is_engagement(self.state.case) then return end
    if Shape.is_engagement(self.state.case) and not self.state.qualifiedEngagementArmed then return end
    if self.state.case==Cadence.CASE and not self.state.cadence.active then return end
    if #self.damageQueue >= 64 then self.damageOverflow = true; return end
    self.damageQueue[#self.damageQueue + 1] = {attacker=attacker,defender=defender,amount=amount}
end

function Test:_damage_witness()
    local pending = self.damageQueue
    self.damageQueue = {}
    for _, event in ipairs(pending) do
        for index, runtime in ipairs(self.runtime) do
            local member = self.state.members[index]
            if runtime.actor and member.phase == "alive" and not member.cleanupRequested then
                if self.engine:sameActor(runtime.actor, event.attacker) then
                    local ok,allowed
                    if Shape.is_engagement(self.state.case) then
                        local member_plan=util.shallow_copy(member)
                        member_plan.handle=runtime.handle
                        local result
                        ok,result=self.engine:startup_qualified_damage_target(self.scopes[index],member_plan,event.attacker,event.defender)
                        if self.stopped then return false end
                        if not ok then return self:halt(result) end
                        if type(result)~="table" or type(result.allowed)~="boolean" or type(result.active)~="boolean" then
                            return self:halt("Custom assault scope is invalid")
                        end
                        if not result.active then
                            self.state.failure="engagement-permit-revoked"
                            self:_stage("cleanup")
                            return false
                        end
                        allowed=result.allowed
                    else
                        ok,allowed=self.engine:startup_damage_target(self.scopes[index],event.defender)
                        if self.stopped then return false end
                    end
                    if not ok then return self:halt(allowed) end
                    if allowed then
                        self.state.dealtDamageEvents = (self.state.dealtDamageEvents or 0) + 1
                        self.state.dealtDamage = (self.state.dealtDamage or 0) + event.amount
                    end
                end
                if self.engine:sameActor(runtime.actor,event.defender) then
                    self.state.receivedDamageEvents = (self.state.receivedDamageEvents or 0) + 1
                end
            end
        end
    end
    if #pending > 0 then return self:_save("startup_damage_observed") end
    return true
end

function Test:_save(kind)
    if self.journalFailed then return false end
    local hooks=self.engine.bridge and self.engine.bridge.hook_observed or {}
    self.state.damageHookCalls,self.state.deathHookCalls=hooks.damage or 0,hooks.death or 0
    self.state.pendingDamageReceipts=#self.damageQueue
    local called, ok = pcall(self.store.append, self.store, kind, { stage = self.state.stage, status = self.state.status }, self.state)
    if not called or not ok then
        self.state.status, self.state.code = "failed", "journal-write"
        self.stopped, self.journalFailed = true, true
        self.state.cleanupComplete = not self.state.mutationStarted
        if self.engine.startup_test_stage_changed then self.engine:startup_test_stage_changed(self,"failed") end
        self.logger:error("Startup test journal failed; native work stopped")
        return false
    end
    local snapshot_called, saved, snapshot_error, snapshot_phase = pcall(self.store.save_snapshot, self.store, self.state)
    if not snapshot_called or not saved then
        self.state.status, self.state.code = "failed", "snapshot-write"
        local known_phases={["snapshot-temp-write"]=true,["snapshot-backup-rename"]=true,["snapshot-install-rename"]=true}
        local phase=known_phases[snapshot_phase] and snapshot_phase or (snapshot_called and "snapshot-write" or "snapshot-exception")
        local category=snapshot_called and "filesystem-error" or "exception"
        if snapshot_called and type(snapshot_error)=="string" then
            local message=snapshot_error:lower()
            if message:find("permission denied",1,true) or message:find("sharing violation",1,true)
                or message:find("being used by another process",1,true) then category="permission-or-sharing"
            elseif message:find("disk full",1,true) or message:find("no space left",1,true) then category="storage-full" end
        end
        self.state.persistenceFailure={phase=phase,category=category}
        self.stopped, self.journalFailed = true, true
        self.state.cleanupComplete = not self.state.mutationStarted
        if self.engine.startup_test_stage_changed then self.engine:startup_test_stage_changed(self,"failed") end
        -- The preceding append succeeded. Record this distinct failure once without retrying the snapshot.
        local recorded, appended=pcall(self.store.append,self.store,"startup_snapshot_failed",self.state.persistenceFailure,self.state)
        if not recorded or not appended then self.logger:error("Startup snapshot failure marker could not be journaled; native work remains stopped") end
        self.logger:error("Startup test snapshot failed; native work stopped",self.state.persistenceFailure)
        return false
    end
    return true
end

function Test:halt(reason)
    if self.stopped then return false end
    self.stopped = true
    self.state.status = "failed"
    if self.engine.startup_test_stage_changed then self.engine:startup_test_stage_changed(self,"failed") end
    reason = self.engine.bridge and self.engine.bridge.native_fault or reason
    self.state.code = type(reason) == "string" and reason:match("%[([a-z0-9%-]+)%]") or nil
    self.state.code = self.state.code or Diagnostic.classify_error(reason)
    self.state.cleanupComplete = not self.state.mutationStarted
    self.state.finishedAt = self.clock()
    self:_save("startup_test_failed")
    self.logger:error("Startup test stopped", { stage = self.state.stage, code = self.state.code,
        spawned = self.state.spawned, initialized = self.state.initialized, cleaned = self.state.cleaned })
    return false
end

function Test:_stage(stage)
    if self.engine.startup_test_stage_changed and self.engine:startup_test_stage_changed(self,stage)==false then
        return self:halt("Cadence lease restoration is unresolved")
    end
    self.state.stage, self.state.stageStartedAt, self.cursor = stage, self.clock(), 1
    return self:_save("startup_test_stage")
end

function Test:_finish(status, code)
    if self.engine.startup_test_stage_changed and self.engine:startup_test_stage_changed(self,"finished")==false then
        return self:halt("Cadence lease restoration is unresolved")
    end
    if self.state.case==Cadence.CASE and (not Cadence.settled(self.state.cadence)
        or (status=="passed" and not Cadence.passed(self.state.cadence))) then
        return self:halt("Cadence lease restoration is unresolved")
    end
    self.state.status, self.state.code = status, code
    self.state.cleanupComplete, self.state.finishedAt = true, self.clock()
    if not self:_save("startup_test_finished") then return false end
    self.stopped = true
    self.logger:info("Startup test finished", { case = self.state.case, status = status, code = code,
        spawned = self.state.spawned, initialized = self.state.initialized,
        moved = self.state.moved, cleaned = self.state.cleaned, simultaneous = self.state.simultaneous })
end

function Test:_plan_members()
    for index, scope in ipairs(self.scopes) do
        self.state.members[index] = { index = index, baseId = scope.baseId,
            groupId = "startup:" .. self.state.runId, slot = 1, characterId = "BOSS_Hunter_Rifle",
            level = 30, phase = "planned", spawnLocation = scope.positions and util.shallow_copy(scope.positions[1]) or nil,
            baseOrigin = util.shallow_copy(scope.origin), leashRadius = scope.leashRadius }
    end
    return self:_stage("spawn")
end

function Test:_cleaned_npcs()
    if self.state.helpersCreated > self.state.helpersCleaned then return self:_stage("support-cleanup") end
    return self:_finish(self.state.failure and "blocked" or "passed",
        self.state.failure or (self.state.case==Shape.CASE and "shape-instance-only"
            or self.state.case==Cadence.CASE and "cadenced-engagement-damage-observed"
            or self.state.case==Shape.ENGAGEMENT_CASE and "qualified-engagement-damage-observed" or "complete"))
end

function Test:_update_identity(member)
    if member.instanceGuid and (not Shape.contract(self.state.case) or member.actorAddress) then return true end
    local identity = self.engine:startup_identity(member)
    local changed=false
    if identity.instanceGuid and not member.instanceGuid then
        member.instanceGuid, member.playerGuid = identity.instanceGuid, identity.playerGuid
        changed=true
    end
    if identity.actorAddress and not member.actorAddress then member.actorAddress=identity.actorAddress; changed=true end
    if changed then return self:_save("startup_identity_assigned") end
    return true
end

local function distance2(left, right)
    return (left.X - right.X) ^ 2 + (left.Y - right.Y) ^ 2
end

function Test:_tick()
    if self.stopped or TERMINAL[self.state.status] then return end
    local now = self.clock()
    local stage = self.state.stage
    if self.state.case==Cadence.CASE then
        if self.state.cadence.status=="UNRESOLVED" then return self:halt("Cadence lease restoration is unresolved") end
        if stage=="world" and not Cadence.admission(self.engine,self) then
            return self:_finish("blocked","cadence-barrier-unavailable")
        end
        if stage=="engagement" and self.state.cadence.retired then
            self.state.failure=self.state.failure or "cadence-retired"
            return self:_stage("cleanup")
        end
    end
    if stage == "class-catalog" then
        self.catalog = self.catalog or bounties.roster()
        self.state.catalog = self.state.catalog or {}
        local member = self.catalog[self.cursor]
        if not member then return self:_finish("passed", "catalog-classes-qualified") end
        local ok, result = self.engine:startup_catalog_entry(member.id)
        if not ok then return self:halt(result) end
        self.state.catalog[#self.state.catalog + 1] = result
        if not self:_save("startup_catalog_class_qualified") then return end
        self.cursor = self.cursor + 1
    elseif stage == "world" then
        local ok, result = self.engine:startup_prepare(CASES[self.state.case],self.state.baseOrdinal)
        if not ok then return self:halt(result) end
        if not result then
            if now >= self.state.startedAt + 120 then self:_finish("blocked", "world-or-bases-not-ready") end
            return
        end
        self.state.physical = result.physical
        self.state.availableBases = result.availableBases
        if result.blockedCode or Shape.contract(self.state.case) then
            self.scopes = result.scopes or result.candidates
            if type(self.scopes) ~= "table" or #self.scopes ~= CASES[self.state.case] then
                return self:_finish("blocked", result.blockedCode or "shape-base-unavailable")
            end
            self.support = self.engine:startup_support(self.scopes)
            local prepared, available = self.support:prepare()
            if not prepared then return self:halt(available) end
            if not available then return self:_finish("blocked", "streaming-subsystem-unavailable") end
            return self:_stage("support-spawn")
        end
        self.scopes = result.scopes
        assert(type(self.scopes) == "table" and #self.scopes == CASES[self.state.case], "Startup test returned an invalid base count")
        if self.state.case == "prewarm" then return self:_finish("passed", "physical-ready-without-support") end
        if self.state.case == "surface-survey" then return self:_stage("surface-survey") end
        return self:_plan_members()
    elseif stage == "surface-survey" then
        if not self:_save("startup_surface_survey_intent") then return end
        local ok,result=self.engine:startup_surface_survey(self.scopes[1])
        if not ok then return self:halt(result) end
        if type(result)~="table" or type(result.complete)~="boolean" or result.spawnQualified~=false then
            return self:halt("Custom assault scope is invalid")
        end
        self.state.surfaceSurvey=result
        if not result.complete then self.state.failure=result.code or "surface-survey-unavailable" end
        if not self:_save("startup_surface_survey_observed") then return end
        return self:_cleaned_npcs()
    elseif stage == "support-spawn" then
        local index = self.cursor
        if index > #self.scopes then return self:_stage("support-configure") end
        self.state.mutationStarted = true
        self.state.helpers[index] = { phase = "requested" }
        if not self:_save("startup_support_intent") then return end
        local ok, identity = self.support:begin(index)
        if not ok then return self:halt(identity) end
        self.state.helpers[index] = { phase = "deferred", identity = identity }
        self.state.helpersCreated = self.state.helpersCreated + 1
        if not self:_save("startup_support_created") then return end
        self.cursor = index + 1
    elseif stage == "support-configure" then
        local index = self.cursor
        if index > self.state.helpersCreated then return self:_stage("support-wait") end
        if not self:_save("startup_support_configure_intent") then return end
        local ok, result = self.support:finish(index)
        if not ok then return self:halt(result) end
        self.state.helpers[index].phase = "configured"
        if not self:_save("startup_support_configured") then return end
        self.cursor = index + 1
    elseif stage == "support-wait" then
        local ready = 0
        for index, helper in ipairs(self.state.helpers) do
            local ok, observation = self.support:poll(index)
            if not ok then return self:halt(observation) end
            helper.observation = observation
            if observation.ready then ready = ready + 1 end
        end
        if ready == self.state.helpersCreated then
            self.state.physicalPrewarmPassed = true
            if self.state.case == "prewarm" then return self:_stage("support-cleanup") end
            if self.state.case == "surface-survey" then return self:_stage("surface-survey") end
            return self:_plan_members()
        end
        if now >= self.state.stageStartedAt + 120 then
            self.state.failure = "physical-prewarm-timeout"
            return self:_stage("support-cleanup")
        end
        if now >= (self.nextSupportCheckpoint or 0) then
            self.nextSupportCheckpoint = now + 5
            return self:_save("startup_support_observation")
        end
    elseif stage == "support-cleanup" then
        for index, helper in ipairs(self.state.helpers) do
            if not helper.cleaned then
                if not helper.cleanupRequested then
                    helper.cleanupRequested = true
                    helper.cleanupRequestedAt = now
                    if not self:_save("startup_support_cleanup_intent") then return end
                end
                local ok, complete = self.support:close(index)
                if not ok then return self:halt(complete) end
                if complete then
                    helper.cleaned = true
                    self.state.helpersCleaned = self.state.helpersCleaned + 1
                    if not self:_save("startup_support_cleaned") then return end
                elseif now >= helper.cleanupRequestedAt + 60 then
                    return self:halt("Startup support cleanup did not complete")
                end
            end
        end
        if self.state.helpersCleaned == self.state.helpersCreated then return self:_cleaned_npcs() end
    elseif stage == "spawn" then
        local member = self.state.members[self.cursor]
        if not member then return self:_stage("initialize") end
        member.placementStartedAt = member.placementStartedAt or now
        if Shape.contract(self.state.case) and now>=member.placementStartedAt+120 then
            self.state.failure="spawn-placement-timeout"
            return self:_stage("cleanup")
        end
        local prepared, placement = self.engine:prepare_spawn(self.scopes[self.cursor], member)
        if not prepared then return self:halt(placement) end
        if type(placement) ~= "table" or type(placement.ready) ~= "boolean" then
            return self:halt("Custom assault placement is unavailable")
        end
        member.placementMode, member.placementAttempts = placement.mode, placement.attempts
        member.placementReason, member.fallbackReason = placement.reason, placement.fallbackReason
        if Shape.contract(self.state.case) then
            if placement.spawnQualified~=false or placement.experiment~=Shape.contract(self.state.case)
                or (placement.pending==true and (placement.ready~=false
                    or (placement.reason~="shape-residency-pending" and placement.reason~="shape-site-search-pending"))) then
                return self:halt("Custom assault scope is invalid")
            end
            if placement.residency then self.state.helpers[1].observation=placement.residency end
            member.siteSelection=placement.selection
            self.state.surfaceSurvey=placement.surfaceSurvey
            member.plannedGeometry=placement.plannedGeometry
            member.defaultNavDataUsed=placement.defaultNavDataUsed
            member.pathPoints,member.pathLength=placement.pathPoints,placement.pathLength
            if not self:_save("startup_shape_placement_observed") then return end
        end
        if placement.pending == true and placement.ready == false then
            if now < member.placementStartedAt + 120 then
                return self:_save("startup_placement_pending")
            end
            self.state.failure = "spawn-placement-timeout"
            return self:_stage("cleanup")
        elseif placement.pending ~= nil and placement.pending ~= false then
            return self:halt("Custom assault placement is unavailable")
        end
        if not placement.ready then
            self.state.failure = Shape.contract(self.state.case) and (placement.reason or "shape-placement-unavailable") or "spawn-physical-unavailable"
            member.placementReason = placement.reason
            return self:_stage("cleanup")
        end
        if placement.position then member.spawnLocation = util.shallow_copy(placement.position) end
        if placement.goal then member.goalLocation = util.shallow_copy(placement.goal) end
        member.phase, member.spawnRequested = "requested", true
        self.state.mutationStarted = true
        if not self:_save("startup_spawn_intent") then return end
        local ok, handle = self.engine:spawn(self.scopes[self.cursor], member)
        if not ok then return self:halt(handle) end
        local identity = self.engine:startup_identity(member)
        member.instanceGuid, member.playerGuid = identity.instanceGuid, identity.playerGuid
        member.handleAddress = identity.handleAddress
        member.phase = "pending"
        self.runtime[self.cursor] = { handle = handle }
        self.state.spawned = self.state.spawned + 1
        if not self:_save("startup_spawn_returned") then return end
        self.cursor = self.cursor + 1
        return
    elseif stage=="shape-observe" then
        if not Shape.contract(self.state.case) or #self.state.members~=1 then return self:halt("Custom assault scope is invalid") end
        if now>self.state.stageStartedAt+10 then
            self.state.failure="shape-observation-timeout"
            return self:_stage("cleanup")
        end
        if now<(self.nextShapeObservationAt or 0) then return end
        self.nextShapeObservationAt=now+1
        local member=self.state.members[1]
        local plan=util.shallow_copy(member)
        plan.handle=self.runtime[1].handle
        if not self:_save("startup_shape_observation_intent") then return end
        local ok,result=self.engine:startup_shape_observation(self.scopes[1],plan)
        if not ok then return self:halt(result) end
        if type(result)~="table" or result.spawnQualified~=false or result.instanceOnly~=true
            or (result.comparison~="MATCH" and result.comparison~="MISMATCH" and result.comparison~="UNSUPPORTED") then
            return self:halt("Custom assault scope is invalid")
        end
        self.state.shapeObservations=self.state.shapeObservations or {}
        self.state.shapeObservations[#self.state.shapeObservations+1]=result
        if not self:_save("startup_shape_observed") then return end
        if result.comparison~="MATCH" then
            self.state.failure="shape-"..result.comparison:lower()
            return self:_stage("cleanup")
        end
        if #self.state.shapeObservations==2 then
            return self:_stage(Shape.is_engagement(self.state.case) and "engagement" or "cleanup")
        end
        return
    elseif stage == "initialize" or stage == "movement" or stage == "engagement" then
        if Shape.is_engagement(self.state.case) and stage=="engagement" then
            if now>=self.state.stageStartedAt+60 then
                self.state.failure="engagement-timeout"
                return self:_stage("cleanup")
            end
            if not self.state.qualifiedEngagementArmed then
                local plan=util.shallow_copy(self.state.members[1])
                plan.handle=self.runtime[1].handle
                if not self:_save("startup_qualified_engagement_arm_intent") then return end
                local ok,result=self.engine:startup_arm_qualified_engagement(self.scopes[1],plan)
                if self.stopped then return end
                if not ok then return self:halt(result) end
                if type(result)~="table" or type(result.armed)~="boolean" then return self:halt("Custom assault scope is invalid") end
                if not result.armed then
                    self.state.failure=result.reason or "engagement-arm-unavailable"
                    return self:_stage("cleanup")
                end
                self.state.engagementAuthorization=result
                self.state.qualifiedEngagementArmed=true
                return self:_save("startup_qualified_engagement_armed")
            end
            if self.state.case==Cadence.CASE and not self.state.cadence.appliedObserved then
                local plan=util.shallow_copy(self.state.members[1])
                plan.handle=self.runtime[1].handle
                if not self:_save("startup_cadence_acquire_intent") then return end
                local ok,acquired=self.engine:startup_acquire_cadence(self.scopes[1],plan)
                if not ok then return self:halt(acquired) end
                if self.stopped then return end
                if not acquired then
                    self.state.failure=self.state.failure or "cadence-acquire-unavailable"
                    return self:_stage("cleanup")
                end
                return self:_save("startup_cadence_ready")
            end
        end
        local ready, arrived = 0, 0
        for index, member in ipairs(self.state.members) do
            local runtime = self.runtime[index]
            local plan = util.shallow_copy(member)
            plan.handle = runtime.handle
            local ok, observation = self.engine:inspect(runtime.handle, plan)
            if self.stopped then return end
            if not ok then return self:halt(observation) end
            if not self:_update_identity(member) then return end
            member.phase = observation.phase
            if observation.actor then runtime.actor = observation.actor end
            member.waitingOn = observation.waitingOn
            member.scopeReason = observation.scopeReason
            member.distanceFromBase, member.heightFromBase = observation.distanceFromBase, observation.heightFromBase
            if observation.location then member.lastLocation = util.shallow_copy(observation.location) end
            if observation.phase == "alive" then
                ready = ready + 1
                if not member.initialized then
                    member.initialized, member.healthBudget = true, observation.healthBudget
                    member.targetId = observation.targetId
                    member.actorAddress = observation.actorAddress
                    runtime.initialLocation = util.shallow_copy(observation.location)
                    member.initialLocation = util.shallow_copy(observation.location)
                    self.state.initialized = self.state.initialized + 1
                    if not self:_save("startup_member_initialized") then return end
                end
                if stage == "movement" then
                    if not member.travelRequested then
                        member.travelRequested = true
                        if not self:_save("startup_movement_intent") then return end
                        local moved, reason = self.engine:startup_travel(self.scopes[index], plan)
                        if not moved then return self:halt(reason) end
                    end
                    local target = member.goalLocation or self.scopes[index].origin
                    if distance2(observation.location, runtime.initialLocation) >= 300 ^ 2
                        and distance2(observation.location, target) <= 1100 ^ 2 then
                        local checked, arrival = self.engine:startup_arrival(self.scopes[index],plan)
                        if not checked then return self:halt(arrival) end
                        if type(arrival)~="table" or type(arrival.arrived)~="boolean" then
                            return self:halt("Custom assault scope is invalid")
                        end
                        member.arrivalObservation = arrival
                        if arrival.arrived then
                            arrived = arrived + 1
                            if not member.arrived then
                                member.arrived = true
                                self.state.moved = self.state.moved + 1
                                if not self:_save("startup_movement_observed") then return end
                            end
                        elseif now >= (member.nextArrivalCheckpoint or 0) then
                            member.nextArrivalCheckpoint = now + 5
                            if not self:_save("startup_arrival_pending") then return end
                        end
                    end
                elseif stage == "engagement" then
                    local dispatched, result = false, nil
                    if now >= (member.nextEngageAt or 0) then
                        member.nextEngageAt = now + 5
                        if not self:_save("startup_engagement_intent") then return end
                        local engaged
                        engaged, result = self.engine:engage(self.scopes[index],plan)
                        if self.stopped then return end
                        if not engaged then return self:halt(result) end
                        member.behavior = self.engine:startup_behavior(member)
                        dispatched = true
                    end
                    if dispatched or now >= (member.nextObserveAt or 0) then
                        member.nextObserveAt = now + 1
                        local observed, details = self.engine:startup_combat_observation(self.scopes[index],plan)
                        if self.stopped then return end
                        if not observed then return self:halt(details) end
                        member.combatObservation = details
                        if not self:_save(dispatched and "startup_engagement_returned" or "startup_combat_observed") then return end
                    end
                    if result == "unavailable" then
                        self.state.failure = "engagement-unavailable"
                        return self:_stage("cleanup")
                    end
                end
            elseif observation.phase == "dead" or observation.phase == "captured" or observation.phase == "missing"
                or observation.phase == "escaped" then
                if stage == "engagement" and observation.phase == "escaped" then
                    local observed, details = self.engine:startup_combat_observation(self.scopes[index],plan,true)
                    if self.stopped then return end
                    if not observed then return self:halt(details) end
                    member.combatObservation = details
                    if not self:_save("startup_combat_observed") then return end
                end
                self.state.failure = "unexpected-member-" .. observation.phase
                return self:_stage("cleanup")
            elseif stage=="engagement" and Shape.is_engagement(self.state.case) then
                self.state.failure="engagement-member-"..observation.phase
                return self:_stage("cleanup")
            end
        end
        if ready == #self.state.members then
            self.state.simultaneous = #self.state.members > 1
            if stage == "initialize" then
                if Shape.contract(self.state.case) then return self:_stage("shape-observe") end
                if self.state.case == "engagement" and self.state.members[1].placementMode == "in-base" then
                    return self:_stage("engagement")
                end
                return self:_stage(self.state.case == "spawn-cleanup" and "cleanup" or "movement")
            end
            if stage == "movement" and arrived == #self.state.members then
                return self:_stage(self.state.case == "engagement" and "engagement" or "cleanup")
            end
        end
        if stage == "engagement" then
            if self.damageOverflow then
                self.state.failure = "damage-observation-overflow"
                return self:_stage("cleanup")
            end
            if not self:_damage_witness() then return end
            if (self.state.dealtDamageEvents or 0) > 0 then return self:_stage("cleanup") end
        end
        if now >= self.state.stageStartedAt + 60 then
            self.state.failure = stage .. "-timeout"
            return self:_stage("cleanup")
        end
        return
    elseif stage == "cleanup" then
        for index, member in ipairs(self.state.members) do
            if not member.spawnRequested and not member.skipped then
                member.skipped, member.phase = true, "not-spawned"
                if not self:_save("startup_member_skipped") then return end
            elseif member.spawnRequested and not member.cleaned then
                local runtime = self.runtime[index]
                local plan = util.shallow_copy(member)
                plan.handle = runtime and runtime.handle
                local ok, outcome
                if member.cleanupRequested then
                    ok, outcome = self.engine:inspect(plan.handle, plan)
                    if ok then
                        outcome = outcome.phase
                        if outcome == "missing" then outcome = "despawned" end
                    end
                else
                    local inspected, state = self.engine:inspect(plan.handle, plan)
                    if not inspected then return self:halt(state) end
                    if not self:_update_identity(member) then return end
                    if state.phase == "pending" or state.phase=="capturing" then
                        if not member.cleanupWaitingAt then
                            member.cleanupWaitingAt = now
                            if not self:_save("startup_cleanup_awaiting_identity") then return end
                        end
                        ok, outcome = true, "initializing"
                    else
                        member.cleanupRequested = true
                        member.cleanupRequestedAt = now
                        plan.instanceGuid, plan.playerGuid = member.instanceGuid, member.playerGuid
                        if not self:_save("startup_cleanup_intent") then return end
                        ok, outcome = self.engine:despawn(self.scopes[index], plan)
                    end
                end
                if not ok then return self:halt(outcome) end
                if outcome == "initializing" then
                    if now >= member.cleanupWaitingAt + 60 then return self:halt("Custom assault initialization is incomplete") end
                elseif outcome == "despawned" or outcome == "captured" or outcome == "dead" or outcome == "missing" then
                    member.cleaned, member.phase = true, outcome
                    self.state.cleaned = self.state.cleaned + 1
                    if outcome ~= "despawned" then self.state.failure = self.state.failure or "cleanup-" .. outcome end
                    if not self:_save("startup_cleanup_completed") then return end
                elseif outcome ~= "pending" and outcome ~= "despawning" then
                    return self:halt("Startup test cleanup is unresolved")
                elseif now >= member.cleanupRequestedAt + 60 then
                    return self:halt("Custom assault despawn did not complete")
                end
            end
        end
        if self.state.cleaned == self.state.spawned then
            return self:_cleaned_npcs()
        end
    else
        return self:halt("Startup test stage is invalid")
    end
end

function Test:tick()
    if self.stopped then return end
    local ok, reason = pcall(function() self:_tick() end)
    if not ok then self:halt(reason) end
end

function Test.attach(bridge, data_directory, options)
    options = options or {}
    local fs, getenv = options.filesystem or filesystem, options.getenv or os.getenv
    local run_id = getenv("PAL_EVENT_DIRECTOR_STARTUP_TEST_RUN")
    local root = path.join(data_directory, "startup-tests")
    local pointer_path = path.join(root, "active.json")
    local active
    if fs.exists(pointer_path) then active = json.decode(assert(fs.read(pointer_path))) end
    if run_id == nil or run_id == "" then
        if active then
            assert(type(active.runId) == "string" and active.runId:match("^[a-z0-9%-]+$") and #active.runId <= 80,
                "Startup test pointer is invalid")
            local state = Test.read_state(path.join(root, active.runId), active.runId, bridge.logger, fs)
            if state then
                if state.mutationStarted and not state.cleanupComplete then
                    bridge.startup_quarantine = "An interrupted startup test retains uncertain owned entities; native starts are quarantined."
                end
            else
                bridge.startup_quarantine = "A startup test has no durable outcome; native starts are quarantined pending investigation."
            end
        end
        return
    end
    assert(getenv("COMPUTERNAME") == "IMOUTO" and bridge.delivery_profile == "laboratory-native-test"
        and bridge.config.mode == "laboratory" and bridge.config.capabilities.startAllInvasions == true,
        "Startup tests require the IMOUTO laboratory profile")
    assert(active and active.runId == run_id and run_id:match("^[a-z0-9%-]+$") and #run_id <= 80,
        "Startup test launch intent does not match")
    local directory = path.join(root, run_id)
    local plan = json.decode(assert(fs.read(path.join(directory, "plan.json"))))
    assert(plan.runId == run_id and plan.sourceRevision == getenv("PAL_EVENT_DIRECTOR_SOURCE_REVISION"),
        "Startup test plan provenance does not match the launcher")
    assert(plan.artifactSha256 == getenv("PAL_EVENT_DIRECTOR_ARTIFACT_SHA256"), "Startup test artifact does not match the launcher")
    if plan.previousRunId then
        assert(type(plan.previousRunId) == "string" and plan.previousRunId:match("^[a-z0-9%-]+$") and #plan.previousRunId <= 80,
            "Previous startup test identity is invalid")
        local previous = assert(Test.read_state(path.join(root, plan.previousRunId), plan.previousRunId, bridge.logger, fs),
            "Previous startup test has no durable outcome")
        assert(not previous.mutationStarted or previous.cleanupComplete, "Previous startup test retains uncertain entities")
        assert(previous.failedArtifactSha256 ~= plan.artifactSha256
            and not ((previous.status == "failed" or previous.status == "running") and previous.artifactSha256 == plan.artifactSha256),
            "Failed startup tests cannot repeat on the same artifact")
    end
    local store = Store.new(directory, bridge.logger, fs)
    bridge.startup_test = Test.new({ plan = plan, store = store, engine = bridge:_custom_engine(), logger = bridge.logger, clock = bridge.clock })
end

return Test
