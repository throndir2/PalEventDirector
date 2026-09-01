# Engine capability map

## How to read this map

This is a planning inventory, not an implementation guarantee. Reflection shows what an Unreal object exposes; it does not prove that an arbitrary call supplies required native context or is safe on a dedicated server.

Evidence labels:

- **Confirmed** — primary documentation and/or a current server-only implementation establishes the general capability.
- **Probable** — current reflected APIs provide a credible authoritative path.
- **Experimental** — the path exists but has significant lifecycle, AI, save, replication, prediction, or cleanup uncertainty.
- **Rejected** — incompatible with the vanilla-client contract.

Every enabled capability still passes the acceptance gate in [the vanilla-client contract](02-vanilla-client-contract.md).

## Runtime-format decision

| Format | Useful capability | Fit for this project | Decision |
|---|---|---|---|
| UE4SS Lua | Observe/call reflected functions, inspect objects, timers, files, runtime logic | Excellent for the event core; server-only package supported on Windows | **Primary runtime** |
| PalSchema | Narrow existing data/default edits, spawners, additions | Useful for static experiments, but dynamic changes and new identities can violate vanilla compatibility | Optional laboratory dependency; not core |
| LogicMod | Cooked Blueprint event logic and server helpers | Heavy toolchain; custom replicated classes are forbidden | Deferred, server-local helpers only if Lua cannot express a proven need |
| Resource pak | Replace cooked data/assets | Whole-asset conflicts and client asset mismatches | Avoid for core; no custom visible assets |
| Native C++ | Non-reflected internals and custom runtime capability | Highest crash/security/update burden | Last resort after a documented Lua limitation |
| REST/RCON sidecar | Administration, announcements, players, save/restart, metrics | Safe for operations but too narrow for gameplay observation/actions | Optional supporting process |

## Core primitives

| Capability | Evidence | Vanilla fit | Risk | Planned adapter or spike |
|---|---|---:|---:|---|
| World-ready lifecycle | Confirmed | Yes | Medium | Use dedicated-server-compatible engine/world hooks; prove one registration per world. |
| Wall-clock scheduling | Confirmed | Yes | Low | Mod-owned scheduler using UTC plus configured display timezone. |
| Game-time scheduling | Probable | Yes | Low | `UPalTimeManager` exposes hour/minute changes and timer-by-span. Observe before binding. |
| Public server notice | Confirmed | Yes | Low | `APalGameStateInGame.BroadcastServerNotice`, reliable multicast. |
| Public system chat | Confirmed | Yes | Low | `BroadcastChatMessage` or `UPalUtility.SendSystemAnnounce` through validated native shape. |
| Private system chat | Probable | Yes | Low | `UPalUtility.SendSystemToPlayerChat` to existing player UIDs. |
| Chat command ingestion | Confirmed | Yes | Low | Hook server-received chat, parse `!` commands, sanitize, rate-limit, optionally suppress if safely possible. |
| Join/leave roster | Confirmed | Yes | Low | Possession/login hooks plus roster reconciliation; never depend on client `ClientRestart`. |
| Player identity resolution | Confirmed | Yes | Medium | Stable Palworld UID as primary key; names/platform IDs are aliases only. |
| Player/guild/base lookup | Probable | Yes | Low | `UPalUtility` and `UPalBaseCampManager` accessors; cache weakly and re-resolve. |
| Position and zone occupancy | Confirmed | Yes | Medium | Read replicated authoritative character transforms on a bounded interval. |
| Server health/load | Confirmed | Yes | Low | REST metrics and/or game-state frame time/entity counts; adaptive shedding. |
| Mod-owned persistence | Confirmed | Yes | Medium | Atomic journal and snapshots outside save data; no live save editing. |
| External dashboard/Discord | Confirmed | Optional | Medium | Local sidecar and atomic file IPC; core never waits on network. |

## Observation primitives

