# Pal Event Director

Pal Event Director is a planned event platform for a Palworld dedicated server. It will run on the server while every player connects with an unmodified Palworld client, including cross-play clients that cannot install mods.

> **Project state:** design and capability-research phase. This repository does not yet contain a runnable mod.

> **Flagship focus:** Siege League—native mandatory invasions, player-plus-active-Pal contribution standings, participation rewards, and first/second/third podium rewards. The broader event catalog remains planned.

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
- Mandatory scheduled invasions that can target every registered base without an Event Director consent layer, including experimental all-base bounty-target sieges with native per-base or explicitly configured level policies.
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
