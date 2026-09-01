# Roadmap

## Delivery strategy

Build the entire platform as a sequence of independently useful, evidence-gated capabilities. Breadth comes from event composition, not from enabling every reflected function. Later phases expand spectacle and automation without replacing the safety core.

No calendar date is promised. Each phase exits only when its acceptance criteria pass on the current Palworld revision.

## Flagship fast path

The roadmap remains a full-platform plan, but implementation should drive toward **Siege League** as the first complete gameplay vertical slice. Follow the safety dependencies from Phases 0–2, implement the combat-attribution subset of Phase 3, complete the exactly-once reward core in Phase 4, and then advance the native-invasion subset of Phase 7. Unrelated observation families, zones, independent character spawning, modifiers, and instance control can continue afterward or in parallel without blocking the first siege.

The initial slice contains:

1. public warnings and standings plus private score queries;
2. player, guild, and home-base identity snapshots plus active-owned-Pal attribution;
3. accepted-damage, final-hit, capture, and invasion-lifecycle observation;
4. one bounded, noncapturable stock-composition ranked base siege before all-base scale;
5. one bounty-member substitution profile after stock siege proof, initially completion-only unless capture normalization and the full reward economy pass;
6. participation and first/second/third reward obligations through the durable ledger;
7. a one-home-base target-budgeted contribution leaderboard, separate base/guild outcomes, and final hits recorded as a secondary statistic and tie-breaker;
8. restart, vanilla-client, native-drop, cleanup, and server-health validation.

This path does not weaken any phase gate. It narrows which capabilities are built first.

## Parallel workstreams

1. **Core runtime** — lifecycle, state, scheduler, event machine, jobs, claims, recovery.
2. **Engine adapters** — observation/action capabilities by exact revision.
3. **Definition tooling** — schema, validator, simulator, preview, template library.
4. **Vanilla UX** — messages, commands, signboards, localization strategy.
5. **Safety/QA** — disposable server, test clients, failure injection, soak, evidence.
6. **Operations** — package, backups, deployment, rollback, metrics, update response.
7. **Optional sidecar** — calendar UI, Discord/web, REST health, archival reporting.

## Phase 0 — Repository and capability laboratory

### Deliverables

- Design documents and source hierarchy.
- Repository conventions, license decision, contribution/security policy.
- Reproducible development-server notes with no secrets.
- Current game/runtime fingerprint recorder.
- UE4SS discovery workflow: fresh logs, headers/types, Live View, object paths.
- Capability evidence report template.
- Disposable-world backup/restore workflow.
- Clean vanilla-client test installation.

### Exit criteria

- Untouched runtime loads on an isolated Windows PalServer.
- Exactly one UE4SS installation is proven.
- A clean vanilla client connects before any gameplay hook is added.
- Backup restoration is rehearsed.
- No private host credentials or copyrighted game dumps enter the repository.

## Phase 1 — Generic orchestration core

### Deliverables

- Minimal idempotent bootstrap and authoritative world-ready lifecycle.
- Monotonic clock abstraction and wall-clock scheduler.
- Event state machine with durable transitions.
- Atomic snapshot and append-only journal.
- Structured logging and health registry.
- Bounded game-thread job queue.
- Capability registry and global/per-adapter kill switches.
- Definition parser, schema v1, normalization, and validator.
- Pure simulation harness with deterministic clock/random seed.

### Initial synthetic templates

- Announcement-only schedule.
- Simulated global counter.
- Simulated registration/race/leaderboard.
- Simulated reward obligations without game grants.

### Exit criteria

- Restart simulation at every journal boundary converges deterministically.
- Invalid definitions cannot invoke code or arbitrary paths.
- No hook or timer multiplies after world reload/hot reload tests.
- Core runs with all gameplay adapters disabled.

## Phase 2 — Read-only server events and vanilla UX

### Adapters

- Public notice and system chat.
- Private system chat.
- Chat command intake and rate limiting.
- Player roster/join/leave.
- Player UID/name/platform alias resolution.
- Game time reads and transitions.
- Basic player/guild/base lookup.
- Current server health/frame metrics.

### Templates

- Daily Dispatch.
- Event Ballot.
- Trivia and Guess the Pal.
- Attendance/returner tracking without rewards.
- Community meter driven by commands/test signals.

