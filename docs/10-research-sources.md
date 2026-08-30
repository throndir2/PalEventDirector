# Research sources and open questions

## Research date and scope

Initial research was performed on **2026-08-30**. Palworld modding changes quickly; all implementation work must re-check primary sources and runtime dumps for the target revision.

Source priority:

1. Pocketpair documentation and repositories.
2. UE4SS maintainer documentation.
3. Current Palworld Modding Kit source/reflected headers.
4. PalSchema maintainer documentation.
5. Palworld Modding community documentation.
6. Current open-source or testable server mods as practical evidence.
7. Hosting guides and forum claims only as leads, never as compatibility proof.

## Pocketpair primary sources

### Official mod loader

- [Palworld Mod Loader — general](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/01-General.md)
- [Palworld mod package format](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/02-Package.md)
- [Palworld Mod Uploader](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/03-ModUploader.md)
- [Official loader technical details](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/04-Tech.md)
- [Installing mods on a server](https://docs.palworldgame.com/settings-and-operation/mod/)

Findings:

- The official loader supports Paks, Lua, LogicMods, UE4SS core, and PalSchema-dependent packages.
- Official server-side mod loading currently targets the Windows dedicated-server edition.
- A server payload needs an install rule with `IsServer: true`.
- The server activates package identities through `Mods/PalModSettings.ini` and restarts to deploy changes.
- `IsServer` controls deployment side; it does not state whether clients need matching content.
- Version comparison is string inequality, so every package update must change `Version`.
- `PackageName` is deployment/dependency identity and collisions are ambiguous.

### Dedicated-server operation

- [Configuration parameters](https://docs.palworldgame.com/settings-and-operation/configuration/)
- [Server commands](https://docs.palworldgame.com/settings-and-operation/commands/)
- [REST API index](https://docs.palworldgame.com/category/rest-api/)
- [REST API introduction/security warning](https://docs.palworldgame.com/api/rest-api/palwold-rest-api)
- [World actor snapshot endpoint](https://docs.palworldgame.com/api/rest-api/game-data)
- [Server metrics endpoint](https://docs.palworldgame.com/api/rest-api/metrics)

Findings:

- `bAllowClientMod` permits players with client mods; it is separate from server package activation.
- Official commands cover announcements, save, shutdown, player listing, kick/ban, teleport, and spectate, but not rich event gameplay.
- The REST API covers information, players, settings, announcements, moderation, save/stop, metrics, and an optional actor snapshot.
- Pocketpair explicitly warns not to expose the REST API directly to the Internet.
- Configuration includes many event-relevant server settings, but most apply at boot and each runtime mutation still needs validation.

### Policy

- [Palworld Mod Usage Guidelines](https://guideline.palworldgame.com/palworld-mod-guideline)

Findings:

- Mod use is at the operator/player's risk.
- Mods may cause bugs, crashes, save corruption, or lasting effects after disable.
- Backups and trusted sources are required.
- Mods are prohibited on official servers.
- Authors must respect third-party rights and distribution-platform terms.

## UE4SS primary sources

- [UE4SS Lua API](https://docs.ue4ss.com/dev/lua-api.html)
- [`RegisterHook`](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html)
- [`ExecuteInGameThread`](https://docs.ue4ss.com/dev/lua-api/global-functions/executeingamethread.html)
- [UE4SS installation guide](https://docs.ue4ss.com/installation-guide)

Findings:

- Lua can find reflected objects, read/write reflected properties, call UFunctions, register UFunction hooks, observe new objects, and schedule work.
- A function must exist in memory before `RegisterHook` can attach.
- Hook callbacks receive wrapped context/parameters and may have pre/post differences based on function path.
- UObject/game-state work belongs on the game thread.
- Async/delayed loops must not retain stale game objects.
- Current individual API pages are more authoritative than the older aggregate API list.

## Palworld Modding Kit and community docs

- [Palworld Modding Kit documentation](https://pwmodding.wiki/docs/category/palworld-modding-kit)
- [PMK prerequisites](https://pwmodding.wiki/docs/developers/palworld-modding-kit/prerequisites)
- [PMK Blueprint examples](https://pwmodding.wiki/docs/developers/palworld-modding-kit/bp-examples)
- [UE4SS Lua documentation](https://pwmodding.wiki/docs/category/lua-modding)
- [UE4SS function overview](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/ue4ss-functions)
- [Function-hooking tutorial](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/hooking-functions)
- [LogicMods introduction](https://pwmodding.wiki/docs/developers/ue4ss-modding/logic-mods/introduction)
- [Using Blueprints with Lua](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/blueprints-with-lua)
- [Current Palworld Modding Kit source](https://github.com/localcc/PalworldModdingKit)

Findings:

- PMK is an unofficial UE5.1 skeleton/API project, not Pocketpair's full SDK or game source.
- It can call exposed Palworld functions, modify values, and author Blueprint behavior/content.
- The documented toolchain includes UE5.1, .NET 6, Visual Studio 2022/MSVC 14.38, and Wwise 2021.1.11.
- Lua is better for quick runtime observation/hooks and cannot create new assets by itself.
- LogicMods provide a cooked `ModActor` but add toolchain/runtime/package complexity.
- Common client `ClientRestart` initialization is unsuitable for dedicated servers; current server-compatible lifecycle must be proven.
- Generated headers, Lua types, Live View, and FModel are discovery aids.
- PMK examples show base/guild access and replicated HP/stamina/shield changes.

### Current reflected systems inspected

The design reviewed current PMK headers for:

- `APalGameStateInGame` — replicated world state, reliable server notices and chat.
- `UPalUtility` — players, guilds, inventory, records, managers, messages, time, XP, teleport, status, capture/death helpers.
- `UPalTimeManager` — current game time, night/hour/minute delegates, fixed time, game-time timers.
- `UPalPlayerInventoryData` — existing-item server grant candidate.
- `UPalCharacterManager` and `APalNetworkTransmitter` — initialized, network-aware character spawning and handles.
- `UPalInvaderManager` and `UPalIncidentSystem` — native invasion and incident lifecycle.
- `UPalSupplyManager` — supply state and start/end observations.
- `UPalPlayerRecordData` — captures, bosses, crafting, dungeons, oil rigs, arena, fishing, treasure, discovery, relic, and stage records.
- `UPalBaseCampManager` — base lifecycle and lookup.
- `UPalMapObjectSignboardModel` — replicated sign text.
- boss, raid, dungeon, arena, fishing, work-progress, oil-rig, event-notify, and randomizer managers.

These headers establish candidates only. Private intended call context, Blueprint-implementable behavior, networking ownership, and dedicated-server lifecycle must be observed.

## PalSchema sources

- [PalSchema features](https://okaetsu.github.io/PalSchema/docs/features)
- [PalSchema getting started](https://okaetsu.github.io/PalSchema/docs/gettingstarted)
- [Custom spawners](https://okaetsu.github.io/PalSchema/docs/guides/spawners/overview)
- [Blueprint editing](https://okaetsu.github.io/PalSchema/docs/guides/blueprints/intro)
- [Creating an item](https://okaetsu.github.io/PalSchema/docs/guides/items/creatingabow)
- [Creating a building](https://okaetsu.github.io/PalSchema/docs/guides/buildings/craftingstation)

Findings:

- PalSchema can modify DataTable and Blueprint assets at runtime with JSON/JSONC and can add rows.
- It supports categories for appearance, Blueprints, buildings, enums, guide data, items, Pals, raw tables, skins, spawns, and translations.
- Custom spawners can add existing Pals/NPCs and field-boss-like placements.
- New items/buildings often require cooked Blueprint/assets in addition to data.
- Adding any new identity/content is outside Pal Event Director's vanilla-client contract.
- PalSchema may remain useful in an isolated laboratory or for static existing-row experiments, but it is not the planned dynamic core.

## PalMods creator course

- [Creating Mods for Palworld](https://www.palmods.gg/docs/authors/creating-mods)
- [Choose the right format](https://www.palmods.gg/docs/authors/creating-mods/choose-a-format)
- [Create a UE4SS Lua mod](https://www.palmods.gg/docs/authors/creating-mods/lua-modding)
- [Create a PalSchema mod](https://www.palmods.gg/docs/authors/creating-mods/palschema-authoring)
- [PMK and LogicMods](https://www.palmods.gg/docs/authors/creating-mods/modding-kit)
- [Package, test, and publish](https://www.palmods.gg/docs/authors/creating-mods/publishing)
- [Packaging specification](https://www.palmods.gg/docs/packaging)

Findings adopted into this design:

- Choose the least powerful format that expresses the requirement.
- Prototype the riskiest assumption first.
- Separate client/server authority and persistence before implementation.
- Treat reflected paths and signatures as versioned inputs.
- Schedule UObject work on the game thread and make initialization idempotent.
- Test the exact release artifact, clean install, update, mismatched clients, persistence, removal, and dependencies.
- `IsServer` is not the same as server-only player requirements.

## Practical feasibility evidence

These sources demonstrate concepts but do not replace this project's validation.

### Open or inspectable projects

- [Admin Commands](https://github.com/dkoz/AdminCommands) and its [published description](https://www.curseforge.com/palworld/lua-code-mods/admin-commands) demonstrate existing Pal spawn/catch, item/XP grants, time, announcements, teleportation, player position, spectate, logging, and server commands.
- [RewardsEngine](https://www.curseforge.com/palworld/lua-code-mods/rewardsengine) demonstrates a server-side rank/reward concept driven by daily login, playtime, gathering, crafting/building, and kills.
- [PalForge](https://github.com/KBVE/palworld/tree/main/mods/PalForge) demonstrates server-authored text on staff-placed vanilla signboards and documents a negative build-spawn result.
- [Palworld Server Toolkit](https://github.com/fol2/palworld-server-toolkit) demonstrates a Windows server, UE4SS Lua, file IPC, external dashboard, item grants, and Pal spawn administration.
- [Guild Feed Box Sync](https://github.com/Stians92/palworld-guild-feed-box-sync) provides a careful server-oriented design using existing containers and native replication, while explicitly identifying uncompleted multiplayer validation.

### Closed or claim-only evidence

- [Better Server-Side Commands](https://www.nexusmods.com/palworld/mods/3669) claims Windows server-only cross-play operation with no client mod and demonstrates meteor triggers, boss resets, existing Pal/item/XP/point grants, teleports, healing, announcements, and persistent state.

Its page prohibits reuse without permission. This project treats it only as feasibility evidence and does not copy or derive from its code.

### Important negative evidence

PalForge reports that invoking `RequestSpawnMapObject_Server` from bare Lua aborted the process because the native function expects a complete build-request context. Pal Event Director therefore rejects general dynamic build-object spawning and uses staff-placed vanilla signs/structures.

## Facts versus hypotheses

### Established enough to plan as confirmed foundations

- Windows dedicated servers can load official server mod packages.
- Server-only UE4SS Lua can observe and invoke reflected Palworld behavior.
- Native server messages reach vanilla clients.
- Existing item/XP grants, existing Pal spawning, time changes, teleportation, and chat commands have current server-mod examples.
- Meteor triggering has current server-mod evidence.
- Server-side persistent project state and file IPC are practical.

### Probable but requiring focused proof

- Complete capture/kill/gather/craft/build/fishing attribution.
- Safe private system chat on all client platforms.
- Native invasion start/finish and selected-base control.
- Signboard write/restore across filtering and concurrent edits.
- Dungeon/raid/oil-rig/arena result attribution.
- Network spawn ownership through restart/world partition.
- Runtime setting leases with correct client UI.

### Experimental

- Directed raid/arena lifecycle.
- AI escort and controlled multi-wave encounters.
- Multiple simultaneous supply/invasion systems.
- Input restriction, force freeze, PvP minigames, and movement-affecting rules.
- Randomizer weekends on a persistent main world.

## Open technical questions

1. What is the most reliable current dedicated-server world-ready lifecycle hook?
2. Which exact UE4SS build and official package identity are compatible with the target Palworld revision?
3. Does server-only package activation permit vanilla clients while `bAllowClientMod=False` in every cross-play case?
4. Which message API gives reliable private text to Steam, Xbox, PlayStation, and Mac clients?
5. Can server chat commands be suppressed without disturbing normal chat or requiring a client hook?
6. Which capture callback exposes player, target instance, species, level, rarity, passive skills, sphere, and source exactly once?
7. Which kill/death path correctly attributes player, owned Pal, environment, PvP, bosses, and summoned event actors?
8. Can gathering and crafting be distinguished from inventory transfer and director rewards cheaply?
9. What result does the item grant API return for full/partial inventory, and how can delivery be verified?
10. Which non-debug APIs safely grant XP and technology/status/relic points on dedicated servers?
11. What native path starts a meteor/supply event, and how is ownership distinguished from a natural event?
12. Do invader-manager public start methods create complete declaration, navigation, reward, and cleanup behavior from a server mod?
13. What actor/handle identity survives unload/restart well enough for spawn reconciliation?
14. Which existing Pal/NPC IDs and level ranges are safe to spawn and capturable?
15. Can sign text be updated through the normal filtering path without impersonating a player request?
16. Which world settings can change live, replicate correctly, and revert without stale client UI or active-task inconsistency?
17. Can normal dungeon/boss/raid/oil-rig/arena completions be attributed without invoking private server-internal functions?
18. How does the official loader preserve writable config/state across package updates?
19. What performance cost do the required hooks and record/position reconciliation have on a mature world?
20. What package disable/removal sequence leaves the world clean when an event was interrupted?

## Research workflow for each Palworld update

1. Record server executable/display revision and official docs version.
2. Check Pocketpair loader/package/server documentation changes.
3. Check Palworld Modding Kit commits and diff only used headers.
4. Check required UE4SS release/fork and API changes.
5. Regenerate runtime headers/types in an isolated development install.
6. Re-observe every hooked function and parameter shape.
7. Run adapter probes with mutations disabled.
8. Run disposable-world mutation tests.
9. Run vanilla and cross-play journeys.
10. Publish an evidence report before changing the supported-revision claim.

## Documentation caveats

- Community documentation sometimes contains old folder layouts or client-focused examples.
- Generated PMK headers may expose functions that native code does not intend arbitrary callers to invoke.
- Search-result summaries and hosting articles can be stale, contradictory, or promotional.
- Current mod descriptions may claim server-only support without publishing mismatched-client test evidence.
- A working result on one UE4SS provider/build does not imply another provider/build works.

For these reasons, implementation decisions must cite a current primary source plus local runtime evidence whenever possible.
