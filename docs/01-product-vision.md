# Product vision

## Mission

Create a dependable event director that makes a persistent Palworld server feel alive every day without asking players to install anything. The system should support small automatic bonuses, structured competitions, cooperative campaigns, spectacular world incidents, and long-running seasons while preserving vanilla-client connectivity and recoverability.

## Problem

Vanilla dedicated servers provide world settings and basic administration but little event orchestration. Operators can announce messages and manually change a few settings, yet a recurring event usually requires staff presence, ad hoc commands, manual scorekeeping, and risky cleanup. Players on console or other locked-down platforms cannot participate in events that depend on client mods.

Pal Event Director fills that gap by orchestrating existing Palworld systems from the authoritative server.

## Product goals

1. **Zero-friction participation** — unmodified Steam, Xbox, PlayStation, and Mac clients can connect normally, subject only to Palworld's own cross-play support.
2. **Broad event vocabulary** — combine schedules, player actions, world incidents, scoring, rewards, messages, zones, and temporary modifiers.
3. **Safe unattended operation** — recurring events survive restarts, missed schedule boundaries, empty servers, and partial failures.
4. **Operator control** — preview, start, pause, resume, abort, resolve, and inspect events without editing live code.
5. **Evidence-based compatibility** — every engine adapter has a tested game revision, evidence level, health probe, and kill switch.
6. **Reversible effects** — temporary settings, spawned actors, registrations, and pending rewards have explicit cleanup behavior.
7. **Fairness and transparency** — deterministic scoring, auditable rewards, anti-duplication, configurable eligibility, and clear tie rules.
8. **Maintainability after updates** — game-specific paths are isolated from generic event logic.
9. **Creative range** — support quiet community goals and ambitious world spectacles through the same primitives.
10. **No secret-bearing artifacts** — packages, logs, and repositories never contain server administration credentials.

## Hard constraints

- The production target is Palworld's Windows dedicated-server edition.
- Only the server runs Pal Event Director and its runtime dependency.
- Players use vanilla clients.
- The mod uses only existing client-known content and native replication paths.
- No event is accepted merely because it works in single-player, on a listen host, or in the server console.
- Runtime code must obey Unreal game-thread and object-lifetime rules.
- Palworld and UE4SS updates are compatibility events requiring revalidation.
- Save corruption is a first-class risk; disposable worlds and backups are mandatory.

## Design principles

### Existing content, new choreography

The creative opportunity is not inventing assets. It is recombining Palworld's existing systems: a meteor starts a race, its impact begins a capture hunt, captured targets advance a guild objective, and completion opens a boss wave with vanilla rewards.

### World events do not imply consent

Scheduled base invasions are world rules, like Palworld's ordinary raids. Pal Event Director does not add a registration or consent gate before attacking a base. An all-base event attempts every base known to the native invasion manager; native pathfinding, loading, cooldown, or state failures are technical outcomes rather than player choices. Consent remains available where an event directly takes control of an individual player, but it is not a prerequisite for server-wide invasion events.

### Capabilities, not one-off scripts

An event is composed from versioned adapters such as `announce`, `observe_capture`, `spawn_character`, `start_invasion`, `grant_item`, or `watch_zone`. Each adapter owns validation, authority checks, rate limits, logging, and cleanup.

### Fail closed and degrade gracefully

If reward delivery fails, the score remains and a durable pending grant is retried. If spawning is disabled, a compound event can fall back to a gathering objective. If cleanup cannot be proven, the event cannot start.

### State outside the world save

The director stores its calendar, progress, reward ledger, and recovery journal in mod-owned files. It reads game state and invokes validated game behavior, but it does not patch save files while the server is running.

### The exact artifact is the product

Development folders do not establish compatibility. Each release is tested through the official server package layout with only declared dependencies.

## Users and roles

| Role | Needs |
|---|---|
| Player | Clear event information, effortless opt-in, fair scoring, reliable rewards, no downloads. |
| Event host | Manual controls, participant tools, announcements, overrides, and diagnostics. |
| Server operator | Safe deployment, health checks, backups, kill switches, logs, and rollback. |
| Event designer | Declarative templates, validation, simulation, composable objectives, and documented limits. |
| Maintainer | Version-isolated engine adapters, reproducible tests, fixture logs, and compatibility reports. |

## Product modes

### Calendar mode

Daily, weekly, monthly, anniversary, and seasonal schedules. Rules define timezone, recurrence, announcement windows, overlap policy, downtime behavior, and catch-up behavior.