| Signal | Evidence | Likely source | Main question before release |
|---|---|---|---|
| Player chat | Confirmed | `BroadcastChatMessage` / `EnterChat_Receive` flow | Reliable sender/category mapping and safe suppression semantics. |
| Player death/kill | Confirmed | damage/death functions and kill-log data | Attribution across Pals, environment, PvP, disconnect, and overkill. |
| Pal capture | Confirmed | capture success path and player record deltas | Exact player, species, level, rarity, passive data, and duplicate firing. |
| Existing item grant | Confirmed | `UPalPlayerInventoryData.AddItem_ServerInternal` | Full inventory behavior, stack limits, invalid IDs, notification, offline delivery. |
| Item pickup/resource gathering | Probable | item/container/network operation hooks and record triggers | Distinguish gathering, pickup, transfer, crafting output, and admin grants. |
| Craft completion | Probable | work/item production hooks; `CraftItemCount` record | Attribute player versus base Pal and prevent count duplication. |
| Build completion | Probable | player-record `OnCompleteBuild_ServerInternal` and base manager | Attribute builder, validate object type, handle cancellation/dismantle. |
| Work/base production | Probable | work-progress and container operations | Efficient source attribution across many bases. |
| Fishing result | Probable | `UPalFishingSystem` result and obtained-character delegates | Whether server delegates expose player, species, size, rarity, and result consistently. |
| Boss defeat | Probable | boss manager, kill data, replicated record counters | Participant attribution and one completion per instance. |
| Dungeon boss captured/killed | Probable | `UPalDungeonInstanceModel` server-internal transitions | Identify entrants and completion time without invoking internals. |
| Dungeon/stage entry | Probable | player record entering-stage updates | Stable stage identity and reconnect/travel semantics. |
| Raid boss start/finish | Probable | `UPalRaidBossManager` delegates | Guild/base ownership, finish type, participants, reward duplication. |
| Invasion waves | Probable | `UPalInvaderManager` delegates | Correct base, wave, arrival, timeout, and cleanup transitions. |
| Oil-rig crate/clear | Probable | `UPalOilrigManager.OnOpenCrateDelegate`, record counter | Identify opening player and clear attribution. |
| Arena entry/result | Experimental | arena subsystem/models/ranking records | Dedicated-server lifecycle, participant result, native UI assumptions. |
| Fast travel/area discovery | Probable | player record flags and travel request path | Count true unlock/discovery rather than repeat travel. |
| Relic acquisition | Probable | player-record relic delegates | Distinguish new acquisition, migration, and admin grants. |
| NPC talk/trade | Probable | player-controller server talk delegate and record maps | Unique interaction and anti-spam semantics. |
| Base create/remove | Probable | base manager delegates | Guild ownership and initialization completeness. |
| Sign changes | Confirmed | signboard replicated text/delegate | Content filtering, staff ownership, and safe update path. |

Record polling can supplement a missing event hook by comparing monotonic counters. It cannot provide details absent from the counter and must not poll large player/object graphs every frame.

## Action primitives

