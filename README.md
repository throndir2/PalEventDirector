# Pal Event Director

> **Direct laboratory testing.** IMOUTO's `575a9f52` build crashed inside native preflight. The `laboratory-native-test` profile enables in-game chat and invasion commands without a manual preflight prerequisite. Normal start validation and dispatch write flushed native-operation breadcrumbs automatically. The oversized `GetOptionWorldSettings` getter is prohibited; the adapter reads the invasion flag through the world-scoped option subsystem instead. Recurring schedules, item delivery, and native-all comparison remain disabled. Follow [the test runbook](docs/15-preflight-crash-diagnostics.md), not the historical quick start below.

Pal Event Director is a server-only event platform for a Palworld dedicated server. It runs on the server while every player connects with an unmodified Palworld client, including cross-play clients that cannot install mods.

> **Project state:** runnable `0.1.0-alpha.3` laboratory build. It adds daily/weekly local-time schedules, durable 10/5/1-minute scheduled notices, 0–60-minute manual starts, online-guild-only base targeting, a global start/late-join roster, operator/chat controls, and audited bounty profiles. All gameplay observation, invasion starts, bounty substitution, chat hooks, schedules, and live item delivery are disabled by default until the disposable-world gates pass.

`Info.json` intentionally leaves `MinRevision` at `0` for this unpublished laboratory package because the installed executable does not expose the official five-digit title revision in file metadata. Record that revision in-game and set it before any published release.

> **Flagship focus:** Siege League—native mandatory invasions, player-plus-active-Pal contribution standings, participation rewards, and first/second/third podium rewards. The broader event catalog remains planned.

## Historical alpha gameplay quick start (quarantined)

Prerequisite: one Palworld-compatible `UE4SS` package managed by Pocketpair's official loader. Do not install a second runtime.

1. Run `npm install`, `npm run check`, and `npm run build` in this repository.
2. Extract the generated archive from `dist/` into one folder under the server's `Mods/Workshop/`; `Info.json` must be directly inside that folder.
3. Set `bGlobalEnableMod=true`, then add `ActiveModList=UE4SS` and `ActiveModList=PalEventDirector` under `[PalModSettings]` while preserving the server's existing mod entries.
4. Restart only a disposable laboratory server/world first.
5. The first boot creates persistent `Pal/Saved/PalEventDirector/config.json` with all adapter/mutation switches off.
6. Enable `diagnostics.observationProbe` and one observation capability at a time, restart, and complete the checklist in [the alpha laboratory runbook](docs/12-alpha-laboratory-runbook.md). Use `traceHooks` only for short focused troubleshooting.
7. Enable `startAllInvasions` and `substituteBountyMembers` only after observation and substitution probes pass. Live `grantItems` is intentionally rejected in this build; rewards remain durable pending obligations until the next persistence gate is implemented.

Development, validation, packaging, and deployment now run locally on IMOUTO from the workspace checkout, not the old MIKO-hosted network share. From approved, clean, pushed source, run `npm run build` and `npm run build:imouto`, then use the generated bundle's installer. Its target is `D:\SteamLibrary\steamapps\common\PalServer`; it backs up repeat deployments and never touches MIKO Production or the sibling Palworld client. The disposable world is already imported: do not rerun its importer. See [the IMOUTO deployment runbook](docs/14-imouto-dev-deployment.md).

The installer configures `PalEventDirectorDeployments\Enable-PalEventDirectorLaboratory.ps1` and `Start-PalEventDirectorImouto.ps1`. With the server stopped, confirm the activation command once to enable chat/combat/invasion/bounty capabilities, native-admin-or-operator authorization, and compatibility pins while keeping rewards and schedules disabled. Then start IMOUTO with the generated launcher, not Steam Play: it reads the verified build ID from the local dedicated-server manifest and supplies both PED environment variables only to the child server process. Run it with `-ValidateOnly` to verify launch integration without starting Palworld.

The primary admin command is `!siege start all-bounty [0-60 minutes]`. At `0`, each requested target is submitted once without a countdown or first-probe acceptance prerequisite. Native visitor/incident occupancy and gameplay flags are observations, not PED admin vetoes; Palworld may reject or ignore the call. Positive countdown timing is still honored. Ordinary users and schedules retain their policy checks and confirmed-probe fanout. A returned native call is never displayed as `RAID STARTED` without a new matching lifecycle callback. No confirmed base means `START FAILED`, with no rankings or rewards. `chatStartPolicy=operatorOrPalworldAdmin` accepts configured operators or fresh server-side Palworld admin authority; `anyUser` does not confer admin overrides. See [the complete administration reference](docs/13-admin-and-scheduling.md) for commands, diagnostics and retained integrity checks.