### Live host mode

An authorized host starts a template, chooses parameters, admits participants, advances stages, applies rulings, or aborts safely.

### Campaign mode

Multiple events contribute to a persistent server or guild objective over days or weeks. Campaigns can unlock later stages, cosmetic recognition through text, or increasingly difficult vanilla encounters.

### Adaptive director mode

The system chooses from an approved pool using online count, median progression, recent event history, server frame time, time of day, and cooldowns. It may scale counts and levels only inside prevalidated bounds.

### Community-choice mode

Players vote through rate-limited chat. The server resolves a deterministic ballot and starts one of several compatible templates.

## Functional scope

### Scheduling and orchestration

- Wall-clock and game-clock schedules.
- Recurrence, exceptions, blackout windows, cooldowns, and dependencies.
- Pre-announcement, registration, warm-up, active, grace, resolution, reward, cleanup, and archive phases.
- Parallel events when resource claims do not conflict.
- Recovery from restart at every phase.

### Observation

Potential signals include player join/leave, chat, capture, death, kill, inventory change, item pickup, gathering, work completion, crafting, building, fishing, base lifecycle, stage entry, dungeon boss state, raid start/finish, oil-rig crate opening, arena state, world time, and zone occupancy. Each signal is enabled independently only after validation.

### Actions

Potential actions include vanilla announcements, private system chat, sign text updates, existing item/XP/point grants, healing, teleportation, time changes, temporary server-authoritative modifiers, existing character spawning, meteor/supply incidents, invader marches, native incidents, boss/arena entry, and safe cleanup.

### Scoring and rewards

- Individual, party-like team, guild, cooperative global, and staff-judged scoring.
- Counters, distinct sets, fastest time, streaks, weighted points, races, survival, quotas, brackets, and compound stages.
- Participation and winner rewards, caps, cooldowns, rank bands, pity rules, and exactly-once delivery.
- Offline pending rewards where identity and delivery APIs are proven safe.

### Presentation

- Server announcements.
- Private and global system chat.
- Chat commands.
- Staff-placed vanilla signboards.
- Optional external web/Discord display through a local sidecar.

## Non-goals

- A custom in-game event UI.
- Custom items, recipes, technologies, Pals, buildings, maps, markers, meshes, animations, audio, or effects.
- Client-side prediction changes such as arbitrary movement physics.
- Replacing Palworld's networking or matchmaking.
- Editing player or world save files during runtime.
- Guaranteeing that every reflected function is callable.
- Automatically enabling a new Palworld revision in production.
- Monetization, pay-to-win rewards, or platform-policy circumvention.

## Success criteria

### Compatibility

- A clean Steam client and at least one locked-down cross-play client complete representative events without local files.
- Clients reconnect during and after events without desync, missing-class errors, or mod-list requirements.
- The server accepts vanilla clients with client mods disallowed.

### Reliability

- A restart in every event phase produces one deterministic outcome.
- Rewards are never duplicated and are not silently lost.
- Temporary mutations revert after normal completion, abort, crash recovery, and package disable tests.
- Spawned event actors are capped, attributable, and cleaned or handed to normal game lifecycle explicitly.

### Performance

- No unbounded per-frame scans.
- Event work is budgeted and observable.
- A maximum-player soak test remains within agreed server frame-time and memory budgets.
- Expensive adapters shed optional work before affecting gameplay.

### Operability

- Operators can identify the active event, current phase, claimed resources, participants, pending rewards, and last error from logs and commands.
- Every event template has dry-run validation and a documented abort path.
- Every release names its tested Palworld revision and UE4SS build.

## Definition of the complete platform

The project reaches its full intended scope when it has:

1. A stable generic orchestration core and persistent journal.
2. A validated adapter library spanning messaging, participants, scoring, rewards, time, positions/zones, existing-character spawning, incidents/invasions/supply events, signboards, and selected instance systems.
3. A declarative format with schema validation and simulation.
4. A substantial built-in template library across all catalog families.
5. Conflict-safe modifier and world-resource leasing.
6. Vanilla-client, cross-play, restart, update, and removal test suites.
7. Operator commands, audit logs, metrics, backup-aware deployment, and rollback documentation.
8. Optional but isolated external calendar/dashboard integration.
9. Published evidence for every compatibility claim.

Completeness does not require every experimental concept to ship. It requires that rejected concepts remain rejected and experimental adapters cannot bypass the safety gates.