### Exit criteria

- Clean Steam and first cross-play client see correct messages and commands.
- Join/reconnect in every phase works.
- Chat cannot inject formatting, paths, adapters, or unbounded output.
- Maximum-player synthetic command load stays within budget.

## Phase 3 — Objective observations

Add adapters one signal family at a time:

1. accepted-damage, death/final-hit, and player/owned-Pal attribution;
2. capture attribution;
3. player records and monotonic counter reconciliation;
4. item gathering/pickup classification;
5. craft/build/work completion;
6. fishing results;
7. stage, dungeon, boss, raid, oil-rig, arena, relic, and discovery observations.

### Templates

- Pal of the Day, diversity safari, capture bingo.
- Boss Passport and Alpha Circuit.
- Gathering/crafting community drives.
- Fishing Derby.
- Normal-play Dungeon Sprint and Oil Rig Assault.

### Exit criteria

- Every normalized signal has documented deduplication and attribution.
- Reward/admin actions are excluded from objective feedback loops.
- Record reconciliation detects missed hooks without inventing details.
- High-volume activities do not perform broad per-frame scans.

## Phase 4 — Reward and progression service

### Deliverables

- Existing-item allowlist for exact revision.
- Item grant adapter with stack/full-inventory behavior.
- XP adapter.
- Pending online delivery and login retry.
- Exactly-once reward ledger and operator review state.
- Reward tables, caps, tiers, deterministic raffle, pity, and audit.
- Technology/status/relic-point spikes, enabled separately only after persistence proof.

### Templates

- Daily Login Gift.
- Weekly Challenge Track.
- Raffle Night.
- Personal Daily Commission.
- Newcomer, returner, mentor, and catch-up contracts.
- Simulated Siege League participation and three-place podium settlement before a live invasion adapter exists.

### Exit criteria

- Fault injection around every grant boundary cannot duplicate a reward.
- Full inventory never silently loses high-value rewards.
- Save/restart/reconnect/removal outcomes are documented.
- Invalid IDs fail before the game call.

## Phase 5 — Position, zones, routes, and signboards

### Deliverables

- Bounded authoritative position sampler.
- Circle/box/sphere/checkpoint zones with hysteresis.
- Ordered routes, attempt timers, travel invalidation, coarse clues.
- Staff-placed signboard registry and text leases.
- Optional safe teleport adapter with consent, floor validation, cooldown, and recovery origin.

### Templates

- Palpagos Grand Tour.
- Checkpoint Race and Guild Relay.
- Landmark Scavenger Hunt and Signpost Trail.
- Hide and Seek, Hot Potato, Tag.
- King of the Hill without forced PvP initially.

### Exit criteria

- Mount/glider/fast-travel/stage/death/reconnect cases are understood.
- Position anomalies trigger review, never automatic punishment.
- Sign text restores and cannot affect an unregistered sign.
- Teleport failure always leaves a recoverable player state.

## Phase 6 — Existing-character spawning

### Deliverables

- Revision-generated Pal/NPC spawn allowlist.
- Valid initialized character parameter builder.
- Network-aware spawn adapter.
- Spawn profiles and discrete difficulty bands.
- Ownership registry, callbacks, reconciliation, expiry, and despawn.
- Captured/dead/unloaded/orphaned state handling.
- Global/event/wave/zone/player spawn budgets and health shedding.

### Templates

- Directed Outbreak.
- Lucky Hunt outbreak.
- Bounded champion encounter.
- Simple two- or three-wave defense in a neutral zone.

### Exit criteria

- Vanilla clients observe spawn, combat, death, capture, travel, and reconnect correctly.
- Captured Pals are never removed as owned event actors.
- Restart with live event actors reconciles safely.
- Soak proves entity and game-thread limits.

## Phase 7 — Native incidents and invasions

### Adapters

- Meteor/supply start, state, and completion.
- Invader declaration, selected-base start, all-base start, exact stock-group selection, waves, end, and timeout.
- Forced-assault mode using the validated declaration-skip path; no Event Director consent gate.
- Pre-spawn native member substitution for allowlisted existing bounty `BOSS_*` character IDs.
- Allowlisted general incident request/stop only where ownership is provable.

