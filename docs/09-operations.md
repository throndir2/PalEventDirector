# Operations design

## Scope

This document plans packaging and operation for a self-hosted Windows Palworld dedicated server. It contains no credentials and does not authorize a production deployment.

## Runtime baseline

- Windows dedicated-server edition of Palworld.
- One Palworld-compatible UE4SS runtime, selected for the exact game revision.
- Pal Event Director packaged through Pocketpair's official server mod-loader contract.
- Vanilla clients; no client-side package rule for Pal Event Director.
- Palworld REST API restricted to loopback or a protected LAN if the optional sidecar uses it.

## Official package shape

A future release package will keep `Info.json` at its root and declare:

- stable alphanumeric `PackageName`;
- incremented `Version`;
- tested `MinRevision`;
- the exact UE4SS package identity as a dependency;
- a Lua install rule with `IsServer: true`;
- no client install rule unless the product contract is intentionally changed, which is currently prohibited.

The server operator stages the package under the official Workshop/package root, lists dependency and project `PackageName` values in `Mods/PalModSettings.ini`, and restarts. The official loader deploys managed files and records an install manifest.

## Configuration separation

| Class | Examples | Update behavior |
|---|---|---|
| Packaged defaults | Built-in templates, schemas, revision adapter | Replaced by versioned package update. |
| Operator policy | timezone, caps, enabled capabilities, admin UIDs | Preserved across updates; never shipped with real secrets. |
| Calendar | enabled templates, parameters, recurrence | Preserved and backed up. |
| Runtime state | active occurrences, journal, reward ledger, spawn registry | Preserved, migrated, and backed up. |
| Secrets | optional sidecar HMAC, webhook/token | Stored outside package/repository with restricted ACLs. |
| Logs/metrics | structured runtime records | Rotated and excluded from package. |

Configuration loading is fail-closed. Invalid optional sections use documented safe defaults; invalid identity, state, reward, capability, or cleanup policy prevents affected events from starting.

## Operator workflow

### Add or change a template

1. Edit in a development/staging copy.
2. Run schema validation and deterministic simulation.
3. Preview schedule, claims, actions, maximum rewards, maximum spawns, and cleanup.
4. Test on a disposable world when new capabilities or parameter bounds are involved.
5. Atomically replace the calendar/template file.
6. Ask the director to reload data.
7. Confirm the new digest applies only to future occurrences.

### Start a live event

1. Run template validation against current adapter health.
2. Preview resolved parameters and resource claims.
3. Verify player count/server health.
4. Start with an operator UID-authenticated command or sidecar request.
5. Confirm the occurrence ID and first durable transition.

### Abort an event

1. Issue a graceful abort, not a script reload or server termination.
2. Stop new scoring and spawning.
3. Resolve reward policy (`none`, participation-only, or earned-so-far) from the template.
4. Run mandatory cleanup and release leases.
5. Verify no unresolved ownership/claims remain.
6. Escalate to recovery mode if verification fails.

### Emergency isolation

- Stop accepting new events.
- Use the director's global safety stop when it is responsive.
- Gracefully save and stop the server through the established server-management path.
- Start a copied world with `-NoMods` for diagnosis when required.
- Do not assume disabling the package reverses persistent rewards or orphaned state.
- Do not delete state until reward and cleanup obligations are reconciled.

## Deployment pipeline

A future release/deployment pipeline should enforce:

1. Inventory all repository and server-package changes.
2. Verify source provenance and dependency/runtime hashes.
3. Build a clean package from a tagged commit.
4. Validate package metadata, target folders, and absence of secrets/caches/logs.
5. Run generic unit/simulation tests.
6. Run adapter integration tests on an isolated Windows server.
7. Back up the target world, director state, package, and mod configuration.
8. Deploy to a staging/canary server first.
9. Complete vanilla Steam and claimed cross-play journeys.
10. Confirm save/restart/reconnect/cleanup/removal behavior.
11. Push the exact validated source revision to the canonical remote.
12. Deploy only the artifact traceable to that revision.
13. Verify loader deployment, UE4SS log, adapter probes, server readiness, and vanilla connection.
14. Retain immediate rollback materials and monitor one full event cycle.

Any change after final multiplayer validation invalidates that validation gate.

## Upgrade policy

### Pal Event Director update

- Stop scheduling new occurrences.
- Let active events finish or abort them cleanly.
- Ensure claims/cleanup are resolved.
- Save and stop the server gracefully.
- Back up state/config/package/world.
- Replace staged package with a changed `Version`.
- Start and inspect managed deployment and migration.
- Run smoke journeys before reopening normal scheduling.

### Palworld update

Treat every Palworld update as incompatible until proven otherwise:

1. Freeze the current server, runtime, package, and world backup.
2. Disable automatic event starts.
3. Update an isolated server copy.
4. Select a compatible UE4SS build.
5. regenerate/inspect current dumps and compare used paths/signatures;
6. run observation and adapter contract tests;
7. complete the full vanilla-client matrix;
8. publish a compatibility record;
9. only then update production.

