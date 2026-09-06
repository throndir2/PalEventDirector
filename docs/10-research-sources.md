# Research sources and open questions

## Research date and scope

Initial research was performed on **2026-08-30** and extended with local current-game data inspection on **2026-08-31**. Palworld modding changes quickly; all implementation work must re-check primary sources and runtime dumps for the target revision.

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

### Trigger-route re-audit on IMOUTO

The local reference checkout is pinned to `e6632458b97af0083eb81715775651b08104ef6a`. Its tracked `Content` tree contains only `InitBank.uasset`; it does not contain the shipped game's invasion Blueprint implementations. The manager/player-controller/cheat-manager `.cpp` files contain generated empty or constant-return stubs. They establish declarations for a skeleton SDK, not the behavior of the running Shipping binary.

The PED command path is real invocation, not just an announcement: chat authorization enters `Director:arm_start`, the scheduler records an intent, `Director:start` establishes target state, and `Bridge:start_all_invasions` invokes the selected native method through `_native_call`.

The table below records the earlier `b8972e4` audit. The subsequent Endless Siege integration moves normal admin starts to the public march route; direct admission and controller debug remain explicit comparison commands.

| Current command/authority | Actual native call | Evidence and limitation |
|---|---|---|
| Authorized admin `start`, or `test-native admission` | `UPalInvaderManager::RequestIncidentInvaderEnemy(Guid, Observer)` | This is a private reflected helper in the PMK header. On IMOUTO it returns a Boolean and can begin pathfinding, but that has not produced a confirmed raid. |
| Ordinary start, or `test-native march` | `UPalInvaderManager::StartInvaderMarchForBaseCamp(Guid)` | Public selected-base entry point in the PMK header. A void return does not establish acceptance; test it independently rather than assuming it is equivalent to the private helper. |
| `test-native debug` | `APalPlayerController::Debug_InvaderMarchForNearCamp(GroupName, true)` | Reliable server RPC declaration. Observed clean return without pathfinding or incident. Shipping/editor/cheat restrictions are hypotheses, not proven by the generated empty SDK body. |