### Templates

- Meteor Chase and Supply Drop Scramble.
- Meteor Safari.
- Mandatory Base Siege, All-Base Alarm, and Base Defense League.
- Bounty Siege, Most Wanted March, and Kingpin Siege.
- Siege League with individual contribution standings, final-hit side statistics, base/guild outcomes, and exactly-once participation/podium rewards.
- Night of Falling Stars at low initial scale.
- Meteor-to-Siege compound event after independent soak.

### Exit criteria

- No event can stop or clean a naturally occurring incident by mistake.
- Every registered base receives an attempted outcome in all-base mode; native technical failures are classified and reported.
- Exact group-name scope and declaration/Negotiator bypass are proven rather than inferred from reflected names.
- Bounty death/capture/butcher drops, wave completion, vanilla clients, and overworld-bounty independence are proven.
- Target-budgeted damage standings reconcile against native combat events; final-hit and capture resolution cannot duplicate target scoring.
- Direct-player and active-owned-Pal contributions roll up correctly while preserving separate source telemetry.
- Personal participation, per-successful-base completion, first, second, and third rewards settle exactly once without replacing native invasion rewards or bounty drops.
- Concurrency locks and server-health stops work.
- Restart and world-partition cases converge.

## Phase 8 — Modifier leases

Enable one adapter per tested setting or status; do not add an arbitrary property editor.

### Candidate sequence

1. time set/fixed progression;
2. experience rate;
3. collection/drop rate;
4. capture rate;
5. deterioration;
6. incubation/breeding;
7. selected damage/healing/revive settings;
8. fast-travel policy only if client behavior is acceptable.

### Templates

- Happy Hour.
- Abundance Weekend.
- Endless Night/Longest Day.
- Capture Frenzy.
- Decay Holiday.
- Breeder's Moon.

### Exit criteria

- Baseline is captured, composed, applied, verified, reverted, and crash-recovered.
- External operator changes produce a safe conflict, not a blind overwrite.
- Client UI/prediction mismatch is absent or explicitly harmless.
- Overlapping leases obey documented deterministic policy.

## Phase 9 — Advanced native instance integration

Observation precedes control for every subsystem.

### Candidate order

1. normal boss/tower attempts;
2. dungeon entry/boss/exit;
3. fishing detailed results;
4. oil-rig clear/crate;
5. normal raid boss start/finish;
6. solo arena results;
7. native arena room lifecycle;
8. directed boss/raid entry only if complete native context is proven.

### Templates

- Tower Time Trial.
- Dungeon Decathlon.
- Oil Rig Assault.
- Raid Boss Weekend.
- Arena Solo Ladder.
- Arena Bracket only at the final gate.

### Exit criteria

- Instance limits, entry/exit, reconnect, participant attribution, and native reward interaction are known.
- Director rewards cannot duplicate native rewards unexpectedly.
- Forced lifecycle operations have deterministic safe exits.

## Phase 10 — Campaigns, seasons, and adaptive director

### Deliverables

- Campaign dependency graph and global/guild/personal tracks.
- Guild roster snapshot/transfer policies.
- Historical rankings, Hall of Fame, and archive compaction.
- Adapter-aware event ballot.
- Adaptive selection policy based on population, progression, recency, health, and cooldown.
- Discrete tested scaling profiles.
- Compound event graph with fallback branches.

### Templates

- Festival Week.
- Guild Expedition League.
- Island Restoration Project.
- Story Choice Night.
- Expedition/Mercy/Guild season variants.
- Adaptive Crisis Director.
- Server Versus Director after spawn/health maturity.

### Exit criteria

- Selection is deterministic and auditable.
- Unavailable adapters are removed before choice, not failed after selection.
- Guild changes and season rollback cannot duplicate or transfer rewards incorrectly.
- Campaign state survives long downtime and package upgrades.

## Phase 11 — Optional sidecar and authoring experience

### Deliverables

- Authenticated atomic inbox/outbox protocol.
- Calendar/template editor with schema validation and simulation preview.
- Sanitized status/leaderboard web view.
- Discord notifications and operator actions with strict allowlist.
- REST-based health, save, announce, and graceful restart integration over loopback/LAN.
- Export/import of data-only community templates.