Unknown revisions leave gameplay adapters disabled. A permissive “try anyway” mode is development-only.

### UE4SS update

Never install a second runtime beside the managed one. Test runtime upgrades with the exact project package and game revision. Verify proxy/native files, member-layout requirements, logs, hot-reload behavior, and clean restart.

## Backups

Pre-change backup set:

- Palworld world and player saves;
- director configuration, calendar, snapshot, journal, reward ledger, and archives;
- active package archives and `Info.json`;
- `PalModSettings.ini` and loader install manifests;
- exact server/runtime version and file hashes;
- recent relevant logs.

A backup is not accepted until its contents can be listed and a restoration is rehearsed on a copy. Director state and Palworld save time must be correlated so restoring one without the other does not duplicate rewards or lose cleanup ownership.

## Restore consistency

Restoring a world to time $T$ while retaining a newer reward ledger can suppress legitimate re-earned rewards; restoring a newer world with an older ledger can duplicate them. A backup manifest therefore records a shared checkpoint ID in both the director snapshot metadata and external backup catalog.

After restoration:

1. start with automatic schedules paused;
2. verify world/save checkpoint and director checkpoint;
3. reconcile active occurrences and reward state;
4. abandon future journal records from the discarded timeline into an audit archive;
5. run cleanup recovery;
6. resume scheduling explicitly.

## Health checks

### Startup

- Official loader enabled intended package identities.
- Exactly one UE4SS runtime loaded.
- Project `main.lua` loaded once.
- Game/runtime revision matches an adapter pack.
- World-ready transition occurred once.
- Mandatory manager/function probes passed.
- State replay and schema migration succeeded.
- No unresolved exclusive lease blocks operation.
- Vanilla test client can connect.

### Runtime

- Server FPS/frame time above policy.
- Game-thread queue bounded.
- No hook-registration growth.
- State checkpoint age bounded.
- Journal writes and disk free space healthy.
- Spawn ownership reconciled.
- Pending reward count/age bounded.
- Announcement rate bounded.
- Sidecar/REST status informational unless an event explicitly requires sidecar functionality.

### Event completion

- Final score digest recorded.
- Reward obligations created once.
- Delivery statuses known.
- Director-owned actors resolved.
- Signs restored or transferred according to policy.
- Modifier baselines restored and verified.
- Resource claims released.
- Occurrence archived.

## Rollback

A package rollback is allowed only after understanding state schema compatibility. The preferred release supports reading the immediately previous state schema. Otherwise:

1. pause schedules and cleanly finish/abort events;
2. back up current data;
3. run a documented downgrade migration if supported;
4. restore the prior package and matching state checkpoint;
5. restore the corresponding world checkpoint if game mutations require it;
6. validate with vanilla clients.

Never overwrite current state with an old snapshot merely to make an older binary start.

## Log and data retention

Proposed defaults:

- Active journal: until compacted into verified checkpoint plus safety window.
- Occurrence summaries: one year or operator policy.
- Reward ledger: at least as long as the world exists, compacted without losing unique keys.
- Detailed normalized event logs: short rolling window, with sampled/aggregated high-volume signals.
- Metrics: rolling operational window.
- Crash and compatibility evidence: retained with release records.

Player-facing exports should minimize platform identifiers. Internal player UIDs may be necessary for correctness but are access-controlled and never posted to public dashboards by default.

## Optional sidecar operations

The sidecar may:

- render calendar and status;
- validate and stage definition files;
- consume director outbox events;
- publish sanitized Discord/web updates;
- read official REST health/player/metrics endpoints;
- request official save/announce/graceful shutdown operations;
- assist with backups and release evidence.

It may not:

- edit live Palworld saves;
- inject arbitrary Lua or engine paths;
- bypass director authorization;
- expose the REST API or secrets to the Internet;
- silently start an event after losing state synchronization.

## Routine event administration

Recommended cadence:

- Daily: inspect failed actions, pending rewards, queue/health, and next 24 hours.
- Weekly: review event balance, spam volume, participation, abandoned state, and upcoming conflicts.
- Before a special event: run preview/simulation, verify caps and cleanup, and test manual abort.
- After a special event: archive outcome, reconcile rewards, and review performance/errors.
- After any game/runtime update: complete compatibility workflow before resuming schedules.

## Production readiness checklist

- [ ] Current source revision is clean, committed, pushed, and traceable to package hashes.
- [ ] World and director-state backups are verified.
- [ ] Exact Palworld and UE4SS revisions are supported.
- [ ] Official package/dependency deployment succeeds without duplicates.
- [ ] Vanilla Steam and claimed cross-play tests pass.
- [ ] Restart and cleanup tests pass.
- [ ] Every enabled adapter has bounds and a kill switch.
- [ ] Every enabled template has claims, recovery, cleanup, and reward caps.
- [ ] REST/sidecar endpoints are not publicly exposed.
- [ ] Logs and packages contain no credentials.
- [ ] Rollback artifact and procedure are ready.