Built-in profiles:

| Profile | Composition |
|---|---|
| `all-bounty` | Default. Attempts to replace every intercepted native selected member while rotating the audited 34-ID bounty catalog across all bases; spawned outcomes still require live proof. |
| `patrol` | All members use low-yield one- or two-token bounty targets. |
| `mixed` | One bounty captain with the remaining native escorts. |
| `most-wanted` | All members use two- through four-token targets. |
| `kingpin` | Every member becomes Ram, the five-token Dark Trader bounty. |
| `jackpot` | Every member uses a four- or five-token target. |
| `native` | No composition substitution; useful as the baseline control. |

The corresponding server-console forms are `ped start [profile] [minutes]`, `ped cancel`, `ped status`, `ped profiles`, `ped schedule`, `ped leaderboard`, `ped resolve`, `ped abort`, `ped reset`, the separately restored-world diagnostic `ped diagnose-native-all confirm-disposable-start-all`, and the currently blocked `ped rewards`.

## Non-negotiable contract

The server may change authoritative game state only through behavior and content already understood by a vanilla client. An event may use existing Pals, NPCs, items, incidents, locations, effects, messages, and replicated properties. It may not require a custom client class, asset, data identity, script, widget, or network protocol.

In practical terms:

- Server installation only.
- No client mod, loader, Workshop subscription, or manual file.
- No custom items, Pals, buildings, maps, models, sounds, UI, or replicated Blueprint classes.
- Built-in chat, announcements, signboards, actors, and normal replication are the player interface.
- Every capability is disabled until tested with a truly vanilla client.

See [the vanilla-client contract](docs/02-vanilla-client-contract.md) for the complete acceptance rules.

## Proposed platform

The core will be a server-only UE4SS Lua package for the Windows dedicated-server edition of Palworld. It will be packaged for Pocketpair's official mod loader with an explicit server install rule. The architecture is Lua-first because runtime hooks, timers, reflected objects, and direct calls to existing game functions are the capabilities an event director needs most.

The planned system includes:

- Wall-clock, game-time, recurring, manual, voted, and adaptive scheduling.
- Event state machines with announcements, registration, active play, resolution, rewards, and cleanup.
- Objectives based on joins, chat, captures, final hits, direct-versus-owned-Pal kills, damage contribution, gathering, crafting, building, fishing, travel, dungeons, bosses, raids, arenas, oil rigs, zones, and elapsed time where corresponding hooks prove reliable.
- Existing-item, experience, technology-point, status, and recognition rewards.
- Controlled spawning of existing Pals and NPCs, built-in incidents, invasions, meteorites, supply drops, and instance systems where safe adapters are validated.
- Mandatory scheduled invasions that target every available idle base belonging to a guild represented by at least one online member at the event boundary, including experimental bounty-target sieges with native per-base or explicitly configured level policies.
- Per-player, team, guild, cooperative, competitive, server-wide, and season-long scoring.
- Crash-safe state, exactly-once reward delivery, modifier leases, spawn cleanup, audit logs, and per-capability kill switches.
- Vanilla UX through announcements, private system chat, public chat, commands, and staff-placed signboards.
- An optional local sidecar for calendar authoring, Discord/web integrations, metrics, and file-based IPC. Core gameplay will not depend on Internet access.

## Design documents

Read these in order:

1. [Product vision](docs/01-product-vision.md) — goals, scope, principles, and success criteria.
2. [Vanilla-client contract](docs/02-vanilla-client-contract.md) — the compatibility boundary and mandatory gates.
3. [Engine capability map](docs/03-capability-map.md) — evidence-backed primitives, risks, and required spikes.
4. [Architecture](docs/04-architecture.md) — components, state machine, data flow, persistence, and recovery.
5. [Event definition format](docs/05-event-definition-format.md) — the proposed declarative event model.
6. [Event catalog](docs/06-event-catalog.md) — a broad catalog of feasible and experimental event concepts.
7. [Safety and testing](docs/07-safety-and-testing.md) — performance budgets, test matrix, security, and release gates.
8. [Roadmap](docs/08-roadmap.md) — the staged path from capability laboratory to complete platform.
9. [Operations](docs/09-operations.md) — packaging, configuration, deployment, rollback, and event administration.
10. [Research sources](docs/10-research-sources.md) — source hierarchy, findings, and unresolved questions.
11. [Mandatory invasions and bounty sieges](docs/11-invasion-and-bounty-design.md) — all-base targeting, exact invasion groups, bounty-token farming, and required proof.
12. [Alpha laboratory runbook](docs/12-alpha-laboratory-runbook.md) — implemented scope, fail-closed switches, installation, and staged live validation.
13. [Alpha.3 administration and scheduling](docs/13-admin-and-scheduling.md) — all chat/console commands, profiles, schedules, warnings, eligibility, and configuration fields.
14. [IMOUTO DEV deployment](docs/14-imouto-dev-deployment.md) — local clean builds, stopped-server deployment, dependency pins, rollback, and vanilla-client checks without touching MIKO Production.
15. [Preflight crash diagnostics](docs/15-preflight-crash-diagnostics.md) — guarded gameplay testing, the isolated diagnostic profile, pinned-source buffer audit, and one-operation procedure.

The installed test-profile preparation command enables chat and the event observation/substitution capabilities. Use `!siege status` and an authorized `!siege start native 0` or `!siege start all-bounty 0` directly. Standard authorization, version, world-setting, base-eligibility, and active-incident checks still apply automatically. A native Lua error or failed breadcrumb write stops further native starts until the server is restarted after investigation. The stepped diagnostic remains available for isolated troubleshooting, but is not required for gameplay.

For the current entry-point investigation, an admin can use `!siege test-native` while standing inside an eligible base. This explicitly tests one nearest base through the player-controller debug RPC, with a fixed stock Hunter group, no bounty substitution, and no fanout. It is not an all-base start or an unlock requirement. Private chat reports request validation, native-call return, and the observed result; a successful raid remains unproven until native lifecycle confirmation.

## Feasibility language

All plans use the same labels:

| Label | Meaning |
|---|---|
| **Confirmed** | Supported by current primary documentation and/or a current working server-only implementation, but still requires validation in this project. |
| **Probable** | A reflected, server-authoritative path exists and fits the vanilla boundary; a focused capability spike is required. |
| **Experimental** | Technically plausible but has substantial lifecycle, replication, save, AI, prediction, or cleanup risk. It ships only after isolated soak testing. |
| **Rejected** | Requires client content, creates an unknown replicated identity, cannot be cleaned up safely, or otherwise violates the project contract. |

“Confirmed” never means permanently compatible. Every Palworld revision can alter reflected paths, signatures, timing, and runtime-loader compatibility.

## Architectural decision summary

- **UE4SS Lua first:** fastest route to hooks and existing server functions.
- **No replicated custom content:** a LogicMod may eventually provide non-replicated server helpers, but never player-visible custom classes.
- **No direct save editing while live:** project state is kept separately and game state changes use validated game APIs.
- **Data-driven events:** definitions compose capabilities rather than embedding one-off logic.
- **Transactional cleanup:** temporary mutations are leases with a captured baseline and deterministic revert path.
- **Fail closed:** missing functions, stale objects, unknown versions, excessive load, or invalid configuration disable the affected capability or event.
- **Evidence over assumptions:** reflection exposes candidates, not safety guarantees.

## Target player experience

A player joins normally and sees no mod warning or download requirement. The server can announce:

- what is happening;
- how to opt in;
- current objective and score;
- time remaining;
- winners and rewards.

Typical commands will be ordinary chat messages such as `!event`, `!join`, `!score`, `!leaderboard`, and `!leave`. Commands must be rate-limited and may receive private system-chat responses so event traffic does not flood global chat.

## Out of scope

- Circumventing official-server rules or anti-cheat.
- Running the mod on official Pocketpair servers.
- Requiring or silently distributing client modifications.
- Permanent destructive world changes as event mechanics.
- Exposing Palworld's REST API directly to the Internet.
- Promising compatibility before mismatched-client and restart tests pass.

## Source date

The initial design research reflects Palworld and community documentation available through **2026-08-31**, including Palworld Server Guide 1.0.3, Palworld Modding Kit commit `e6632458`, UE4SS 4.0 documentation, PalSchema 0.6.0 documentation, the installed current server tables, and current server-mod examples. Refer to [research sources](docs/10-research-sources.md) before implementing against a later game revision.