### Exit criteria

- Core events continue when sidecar is stopped.
- Replayed/forged/stale requests are rejected.
- No API or secret is Internet-exposed or committed.
- Imported templates cannot execute code or expand global policy ceilings.

## Phase 12 — Release and long-term maintenance

### Deliverables

- Official package metadata and dependency graph.
- Clean install/update/disable/removal automation.
- Compatibility report generator.
- Final vanilla/cross-play regression suite.
- Performance dashboards and alert thresholds.
- Backup/restore/downgrade rehearsals.
- Stable, beta, and laboratory release channels.
- Maintainer update playbook and support bundle.

### Exit criteria

- Exact release artifact is traceable to a pushed canonical source revision.
- All enabled templates and adapters have evidence and kill switches.
- Production-like soak covers one complete weekly schedule and at least one restart/failure per risk class.
- Operations can roll back without guessing which world/director state belongs together.

## Event-family release order

| Order | Family | Dependency |
|---:|---|---|
| 1 | Announcements, ballots, trivia, virtual goals | Core messaging/commands |
| 2 | Capture, boss, gathering, crafting observations | Normalized observation adapters |
| 3 | Login, commissions, raffles, rewards | Reward ledger |
| 4 | Routes, races, scavenger hunts, social zone games | Position/zone service |
| 5 | Outbreaks and bounded combat waves | Spawn ownership |
| 6 | Meteor, mandatory all-base, and bounty invasion events | Native incident adapters |
| 7 | Bonus weekends and time narratives | Modifier leases |
| 8 | Dungeon/oil-rig/raid/arena competitions | Instance integrations |
| 9 | Festivals, campaigns, adaptive director | Mature composition/history |

## Required epics

- EPIC-CORE: lifecycle, scheduler, state machine, persistence, jobs.
- EPIC-DEFINITIONS: schema, validator, simulator, preview.
- EPIC-BRIDGE: revision fingerprint and adapter registry.
- EPIC-MESSAGING: notices, chat, commands, signs.
- EPIC-IDENTITY: players, guilds, reconnect, eligibility.
- EPIC-OBSERVATION: capture, kill, item, craft, build, records, instances.
- EPIC-REWARDS: allowlists, ledger, delivery, review.
- EPIC-ZONES: positions, routes, attempts, teleport.
- EPIC-SPAWNS: parameter builder, network spawn, ownership, cleanup.
- EPIC-INCIDENTS: supply, meteor, invasion, general incidents.
- EPIC-MODIFIERS: leases, composition, recovery, per-setting adapters.
- EPIC-INSTANCES: boss, dungeon, raid, arena, oil rig, fishing.
- EPIC-CAMPAIGNS: seasons, history, guild rules, adaptive policy.
- EPIC-SIDECAR: IPC, authoring UI, external integrations.
- EPIC-QAOPS: lab, test matrix, packaging, backup, deployment, update response.

Each adapter or event template should be a small issue under these epics with explicit evidence and acceptance links.

## Priority rubric

Score proposed work on:

- player value and event reuse;
- vanilla-client confidence;
- save/persistence risk;
- cleanup certainty;
- game-thread/performance cost;
- update maintenance cost;
- observability/testability;
- whether another primitive already provides most of the experience.

High-value reusable primitives beat bespoke spectacles. A single reliable capture signal enables dozens of events; one fragile custom boss sequence enables one.

## Deferred until evidence improves

- General dynamic build-object spawning.
- Arbitrary client RPC/VFX invocation.
- Movement/physics rewrites.
- Automatic inventory removal or escrow.
- Forced raid/arena flows that bypass native prerequisites.
- Any custom data identity or player-visible cooked asset.
- Live save-file editing.

## Documentation deliverables per release

Every release updates:

- supported Palworld/UE4SS revision matrix;
- capability evidence table;
- enabled template catalog;
- known client/UI discrepancies;
- save impact and removal behavior;
- package hashes and source revision;
- upgrade/rollback notes;
- current unresolved spikes.

The roadmap is intentionally larger than an initial prototype. Early phases establish the invariants that allow later creativity to run unattended without sacrificing the world or vanilla players.
