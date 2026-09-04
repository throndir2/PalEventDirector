# Vanilla-client contract

## Purpose

This document defines what “server-only” and “vanilla-friendly” mean for Pal Event Director. It is an architectural contract, not a marketing label.

A package rule containing `IsServer: true` tells Palworld where to deploy files. It does **not** prove that an unmodified client can understand the resulting game state. This project makes that stronger claim only after the tests below pass.

## Required player state

A supported player has:

- an unmodified Palworld installation;
- no UE4SS runtime;
- no Pal Event Director files;
- no PalSchema dependency;
- no matching pak or LogicMod;
- no Workshop subscription for this project;
- no external companion application.

The client may be Steam, Xbox, PlayStation, or Mac when that platform is supported by the server's normal cross-play configuration. Platform coverage must be listed per release rather than implied.

## Compatibility invariant

For every value or object that crosses the network, the vanilla client must already know:

1. its Unreal class and serialization layout;
2. every referenced asset path;
3. every data-table row, enum, item ID, Pal ID, effect, animation, and text identity it must resolve;
4. the RPC/property replication behavior used to receive it;
5. the UI path, if any, used to display it.

If any one of these is newly authored by the mod, that feature violates the contract unless it remains wholly server-local and can never be referenced by replicated state.

## Mandatory world-event rule

Vanilla-client compatibility is not a consent model. Scheduled native base invasions may target every available idle base belonging to a guild represented online at the start boundary without registration, guild approval, or a client prompt. Offline-only guilds are excluded by server policy. A native inability to create or route an eligible incident is recorded as a technical failure; it is not interpreted as refusal.

Where a forced invasion profile must bypass Palworld 1.0's Negotiator/cancellation phase, the director uses only a validated native declaration-skip path. This policy does not authorize arbitrary destructive calls or cleanup against actors the director cannot identify.

## Allowed interaction surface

### Strong candidates

- Existing `APalGameStateInGame` server notices and chat messages.
- Private system chat to existing player UIDs.
- Existing signboard text on a staff-placed vanilla sign.
- Existing items added through validated server inventory operations.
- Existing experience and point systems.
- Existing Pals/NPCs spawned through the game's network-aware character path.
- Existing meteor, supply, invasion, incident, boss, dungeon, raid, arena, fishing, and oil-rig systems when invoked through their complete native context.
- Existing player, guild, base, inventory, time, stage, and record data used for observation.
- Server-authoritative time and world settings that vanilla clients already consume correctly.
- Existing teleportation, healing, death, and status paths where authority and prediction are validated.

### Conditional candidates

These are allowed only when a specific adapter passes mismatched-client testing:

- Runtime changes to game-setting objects.
- Changes whose server effect is authoritative but whose client UI retains a baseline value.
- Reusing existing visual effects outside their original gameplay path.
- Existing map markers or warning types invoked in a new sequence.
- Actor scale, movement, collision, stamina, damage, or input changes with client prediction.
- PalSchema modifications to existing rows or Blueprint defaults.
- Non-replicated server-only LogicMod actors.

A visible-but-inaccurate vanilla UI is a compatibility defect unless explicitly harmless, temporary, and approved for that adapter.

## Prohibited interaction surface

The following are rejected for the core project:

- New item, Pal, NPC, recipe, technology, building, spawn-row, enum, quest, or localization identities.
- Custom replicated actors, components, RPCs, structs, properties, or Blueprint classes.
- New or replaced models, textures, icons, animations, sounds, voice lines, effects, maps, levels, dungeons, or widgets.
- Client-side hooks, scripts, keybinds, input handlers, HUDs, menus, scoreboards, notifications, or prediction changes.
- Server state that requires a client pak to deserialize or render safely.
- Repurposing a vanilla ID in a way that causes permanent ambiguous save data.
- Telling players to enable client mods as a workaround.

## Server configuration implications

Palworld documents `bAllowClientMod` as allowing players with mods enabled to join. Pal Event Director does not depend on that setting because players are not modded. Vanilla-client acceptance testing should include `bAllowClientMod=False` to catch accidental client dependencies.

Server package loading is controlled separately through the official mod loader, its global enable flag, `ActiveModList`, package dependencies, and an `IsServer: true` install rule.

## Capability acceptance gate

A new adapter advances through these states:

1. **Discovered** — a current reflected class, property, delegate, or function suggests the capability.
2. **Observed** — an observation-only hook records real calls, parameters, frequency, thread context, and lifecycle.
3. **Invoked in isolation** — the smallest mutation runs on a disposable local server world.
4. **Authority proven** — execution occurs only on the authoritative server and does not duplicate per player.
5. **Vanilla Steam proven** — a clean Steam client observes the intended result and reconnects successfully.
6. **Cross-play proven** — at least one console/locked-down client completes the representative journey when that release claims cross-play.
7. **Persistence proven** — save, restart, reconnect, expiry, disable, and uninstall outcomes are understood.
8. **Cleanup proven** — normal completion, operator abort, script failure, and server crash all converge safely.
9. **Soak proven** — bounded use under representative player/entity load does not degrade the server beyond budget.
10. **Released** — the adapter records exact game/runtime revisions and defaults to disabled outside that compatibility envelope.

Skipping a stage requires a written exception and cannot be used for production-enabled experimental adapters.

## Mandatory mismatched-client journeys

Every player-visible adapter must test:

- Vanilla client joins a modded server before the event starts.
- Vanilla client is online when the event begins.
- Vanilla client joins during registration, active play, resolution, and cleanup.
- Client disconnects and reconnects while participating.
- Client changes area, enters an instance, dies, respawns, and fast travels where relevant.
- Server restarts during every event phase.
- Event ends while no players are online.
- Mod is disabled after cleanup and the world loads without it.
- A copied world loads with `-NoMods` for emergency isolation.

## Network rules

1. Never infer replication from `BlueprintReadWrite` alone; require `Replicated`, an RPC, or observed native replication.
2. Never spawn an actor with a server-local generic spawn call when Palworld provides a network-aware manager/transmitter path.
3. Never invoke a `Server` RPC from an arbitrary object without proving ownership and call context.
4. Never send a custom class or unknown object reference to a client.
5. Never rely on a client-only callback such as `ClientRestart` for dedicated-server initialization.
6. Treat each player's controller/transmitter as ephemeral across travel and reconnect.
7. Validate object ownership, world, authority, and lifetime immediately before use on the game thread.
8. Rate-limit reliable multicast and private-client messages.

## Data identity rules

- Reward and spawn IDs come from an allowlist generated for the tested game revision.
- Unknown IDs fail before calling the game.
- Event definitions cannot specify arbitrary class or asset paths in production.
- Built-in IDs that are debug-only, cutscene-only, non-capturable, or unsafe are excluded.
- No event writes a custom identifier into Palworld's own persistent structures.
- Project-specific IDs live only in the director's external state.

## Presentation rules

### Approved

- Concise server notices.
- Public system chat where all players need the information.
- Private system chat for help, score, errors, and rewards.
- Existing signboards placed through normal gameplay or by staff.
- Existing native warning/marker UI only when invoked through the native system and cross-play tested.
- Optional external web or Discord views that are not needed to participate.

### Not approved

- A custom HUD or widget.
- Raw UE4SS console output as player communication.
- Chat spam used as an ersatz per-frame scoreboard.
- Control characters, rich-text injection, or unbounded player-derived strings in announcements.

## Degraded modes

An event may declare a safe fallback. Examples:

- If character spawning is unavailable, a capture outbreak becomes a naturally spawned species hunt.
- If private chat fails, `!score` returns a short public response with sensitive fields omitted.
- If the sign adapter is unhealthy, announcements continue and sign updates are skipped.
- If a modifier cannot acquire its lease, the event starts without that bonus only when the template declares it optional.

A fallback may reduce spectacle; it may never weaken the vanilla-client invariant.

## Evidence record

Each released adapter must record:

- Palworld display revision and server executable identity;
- UE4SS package/build identity;
- relevant reflected object paths and signatures;
- test world type and save-impact class;
- client platforms tested;
- concurrency and soak conditions;
- known visual discrepancies;
- cleanup and removal result;
- log or test-report reference.

## Release claim wording

Acceptable:

> Server-only on Windows dedicated servers. Tested with unmodified Steam and Xbox clients on Palworld revision X. No client files required.

Not acceptable:

> `IsServer` is present, therefore every client is supported.

The second statement confuses package deployment with multiplayer compatibility and is prohibited in project documentation.