| Action | Evidence | Vanilla fit | Risk | Guardrails |
|---|---|---:|---:|---|
| Announce/public/private message | Confirmed | Strong | Low | Length cap, rate limit, sanitization, queue, deduplication. |
| Update existing sign text | Confirmed | Strong | Medium | Staff-placed allowlisted signs only; native filtering; restore previous text. |
| Grant existing item | Confirmed | Strong | Medium | Revision allowlist, quantity/stack cap, full-inventory handling, reward ledger. |
| Grant XP | Confirmed | Strong | Medium | Per-event/player caps; level-cap tests; no debug-only API in production if a normal path exists. |
| Grant technology/status/relic points | Confirmed/Probable | Strong | High | Prefer normal validated data APIs; test save/reconnect; never decrement. |
| Heal/revive player or carried Pals | Confirmed | Strong | Medium | Only explicit event scope; do not override hardcore rules silently. |
| Teleport player | Confirmed | Strong | High | Floor/nav validation, instance awareness, opt-in, cooldown, origin recovery. |
| Set world time | Confirmed | Strong | Medium | Lease original clock behavior; avoid repeated jumps; announce. |
| Change time progression | Probable | Conditional | High | Client visual/prediction test; bounded lease and crash recovery. |
| Change server-authoritative rate/setting | Confirmed/Probable | Conditional | High | Per-setting capability allowlist; lease; UI mismatch review; no arbitrary property names. |
| Spawn existing Pal/NPC | Confirmed | Strong if native path | High | Network-aware character manager, valid ID/class, level/count/area caps, spawn registry. |
| Spawn shiny/rare existing Pal | Confirmed | Strong | High | Use normal initialized character parameters; cap rarity and cleanup. |
| Despawn event character | Probable | Strong | High | Only director-owned handles; never despawn captured or unrelated actors. |
| Trigger meteor/supply incident | Confirmed community evidence | Strong | High | Native supply/incident path, distance/cooldown limits, completion reconciliation. |
| Start invader march | Probable | Strong | High | `UPalInvaderManager` supports random, one-base, and all-base starts; base attacks are mandatory events, with no project consent gate. |
| Select a stock invasion group | Probable/high confidence | Strong | High | `Debug_InvaderMarch(FName InvaderGropuName, bool)` accepts the descriptive group name and can skip declaration; confirm target scope live. |
| Substitute bounty invasion members | Probable | Strong if pre-spawn | Very high | Post-hook native `SelectInvaders()` and replace output members with allowlisted existing `BOSS_*` IDs before native spawn. |
| Control substituted invasion levels | Probable/high confidence | Strong if bounded | Very high | Preserve the native per-base final level, set an exact level, or apply a bounded offset by editing each selected `FPalInvaderSpawnCharacterParameter.Level` before spawn. |
| Request built-in incident | Probable | Strong | High | Allowlisted incident IDs and complete context; force-stop only director-owned instance. |
| Start/enter tower boss | Experimental | Conditional | High | Native manager lifecycle, preconditions, instance limit, safe exit. |
| Orchestrate raid boss | Experimental | Conditional | Very high | Do not bypass altar/item/guild invariants until complete native flow is understood. |
| Enter arena/solo arena | Experimental | Conditional | Very high | Native room/rule lifecycle and UI must work without custom client state. |
| Force/reset oil rig | Experimental | Conditional | Very high | Persistent world reset semantics and multi-player ownership need proof. |
| Apply damage/kill/freeze/input restriction | Confirmed but dangerous | Conditional | Very high | Opt-in minigames only; prediction/reconnect cleanup; disabled by default. |
| Trigger existing VFX/camera/audio | Experimental | Conditional | High | Only through a normally replicated existing gameplay action. No arbitrary client RPC. |
| Spawn build/map object | Rejected for now | No safe proof | Critical | A bare `RequestSpawnMapObject_Server` has caused process aborts; staff pre-place vanilla objects. |
| Spawn custom actor/content | Rejected | No | Critical | Violates client class/asset knowledge invariant. |

## Built-in system opportunities

### Time

`UPalTimeManager` exposes current day/hour/minute, night lifecycle delegates, fixed-hour changes, and game-time timers. This supports sunset starts, night hunts, timed phases, and calendar displays. Time mutations still need visual and sleep-system tests.

### Messaging

`APalGameStateInGame` exposes reliable multicast server notices and chat messages. `UPalUtility` exposes system announcement and targeted system-chat helpers. These are the primary vanilla UI.

### Players, guilds, and records

`UPalUtility` exposes player lists, characters, controllers, UIDs, guilds, inventories, record data, technology, bases, managers, and server checks. `UPalPlayerRecordData` contains replicated counters and flags for captures, bosses, crafting, dungeons, oil rigs, arena solo clears, fishing, treasures, camps, relics, discoveries, and stage entry. These are excellent reconciliation sources, but direct writes to record data are not planned.

### Character spawning

`UPalCharacterManager` exposes initialization, creation, network spawn, despawn, and handle lookup. Current server command mods prove existing Pal spawning is achievable. The adapter must use fully initialized parameters, network-aware spawn parameters, game-thread execution, and owned-handle cleanup.

### Invasions and incidents