Pinned [UE4SS invocation](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUObject.cpp#L86-L244) resolves the calling context, marshals parameters and calls `ProcessEvent`. The explicit receiver used by PED is consumed correctly for a bound UFunction. [Struct return conversion](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUObject.cpp#L296-L310) uses `GetNonTrivialLocal`, and the [StructProperty handler](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUObject.cpp#L707-L782) converts that return to a Lua table. The current base GUID obtained through `GetId()` is therefore not assumed to be a dangling borrowed pointer into the reflected-call stack.

The PMK pathfinder class exposes no reflected result/status methods beyond its constructor. The manager has one `PathFinder` property. Request 12 returned true for its first admission and false for nine subsequent calls, with valid identity-matched targets; the first path search then ended without an incident. This suggests a serialized/shared native admission boundary but does not prove the hidden rejection condition. A default-agent complete navigation query also does not establish compliance with the invader-specific path, water, biome or grade rules.

### Public raid implementations and backend alternatives

The follow-up public search did not find a demonstrated, repeatable native-raid trigger for dedicated Shipping build `24575149`. This is a research limit, not proof that triggering a raid is impossible.

- [`pal-mod-toolkit` at `ecc90f14968a5f0ba3920ade4034a201c6c618b6`](https://github.com/incognitofelix/pal-mod-toolkit/commit/ecc90f14968a5f0ba3920ade4034a201c6c618b6) explicitly says its raid command does not reliably trigger raids. Its [`RaidTool.cpp`](https://github.com/incognitofelix/pal-mod-toolkit/blob/ecc90f14968a5f0ba3920ade4034a201c6c618b6/src/tools/RaidTool.cpp#L68-L137) passes a null dynamic parameter to the Blueprint handoff and subsequently requests all-base marching. Neither step is a demonstrated fix and neither should be copied as a verified sequence.
- [`pal-invader-relocator` at `33228a7792aa7122cb109a868549fdd543b949c4`](https://github.com/incognitofelix/pal-invader-relocator/blob/33228a7792aa7122cb109a868549fdd543b949c4/README.md#L13-L23) explicitly leaves live-versus-cached start-point behavior unverified. Moving start-point actors is not proof of native raid eligibility or a working trigger.
- Epic's [`UCheatManager` documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UCheatManager) says CheatManager is not instanced in Shipping builds by default. That supports caution around cheat APIs, but does not prove that Palworld's separate `Debug_InvaderMarch*` controller RPC bodies are compiled out or that Pocketpair did not override engine defaults.

| Approach | Supported purpose | What it does not establish |
|---|---|---|
| UE4SS Lua | Current reflected invocation, hooks and server-side orchestration | It cannot expose an unreflected private pathfinder implementation merely by enumerating SDK headers. |
| PMK Blueprint / LogicMods | Cooked server-side Blueprint control flow and parity experiments | The standard official arrangement is still UE4SS-backed; changing language does not itself fix native eligibility or missing initialization. |
| UE4SS C++ extension | More control over native hooks, parameter storage and non-Lua observations | A dynamically sized reflected parameter frame still calls the same engine function; it is not proof of a working raid. |
| Separate native server loader | Different hooks/plugin architecture | Compatibility with this exact server build and native-invasion functionality must be demonstrated independently. |

Pocketpair documents [Lua, LogicMods, Paks, UE4SS core and PalSchema packages](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/01-General.md#L14-L42), with [server-side install rules](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/04-Tech.md#L68-L102). This is deployment support, not an official raid-start API.

The [LogicMods workflow](https://github.com/PalworldModding/Docs/blob/master/docs/developers/ue4ss-modding/logic-mods/introduction.md#L28-L40) uses a cooked `ModActor`. The actual [pinned BP loader](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/assets/Mods/BPModLoaderMod/Scripts/main.lua#L275-L301) supports map/actor-world startup paths; any server experiment should prove headless startup rather than rely on client UI, local-player hotkeys or old PlayerController-only assumptions. A server-only controller should reuse stock replicated game actors/content if vanilla clients must remain supported.

The [UE4SS C++ extension interface](https://github.com/UE4SS-RE/RE-UE4SS/blob/main/docs/guides/creating-a-c%2B%2B-mod.md#L49-L114) is a smaller escalation than rewriting PED. A separate example is [PalApi](https://github.com/TRRabbit/palapi-release), which uses its own loader/core/plugin layout rather than UE4SS. Its published server-plugin claims do not demonstrate a raid trigger. The older [VeroFess unofficial API](https://github.com/VeroFess/PalWorld-Server-Unoffical-Api/blob/d4e9479761732cfd51af0d71435fe0a81df9d7da/src/hooks/hooks_install.cpp#L9-L38) illustrates native offset hooks but is not evidence of compatibility with the current game.

Next controls should distinguish public selected-base march from private admission at the same base, and compare a naturally successful enemy raid's lifecycle if one can be observed. Do not change backend and invocation parameters simultaneously and then attribute any difference to the language. If the inaccessible native transition is the remaining obstacle, a narrowly scoped C++ observer or inspection of the shipped Blueprint implementation is more informative than another speculative trigger sequence.

### Downloaded Endless Siege 1.8.28 implementation

The user supplied the mod archive during the 2026-09-06 investigation. Its SHA-256 is `3c9bcfbdfe4707b3e06122d837124e649ff4db5222b4dddc42bde1461def92d7`; the extracted `main.lua` SHA-256 is `70e28ec94c7b8919c1deb4186a451f3fd4a16bb681dcc12f0409fdd0753811ab`. Only six text files were extracted to a private reference directory outside PED and the game installations. The mod was not executed or installed; no third-party source or assets were added to this repository.

This supplies concrete implementation evidence beyond the public description:

| Reference code | Behavior | Implication for PED |
|---|---|---|
| `resolveContext`, lines 451-494 | Finds the first manager/player, gets the nearest base, then its native ID. | This is a host-oriented lookup, not an authoritative per-admin/world-scoped target selection suitable for direct adoption on a dedicated server. |
| `fireWave`, lines 509-518 | Calls `StartInvaderMarchForBaseCamp(campId)`; on a Lua error, tries `StartInvaderMarchAll` and then `StartInvaderMarchRandom`. | The primary call already exists in PED's explicit `test-native march` route. It is different from PED's normal admin `RequestIncidentInvaderEnemy` admission helper. There is no previously hidden creation API in this function. |
| `armWatchdog`, lines 593-614 | Polls live invader counts, waits 360 seconds by default, then retries all-base/random marching if no new body appeared. | A normal Lua return is not a confirmed invasion. The retry cascade broadens scope and is not an equivalent single-base comparison. |
| `stageClock`, lines 1082-1179 | Allows a presumed five-minute preparation phase, infers a negotiator from a lone body and abandons the stage after 480 seconds by default. | PED's 60-second start deadline may be too short for an actually declared public-march raid. An extension should follow the native declaration/deadline, not assume every empty request is legitimate preparation. |
| Startup callback, lines 1547-1564 | Attempts to end every existing `PalInvaderIncidentBase` and parks boss/predator table rows. | Simply installing the reference could remove existing visitor/raid activity and confound the experiment. Do not copy this global cleanup into PED. |

The timeout message blaming Palbox obstruction is emitted for any stage that never sees attackers; it is not the result of a path query or an engine-provided obstruction reason. Likewise, its global live-body count is not a reliable substitute for exact base, incident and invader-type correlation. These heuristics may be useful for its co-op experience but do not establish the cause of PED's no-incident runs.

The PalSchema payload modifies 77 invasion-table rows for tower groups, 88 for predators and seven drop-table entries. Lua also changes composition weights, counts, levels and negotiator prices. Those changes support the mod's extended encounters, not evidence that a normal native raid needs PalSchema. A separate emergency path calls `PalPlayerState:RequestSpawnMonsterForPlayer`; that is a direct Pal-spawn fallback, not proof of a native base invasion or hostile squad.

The packaged README grants credit-based use/modification/redistribution, while the inspected Nexus page displays stricter terms. Keep the archive as reference and resolve the terms before redistributing its code/assets. The implementation findings above do not require copying its source.

### Concrete alternative implementation references

The strongest source-level alternative found is [`dkoz/AdminCommands` at `8043dc6462d481fb2d4d448333f320b3635f1d85`](https://github.com/dkoz/AdminCommands/blob/8043dc6462d481fb2d4d448333f320b3635f1d85/AdminCommands/Scripts/modules/spawn.lua#L103-L165). Its Lua code obtains `PalNPCManager`, uses `NPCAIControllerBaseClass`, constructs `FPalNPCSpawnInfo` and calls `SpawnNPCForServer`. Initialization handling subsequently checks both `TryGetIndividualParameter()` and `TryGetIndividualActor()`. This is a game-specific character-creation path, not merely spawning an uninitialized generic Actor.

The local pinned PMK corroborates the function and the `ControllerClass`, `CharacterID`, `Level`, `Location`, `Yaw` and `Squad` fields in `PalNPCSpawnInfo.h`. Its second parameter is a native delegate, so current binding support still needs qualification before a PED experiment. The example sets `Squad` to nil and contains no base-targeting or complete attack lifecycle. Its author labels spawning experimental. Treat it as the creation portion of a possible custom encounter, not a native invasion trigger or proof of replication on build `24575149`. A custom attack would still need allegiance, squad AI, navigation, target ownership, damage/capture behavior and safe cleanup.

Other concrete backend references are useful for different reasons:

- The matching [UE4SS BP loader](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/assets/Mods/BPModLoaderMod/Scripts/main.lua#L217-L301) provides map-driven mod-actor creation and handles an already existing world. It is genuine headless-capable startup machinery, not Pal/NPC initialization.
- [Palforge's engine bootstrap](https://github.com/AerafalDev/Palforge/blob/a4832c98298384e465d5e459fe97f86d23ed83f9/src/Palforge/Unreal/Runtime/UnrealBootstrap.cs#L37-L82) and [deferred actor creation](https://github.com/AerafalDev/Palforge/blob/a4832c98298384e465d5e459fe97f86d23ed83f9/src/Palforge/Unreal/Reflection/UnrealContext.cs#L711-L744) are actual Windows/.NET runtime code, not just generated SDK declarations. They do not supply the initialized Pal-to-hostile-squad chain, and generated game-property accessors use literal offsets requiring qualification.
- The cached [`chh-ay/palworld-mod-runtime` v1.0.0 source](https://proxy.golang.org/github.com/chh-ay/palworld-mod-runtime/@v/v1.0.0.zip), origin `9d205f8d14305df9e3567813fff7ce9efadd50b0`, contains non-UI UE4SS C++ engine-tick/map-reload callbacks. Its profile targets build `24181105`, explicitly says `NOT_LIVE_QUALIFIED`, and does not provide a stock-NPC spawning implementation. It is a lower-priority lifecycle reference, not a compatible runtime to install.
- [PalDefender's summon contract](https://github.com/Ultimeit/PalDefender/blob/04738dde580d7b403b41c8c007f900db9be8d518/docs/en/FileTypes/PalSummon.md#L6-L54) documents configured stock-Pal summons, but does not expose a reusable complete native invasion implementation. Adding its separate loader would introduce another independent compatibility variable.

These findings support two distinct tracks: qualify the existing public native-march route with declaration-aware observation first, or deliberately implement a PED-controlled encounter using game-specific spawning and explicit squad behavior. A custom encounter must not be presented as a native Palworld invasion. No alternative loader, downloaded raid mod or third-party gameplay code was installed during this research.

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

### Mandatory invasion and bounty findings

The dedicated design is in [mandatory invasions and bounty sieges](11-invasion-and-bounty-design.md).

Current reflected APIs establish:

- `UPalInvaderManager.StartInvaderMarchRandom()`;
- `UPalInvaderManager.StartInvaderMarchForBaseCamp(FGuid)`;
- `UPalInvaderManager.StartInvaderMarchAll()`;
- `APalPlayerController.Debug_InvaderMarch(FName InvaderGropuName, bool bSkipInvaderDeclaration)`;
- `APalPlayerController.Debug_InvaderMarchForNearCamp(FName InvaderGropuName, bool bSkipInvaderDeclaration)`;
- `UPalInvaderIncidentBase.SelectInvaders(...)` and its output array of `FPalInvaderSpawnCharacterParameter`;
- reliable native invasion lifecycle delivery through `UPalNetworkInvaderComponent` and the complete selected row in `FPalIncidentBroadcastParameter`.

The event policy is now explicit: base invasions are mandatory world events without registration or consent, but the flagship target set is filtered to available idle bases belonging to guilds with an online member at the start boundary. Native inability to create an eligible incident remains a technical failure.

The local Modding Kit clone was clean at commit `e6632458b97af0083eb81715775651b08104ef6a`.

The installed `Pal-WindowsServer.pak` inspected on 2026-08-31 had SHA-256 `BFFAB47CBD3B3C6D14D616376D4E0B060B2429A5EB4C2022820D4F38D36A0770` and an internal pak index with 158,456 entries. Read-only inspection used verified `repak` 0.2.3 and UAssetGUI/UAssetAPI 1.1.0. Extracted assets and decoded raw tables were kept outside the repository.

Installed-table findings:

- `DT_PalInvader` has 240 numeric-keyed rows and 76 descriptive group names.
- No stock invasion row contains a `BOSS_*` member.
- Stock rows use up to five character archetype slots, currently up to 16 attackers per row and five waves.
- `DT_PalInvaderReward` has exactly one matching row for each of the 76 stock group names.
- `DT_PalDropItem` has 34 `BOSS_*` special-enemy rows with `BountyProof_1` at 100%, yielding one to five tokens.
- Those bounty drop rows use level `0`, supporting a character-ID-wide drop rule rather than one fixed event level.
- Invasion members do not carry `UniqueNPCID`; fixed-spawner bounty state and one-time progression should not be assumed to transfer.

### Built-in administrator state

The Palworld 1.0 Modding Kit exposes `APalPlayerController.bAdmin` as a replicated, Blueprint-readable Boolean. The generated controller constructor initializes it to false and lifetime replication includes it. No reflected `IsAdmin()` function or equivalent player-state/session privilege result was found. PED therefore reads `bAdmin` fresh from the server-side controller supplied by each chat callback. It does not query `UPalUtility.GetAdminPasswordForCmdline`, inspect world settings, parse `/AdminPassword`, or retain controller authority across messages.

This is the validated-result boundary rather than credential handling. Pocketpair's server command documentation describes `/AdminPassword <password>` as granting administrative privileges; the exact build-`24575149` live gate must prove true after authentication, false for ordinary users, and false again after logout/reconnect. An unavailable, throwing, or non-Boolean reflected property fails closed.

Primary references:

- local Modding Kit `PalPlayerController.h` (`bAdmin`) and `PalPlayerController.cpp` (false default and `DOREPLIFETIME`), commit `e6632458b97af0083eb81715775651b08104ef6a`;
- Pocketpair [server commands](https://docs.palworldgame.com/settings-and-operation/commands/); and
- UE4SS [UObject/RemoteObject property access](https://docs.ue4ss.com/dev/lua-api/classes/uobject.html).

### Progression reward candidates

The local reflected API establishes the mechanics but not the current cooked item rows:

- `EPalItemTypeA::Blueprint` and `EPalItemTypeB::ConsumePalGainFriendshipPoint` identify schematic and trust-consumable categories;
- `FPalItemRecipe.UnlockItemID` links a schematic inventory item to a crafted product;
- `APalPlayerController.GetDefaultPlayerCharacter`, `UPalIndividualCharacterParameter.GetLevel`, and `APalPlayerState.GetTechnologyData` provide candidate player-progression evidence;
- guild/base `GetBaseCampLevel()` is only coarse maturity context and has no proven technology mapping; and
- `UPalPlayerInventoryData.AddItem_ServerInternal` returns `EPalItemOperationResult`, while `CountItemNum64` provides the required 64-bit count surface.

Current v1.0.3 community item indexes list the following **candidates**, not yet build-`24575149` allowlisted findings:

- Pal Souls: `PalUpgradeStone`, `PalUpgradeStone2`, `PalUpgradeStone3`, and `PalUpgradeStone4`;
- trust consumables: `AffectionFruit_02` and `AffectionFruit_01`; and
- schematics in curated `Blueprint_*` families whose technology/product mapping must be exported rather than inferred from naming.

No row literally named `TrustHeart` appears in those indexes; this is not yet an installed-table assertion. Candidate sources are [PalDB's v1.0.3 item table](https://paldb.cc/en/Items_Table) and the [PalMods item-ID snapshot](https://www.palmods.gg/docs/authors/game-ids/items). Before any candidate enters the reward allowlist, read-only extraction from the exact server build must verify ID, item types, stack limit, legality, schematic unlock product, and technology level.

Delivery remains blocked in alpha.3. Native inventory mutation has no reflected idempotency receipt, so a crash after the item is added but before the durable result is recorded creates an ambiguous retry. Valuable schematics, souls, and Kinship Peaches must remain pending obligations until exact enum/delta, full-inventory, offline, reconnect, and crash-boundary tests pass.

### Invasion level-scaling findings

Pocketpair's [official Palworld 1.0 Steam announcement](https://steamcommunity.com/app/1623730/announcements/detail/1822556746155818?l=english) states that the level of raiding enemies now scales according to the level of Work Pals assigned to the deployed base. This supports target-base-local scaling rather than a single player level or guild-wide base-upgrade level. It does not publish the aggregation formula.

Current Modding Kit and installed-asset inspection establish the remainder of the observable pipeline:

- `FPalInvaderDatabaseBaseRow` has `InvadeGradeMin`/`InvadeGradeMax` and per-slot `LevelMin_*`/`LevelMax_*` fields.
- `FPalInvaderDatabaseRow` adds `WaveLevelOffset`.
- `UPalInvaderIncidentBase.SelectInvaders(Grade, Biome, OutInvaderMember)` resolves rows into `FPalInvaderSpawnCharacterParameter` values.
- Every final member parameter has a writable integer `Level` alongside `CharacterID` and `Otomo`.
- Decoded current native spawn Blueprint bytecode consumes `SpawnParameter.Level` during character initialization.
- Current stock rows use grade bands 1–10, 11–20, 21–40, 41–60, and 61–80, although not every biome/group necessarily has every band.
- All 240 current stock rows have `WaveLevelOffset` equal to zero. The field remains part of the API and cannot be assumed permanently unused.
- A low invasion-grade row can still contain high fixed attacker levels in an endgame biome. Invasion grade is therefore an eligibility tier, not itself the guaranteed spawned level.

The installed Blueprint class defaults were also decoded with the current community `Mappings.usmap` at commit `0e4ae19a05ba0d9fb95d859c09b28f168cb3624f` (SHA-256 `604550BA90FAAB1E394C2789F38EEFF625493D3729C2D7F6A6058BFEDB90A67B`). Invasion properties are inherited from native `UPalGameSetting`; the generated current constructor reports `InvadeOccurablePlayerLevel=5`, `InvadeOccurableBaseCampLevel=8`, and `InvadeGradeOffset=0`. These are eligibility/offset settings, not evidence for the worker-level aggregation formula, and Blueprint/runtime overrides still require observation.

Consequences for the event design:

- `native` level policy keeps the concrete level Palworld selected independently for each target base and is the safest initial bounty-siege policy.
- `fixed` policy can set an exact boss level by replacing the final member parameter's `Level` before spawn.
- `relative` policy can apply a bounded offset to that native final level.
- `workerDerived` can implement a transparent project formula from a target-base worker snapshot, but must not be marketed as matching Palworld until the native formula is measured.
- Official wording does not establish whether Palworld uses maximum, mean, median, a top-N statistic, work suitability, party power, or another score. That remains a live observational spike.

### Combat attribution findings

Current Modding Kit declarations and the installed dedicated-server executable establish these native surfaces:

- `UPalEventNotify_Character.OnNotifyEventDamagedInServer(FPalDamageResult)` is a global server-oriented damage notification.
- `FPalDamageResult` exposes `Attacker`, `Defender`, `Damage`, `ActualDamage`, element, weapon, body part, hit location, shield behavior, base power, and `bCannotKill`.
- `UPalEventNotify_Character.OnNotifyEventDeadInServer(FPalDeadInfo)` exposes the victim, `LastAttacker`, `LastDamage`, and `EPalDeadType`.
- Player characters and Pal monsters implement the outgoing inflict/defeat interface and expose `OnInflictDamageDelegate` and `OnDefeatCharacterDelegate`.
- `FPalDyingEndInfo` retains `LastAttackerInstanceID` for completion of the special player dying/downed lifecycle.
- `FPalKillLogDisplayData` contains attacker and killed character IDs, unique-NPC IDs, and player UIDs, but no damage amount.
- Every `UPalCharacterParameterComponent` has a transient, non-replicated `TMap<FPalInstanceID, int32> DamageMap`.
- Ownership candidates include `GetIndividualIDByActor()`, `FPalInstanceID.PlayerUId`, `FPalIndividualCharacterSaveParameter.OwnerPlayerUId`, and active-Pal trainer state.
- Native player records include selected tower, raid, normal-boss, aggregate-boss, and predator defeat counters. They are progression records, not arbitrary kill or damage ledgers.
- Reflected raid, tower, arena, invasion, and oil-rig systems expose participants/outcomes but no combat MVP or top-damage result.

Read-only string inspection of the current installed server executable confirmed the reflected names `DamageMap`, `OnProcessedActualDamageDelegate`, `OnNotifyEventDamagedInServer`, `OnNotifyEventDeadInServer`, `OnInflictDamage`, `OnDefeatCharacter`, and their player/Pal delegates. Searches found no corresponding `MostDamage`, `DamageScore`, combat-contribution winner, or MVP symbol. Absence of a reflected/string name is not proof that no private native calculation exists, but no supported API for retrieving such a winner is currently evident.

Consequences:

- Final-hit counting is strongly supported by native event shapes, subject to runtime lifecycle and edge-case validation.
- Direct player kills and owned-Pal kills can be kept separate or rolled up to the owning player after ownership normalization.
- Per-player or per-Pal damage can be accumulated from one accepted-damage notification using `ActualDamage`, once its precise HP/shield/overkill behavior is measured.
- A contribution leaderboard should be computed by Pal Event Director from its own bounded per-target ledger. Siege League uses target-budgeted effective damage rather than unrestricted raw “most damage”; neither is currently a native scoreboard result.
- Native `DamageMap` is promising as a reconciliation source but its value semantics, contributor identity, and reset points are unknown because generated implementation bodies are stubs.
- Hate/threat state is not a substitute for damage: it can change for non-damage reasons and exposes target-selection behavior rather than a contribution total.

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
- [Tower Boss Base Raid](https://www.nexusmods.com/palworld/mods/3176) demonstrates adding exact tower-boss compositions to `DT_PalInvader` through PalSchema, but does not establish vanilla-client server-only behavior.
- [Endless Siege](https://www.nexusmods.com/palworld/mods/3947) demonstrates native-style tower-duo and predator base assaults, member/count changes, chained stages, and many lifecycle failure cases. Dedicated-server support was still beta in its published description.
- [Raid & Trade Revival](https://steamcommunity.com/sharedfiles/filedetails/?id=3789305121) demonstrates hundreds of data-driven native raid compositions, including Alphas, corrupted Pals, legendaries, and tower bosses. It recommends matching client data for consistent names and therefore is composition evidence, not vanilla-client proof.

### Closed or claim-only evidence

- [Better Server-Side Commands](https://www.nexusmods.com/palworld/mods/3669) claims Windows server-only cross-play operation with no client mod and demonstrates meteor triggers, boss resets, existing Pal/item/XP/point grants, teleports, healing, announcements, and persistent state.

Its page prohibits reuse without permission. This project treats it only as feasibility evidence and does not copy or derive from its code.

RaidWave's cached page described calls to `StartInvaderMarchRandom`, `StartInvaderMarchAll`, and native incident creation plus runtime invasion-row weight changes. The mod is currently hidden as unsupported/affected by unresolved issues, so it is only a research lead and not positive compatibility evidence.

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
- Palworld has a direct all-base invasion method and exact named-group server/debug methods.
- Current bounty token drops are directly keyed to existing `BOSS_*` character IDs, making bounty invasion members technically credible.

### Probable but requiring focused proof

- Complete capture/kill/gather/craft/build/fishing attribution.
- Safe private system chat on all client platforms.
- Native invasion start/finish, selected-base/all-base scope, exact group selection, and declaration bypass.
- Pre-spawn bounty-member substitution and normal token drops without client files.
- Signboard write/restore across filtering and concurrent edits.
- Dungeon/raid/oil-rig/arena result attribution.
- Network spawn ownership through restart/world partition.
- Runtime setting leases with correct client UI.

### Experimental

- Directed raid/arena lifecycle.
- AI escort and controlled multi-wave encounters.
- Multiple simultaneous supply/invasion systems.
- Mandatory all-base bounty sieges at a mature world's maximum base count.
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
12. Does `StartInvaderMarchAll()` attempt every registered base observer, and which native technical states cause exclusion or failure?
13. Does `Debug_InvaderMarch(GroupName, true)` target every base, and does declaration skip also bypass the Negotiator?
14. Can a `SelectInvaders()` post-hook safely replace each output member before native character initialization without a custom DataTable row?
15. Do bounty invasion copies drop `BountyProof_1` correctly on death, capture, and later butchering, and does capture complete the native wave?
16. Are original overworld bounty spawner state, map markers, respawn, and first-clear Ancient Technology Points unaffected?
17. Which statistic converts the target base's assigned Work-Pal levels into native invasion grade, and when is that workforce snapshot taken?
18. Which global damage/death callback is emitted exactly once per accepted hit/defeat, and what is its ordering relative to outgoing delegates and player down/death?
19. Does `ActualDamage` mean HP-only, shield-plus-HP, post-mitigation requested damage, or clamped health loss under every combat edge case?
20. How reliably can weapons, projectiles, partner skills, explosions, DoT, ridden Pals, and base workers be normalized to immediate Pal and owning player?
21. What exactly does native `DamageMap` accumulate, whose instance IDs are keys, and when is it reset or discarded?
22. What actor/handle identity survives unload/restart well enough for spawn reconciliation?
23. Which existing Pal/NPC IDs and level ranges are safe to spawn and capturable?
24. Can sign text be updated through the normal filtering path without impersonating a player request?
25. Which world settings can change live, replicate correctly, and revert without stale client UI or active-task inconsistency?
26. Can normal dungeon/boss/raid/oil-rig/arena completions be attributed without invoking private server-internal functions?
27. How does the official loader preserve writable config/state across package updates?
28. What performance cost do the required hooks and record/position reconciliation have on a mature world?
29. What package disable/removal sequence leaves the world clean when an event was interrupted?

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