`UPalInvaderManager` exposes random, selected-base, and all-base march starts plus declaration/start/arrival/wave/end delegates. Player-controller and cheat-manager APIs also accept an `InvaderGropuName`; current installed data uses 240 numeric row keys grouped under 76 descriptive `GroupName` values, strongly establishing the latter as the intended selector. The exact server API can skip invasion declaration, which is the candidate forced-assault path when the native Negotiator should not permit cancellation.

Current `DT_PalInvader` rows define five character/companion slots, minimum/maximum member levels, counts, biome, invasion grade, weight, waves, intervals, experience, and wave offsets. Stock data contains no `BOSS_*` members. Current `DT_PalDropItem` contains 34 bounty-character rows that grant `BountyProof_1` at 100%, so replacing native selected members with existing bounty IDs before spawn is a strong candidate for token-farming sieges.

Palworld 1.0 officially says raid-enemy level scales from the Work Pals assigned to the deployed base. The native pipeline therefore evaluates each targeted base separately; it is not documented as one guild-wide level. Runtime structures expose the resulting concrete level on every selected member as `FPalInvaderSpawnCharacterParameter.Level`, and the installed spawn Blueprint passes that value into character initialization. This gives the director a precise pre-spawn control point while allowing `native` policy to preserve Palworld's own target-base balance.

The exact statistic used to reduce a base's assigned Work-Pal levels to an invasion grade is not exposed in generated source or the official notes. Do not describe it as maximum, mean, median, highest-N average, or equality with any particular worker until a controlled runtime matrix establishes that rule. Current grade bands and row level ranges also show that native scaling is indirect: Work-Pal state selects a grade/eligible row, then row data produces concrete attacker levels. See [the dedicated invasion design](11-invasion-and-bounty-design.md).

`UPalIncidentSystem` can request and stop allowlisted native incidents. Invasion and incident adapters require concurrency, lifecycle, and ownership guards, but base targeting does not require player consent.

### Supply events

The supply manager exposes supply state and start/end delegates, while current server mods demonstrate meteor triggering. The exact supported start path must be discovered from current runtime calls rather than inferred from headers alone.

### Instances

Boss, dungeon, raid, arena, fishing, and oil-rig managers expose useful state and delegates. Observation is generally lower risk than forcing lifecycle transitions. Initial support should score normal player-initiated instances before the director attempts to create or reset them.

## Known negative findings

- A current server project reports that calling the native build-object spawn request from bare Lua can abort PalServer because the call expects a complete build-request context. Dynamic event structures are excluded until a safe native path is independently proven.
- A reflected function can be private in intended native use even when generated metadata exposes it as `BlueprintCallable`.
- Client-local initialization hooks commonly used in single-player Lua mods are unreliable or absent on dedicated servers.
- Runtime property changes can be authoritative while leaving stale vanilla UI, as demonstrated by base-range changes whose visual ring does not update.
- Two UE4SS installations can collide and crash; the server must have exactly one managed runtime.

## Required capability spikes

The roadmap must answer these before advanced templates ship:

1. Exact dedicated-server world-ready hook for current revision.
2. Private and public message behavior across all claimed client platforms.
3. Chat sender/category mapping and command suppression.
4. Existing-item grant behavior for full inventory and reconnect.
5. Capture and kill attribution, including Pal and environmental sources.
6. Network-aware spawn/despawn with captured, dead, unloaded, and timed-out actors.
7. Meteor/supply start and completion path.
8. All-base invasion scope, exact `GroupName` selection, declaration bypass, concurrency, and cleanup.
9. Position/zone tracking cost at maximum expected players.
10. Record-delta reconciliation for crafting, dungeon, oil-rig, fishing, and discovery goals.
11. Safe sign update and restore behavior.
12. Per-setting modifier compatibility, one property at a time.
13. Instance-system observation before any forced entry/start/reset.
14. Crash recovery while a modifier, spawn wave, teleport round, or pending reward is active.
15. Pre-spawn bounty-member substitution, token drops on kill/capture/butcher, wave completion, and independence from fixed overworld bounty state.
16. Per-base Work-Pal-to-grade behavior and final invasion levels across controlled worker-level distributions, including empty slots and workers changed during declaration.
