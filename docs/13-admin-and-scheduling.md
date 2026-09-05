# Alpha.3 administration and scheduling

> **Current code versus required design:** the direct laboratory profile enables in-game starts with automatic native breadcrumbs and no manual preflight prerequisite. This revision adds admin throttle exemptions, pending-countdown supersession, admin-first due-work processing, and direct native enemy-incident admission without rewriting cooldown timers. Native acceptance still requires a live test. Active-incident replacement and the complete [admin command contract](11-invasion-and-bounty-design.md#highest-priority-admin-chat-control) remain future work.

## Scope and safety

Alpha.3 is a laboratory-only release. Its mutation preflight rejects any mode other than `laboratory`, and every capability is disabled in the generated configuration. It never requires a client mod: players connect with normal vanilla clients and use ordinary Palworld chat and server notices.

On IMOUTO, the installed preparation command configures the attested profile while stopped. The `laboratory-native-test` profile enables chat/combat/invasion/substitution capabilities, with schedules and item grants disabled. The older isolated diagnostic profile disables all capabilities. Both preserve configuration backups and recovery evidence and pin build `24575149` / UE4SS API `3.0.1`. The local stepped helper is optional, not a gameplay unlock ceremony.

The persistent configuration is `Pal/Saved/PalEventDirector/config.json` below the dedicated-server root, or the directory selected by `PAL_EVENT_DIRECTOR_DATA_DIR`. It is strict JSON, not JSONC. Stop the laboratory server before editing it and restart after every edit; configuration is loaded only at mod startup.

Schema 3 intentionally has no migration from earlier alpha configurations or state. Archive the complete `Pal/Saved/PalEventDirector` directory before an upgrade, start once to generate a safe schema-3 configuration, stop, and reapply reviewed values. Never copy the Production event-state directory into DEV.

## Gameplay contract and implementation status

The command tables below describe the implemented alpha.3 behavior unless explicitly marked as required design. Direct testing follows [the laboratory runbook](15-preflight-crash-diagnostics.md). The admin-priority contract supersedes ordinary throttling/cooldown policy for authorized administrators as a design requirement; implementation must be completed before claiming those overrides work.

### Required admin behavior

An authorized admin chat command is highest-priority control intent. Routine native/PED cooldowns, scheduled work, and ordinary-user throttles must not veto or silently delay it. Zero minutes means execute now; a requested positive countdown must be honored. Conflicts require scoped cancellation/replacement, not a generic "already active" refusal. Admin queries must receive prompt replies, and aliases must behave consistently.

Commands must report their own accepted, executing, succeeded, failed, partial, or superseded outcome. Native acceptance must be observed; "completed, zero invaders" is not success for a rejected start. Status must distinguish the latest attempt from historical completed events. See [the complete contract and integrity boundaries](11-invasion-and-bounty-design.md#highest-priority-admin-chat-control).

### Event boundary

A start is mandatory for the eligible target set; it is not a consent vote. At the start boundary the adapter:

1. snapshots every valid online player controller;
2. resolves every online player UID to a native guild ID, failing the whole start if any lookup is uncertain;
3. selects only available, idle invasion observers whose base belongs to one of those online guilds;
4. rejects the start if any native invasion/visitor slot, eligible observer, required reflected function, runtime version, or configured bound is unsafe;
5. enrolls the same online-player snapshot in one server-wide leaderboard, regardless of guild; and
6. issues one selected-base native probe request, then requests the remaining eligible bases only after a correlated native start callback confirms the probe.

A guild with no online member at that boundary is not attacked. Every online player is enrolled even if that player's guild has no selected base. Players who join while the event is active are enrolled globally on the next poll and before their first accepted score record. An attribution that cannot be tied to an enrolled online player consumes the target's damage budget but receives no score or final hit.

The selected-base start API returns no success value. A normal Lua return is recorded only as `probe_call_returned` or `fanout_call_returned`; a base is considered started only after a matching native lifecycle callback. The adapter resolves the active manager from an online player's world and pins it for the occurrence. Immediately before and after each call it records masked observer key/target/model GUID agreement, invasion/path/cooldown flags, base availability/ignore/state/level, incident membership/state, start-location and saved-state membership, global manager pointers, and the world invasion switch.

PED does not display `RAID STARTED` until the first correlated callback is durably recorded. If the probe has no callback before `startDiscoverySeconds`, remaining bases are not called, the event persists `event_start_failed`, and the player sees a specific `START FAILED` notice. That terminal creates no rankings, normal results, or reward obligations. After a confirmed probe, fanout gets a fresh discovery window; a missing callback for an individual fanout base remains a technical `native_start_missing` outcome while confirmed bases continue normally.

## Countdown and notification behavior

Manual starts accept an integer from 0 through 60 minutes. Passing `0` starts immediately; no separate `start-now` alias exists.

- A positive manual start announces its selected duration immediately, then announces the 10-, 5-, and 1-minute milestones that fit before the start without duplicating equal offsets. For example, seven minutes produces 7/5/1 notices, while one minute produces one notice.
- A zero-minute manual start emits no fabricated countdown notice and proceeds directly through the normal environment, authority, eligibility, concurrency, persistence, and dispatch gates.
- Daily and weekly schedules must contain warning offsets `600`, `300`, and `60` seconds. Extra offsets are allowed.
- The poll interval is limited to 250–5000 ms. Before the first visible side effect, PED durably marks warning delivery in progress. Once that intent exists, delivery is never repeated after a failure or restart because the external banner/chat outcome may be ambiguous.
- If any configured warning cannot be durably recorded and broadcast near its required boundary, that occurrence is marked missed and does not mutate Palworld.
- `lateStartToleranceSeconds` permits a previously warned occurrence to start slightly late; it never excuses a missing warning.

Every event notification uses two vanilla-client channels:

- the red server-notice banner contains only a short title, capped at 80 bytes, such as `SIEGE LEAGUE - 5 MINUTES` or `SIEGE LEAGUE - RAID STARTED`; and
- Palworld system chat carries the profile, timing, target rule, objective, results, or safety details.

Countdown and lifecycle details use `UPalUtility.SendSystemAnnounce`. Query results, help, cooldowns, and command errors use `UPalUtility.SendSystemToPlayerChat` with the requesting player's existing server-side UID and do not consume the red banner. Both exact delivery shapes remain part of the IMOUTO vanilla-client gate.

Warning, occurrence, event-intent, dispatch, and periodic checkpoint records carry a complete recoverable state in the checksummed journal. Score, roster, and ordinary lifecycle changes are marked dirty and enter that state at the configured checkpoint interval. An interrupted snapshot checkpoint can recover from a state-bearing journal tail. Restart during a native start or active event still enters a fail-closed recovery state because native side effects cannot be inferred safely.

## Scheduling

Schedules use the Windows dedicated server's local clock. IMOUTO must remain on the intended local time zone for laboratory schedules. Alpha.3 supports `daily` and `weekly` recurrence.

A disabled weekly example is present in the generated configuration:

```json
{
  "id": "weekly-all-bounty",
  "name": "Weekly All-Bounty Alarm",
  "enabled": false,
  "frequency": "weekly",
  "dayOfWeek": "SAT",
  "hour": 19,
  "minute": 0,
  "profile": "all-bounty",
  "warningSeconds": [600, 300, 60],
  "lateStartToleranceSeconds": 60
}
```

A daily example is:

```json
{
  "id": "daily-patrol",
  "name": "Daily Bounty Patrol",
  "enabled": true,
  "frequency": "daily",
  "hour": 20,
  "minute": 30,
  "profile": "patrol",
  "warningSeconds": [600, 300, 60],
  "lateStartToleranceSeconds": 60
}
```

Field rules:

| Field | Rule |
|---|---|
| `id` | Unique lowercase identifier matching letters, digits, dots, and hyphens; must start with a letter or digit. Changing it creates a new recurrence identity. |
| `name` | Non-empty announcement label, at most 120 bytes. |
| `enabled` | `true` activates recurrence. It also requires all start/observation/substitution dependencies. |
| `frequency` | `daily` or `weekly`. |
| `dayOfWeek` | Required for weekly schedules: `SUN`, `MON`, `TUE`, `WED`, `THU`, `FRI`, or `SAT`. |
| `hour` | Local hour, 0–23. |
| `minute` | Local minute, 0–59. |
| `profile` | Canonical ID present in `siegeLeague.allowedProfiles`. |
| `warningSeconds` | Integer offsets from 1 through 86400 seconds; must include 600, 300, and 60. |
| `lateStartToleranceSeconds` | 0–600 seconds after the intended start, provided every warning was sent. |

The scheduler plans the next occurrence in advance, including a next-day event whose ten-minute warning falls before midnight. A nonexistent local wall time during a daylight-saving transition is skipped rather than normalized to another hour. For a repeated local hour, the host C runtime chooses one epoch and the occurrence key prevents that epoch from running twice. Validate local DST behavior on DEV before scheduling events in transition windows.

Use `ped schedule` or `!siege schedule` to display up to five upcoming local timestamps. To disable or change a recurring schedule, stop the server, edit the configuration, and restart. `cancel` affects only a currently armed manual countdown.

On restart, a restored recurring occurrence is retained only when its complete embedded definition exactly matches the currently enabled schedule with the same ID. Disabling, removing, or editing its time, profile, name, warning offsets, or tolerance cancels the stale occurrence before it can announce or start.

## Chat commands

Chat handling is available only when `capabilities.chatCommands=true`. Requester-targeted queries are rate-limited per player without suppressing another player's reply.

Public forms:

| Command | Result |
|---|---|
| `!event` | Alias for current director status. |
| `!score` | Caller contribution, final hits, and defended-base count. |
| `!leaderboard` | Current or last global standings. |
| `!siege` or `!siege status` | Event status, base counts, player count, target count, and pending rewards. |
| `!siege profiles` | Enabled profile IDs and display names. |
| `!siege schedule` | Up to five upcoming manual/recurring starts in host-local time. |
| `!siege score` | Caller score. |
| `!siege leaderboard` | Global standings. |
| `!siege start <profile> [minutes]` | Starts immediately at `0`, or arms a 1–60-minute countdown when policy permits. Omitted minutes use `manualCountdownMinutes`. |

`chatStartPolicy` is the unified policy for every privileged chat command:

| Policy | Authority |
|---|---|
| `operatorOnly` | Stable player UID must appear in `operatorUids`. |
| `palworldAdminOnly` | The sender's current server-side `APalPlayerController.bAdmin` must be the Boolean `true`. |
| `operatorOrPalworldAdmin` | Either configured UID or current Palworld admin authentication; this is the default and the recommended IMOUTO policy. |
| `anyUser` | Every player may use every privileged chat command. This legacy/private-server option also exposes cancel/resolve/abort/reset and should be selected deliberately. |

Palworld admin authentication and PED operators are different. A player becomes a Palworld admin through Palworld's built-in administrator mechanism; PED reads only its validated result, `APalPlayerController.bAdmin`, from the server-side controller supplied by the chat callback. PED never reads `AdminPassword`, parses a password command, trusts a display name, or accepts a client-provided admin claim. The property is reflected as a replicated Boolean in the Palworld 1.0 Modding Kit and is runtime-gated to adapter `palworld-1.0.3-lab`, dedicated build `24575149`.

The bridge reads `bAdmin` again for every command and retains no controller or authority cache. Admin logout or reconnect therefore uses the fresh controller state. A missing, throwing, non-Boolean, or otherwise ambiguous property produces a specific fail-closed denial under either policy that depends on Palworld admin state. Under the combined policy, an independently matching `operatorUids` entry remains sufficient. Every decision is audited with a masked stable UID; names never participate.

Privileged chat forms:

| Command | Result |
|---|---|
| `!siege cancel` | Cancels one planned manual countdown; it does not cancel recurrence or a native invasion. |
| `!siege resolve` | Resolves a starting, active, or recovery event and creates score/reward obligations. |
| `!siege abort` | Stops director scoring/tracking; native Palworld incidents continue normally. |
| `!siege reset` | Returns completed/aborted/recovery state to idle only when no native invasion is active. |
| `!siege test-native` / `!ped test-native` | Admin-only, immediate one-base native entry-point test while inside an eligible base. Uses a fixed stock group through `Debug_InvaderMarchForNearCamp`, with no bounty substitution or fanout. Not an all-base command or a gameplay prerequisite. |
| `!ped <operator command>` | Runs the corresponding console command below after the same fresh policy decision. |

Unknown commands print the bounded help form. Ordinary users retain the two-second per-UID command limit, ten-second process-local start limit, and configured user-start cooldown. Authorized admins/operators bypass those limits. A newer admin manual countdown atomically supersedes an older pending manual countdown, and due admin work is processed before ordinary due work. Positive countdown duration is still honored.

Admin starts carry an internal, persisted `adminOverride` selected by the authorization result, never from chat text. Their selected-base request uses `RequestIncidentInvaderEnemy(Guid, Observer)`, does not veto solely on a readable cooldown flag, and never rewrites cooldown timers. Native rejection is reported explicitly; acceptance still requires lifecycle confirmation. Current status prioritizes the latest failed manual attempt over an unrelated historical completed event.

Chat start requests also retain their requester privately so PED can report bounded progress directly: request received, target count validated, native call returned, and lifecycle outcome. A returned call is explicitly not called a confirmed raid. A zero countdown skips the deliberate wait; `startDiscoverySeconds` (default 60) only bounds the subsequent wait for lifecycle confirmation, not a guaranteed spawn delay. Timeout replies summarize pathfinding, incident presence, and hook counts without exposing player IDs or world positions. Native-error replies identify the fixed operation label and a bounded failure classification, never the raw error; further native calls remain locked until investigation and a fresh server process.

## Server-console commands

In the direct laboratory profile, ordinary console commands are available subject to their implemented state checks. The stepped diagnostic remains optional. Native-all comparison and item grants remain disabled in the current profile.

UE4SS command contract:

| Command | Result |
|---|---|
| `ped start [profile] [minutes]` | Starts immediately at `0`, or arms a positive manual countdown. The configured default profile and countdown are used when omitted. |
| `ped cancel` | Cancels a planned manual countdown. |
| `ped status` | Displays director status. |
| `ped profiles` | Lists enabled profiles. |
| `ped schedule` | Lists upcoming starts in local time. |
| `ped leaderboard` | Displays global standings. |
| `ped resolve` | Resolves the current event. |
| `ped abort` | Stops director scoring without destroying native actors. |
| `ped reset` | Clears a terminal/recovery director state after native incidents finish. |
| `ped diagnose-native-all confirm-disposable-start-all` | Disabled in the current direct-test profile. The historical comparison requires separately restored disposable-world evidence and is never an event fallback. |
| `ped rewards` | Processes pending grants only when `grantItems` is available. Alpha.3 validation requires `grantItems=false`, so this command fails closed. |

There is no separate `start-now` alias and no command that force-stops an unknown native invasion; use a zero-minute `start` explicitly. The native-all diagnostic may include offline-guild bases and is intentionally excluded from chat, scoring, bounty substitution, and automatic recovery. Never run selected-base and native-all comparisons in the same world state: restore the same disposable snapshot between runs and compare the masked logs.

## Built-in profiles

| ID | Native member transformation |
|---|---|
| `all-bounty` | Replace every intercepted member and rotate the audited 34-ID bounty roster globally. |
| `patrol` | Use only one- and two-token bounty targets. |
| `mixed` | Replace one member with a bounty captain and retain native escorts. |
| `most-wanted` | Use two- through four-token targets. |
| `kingpin` | Replace every selected member with Ram (`BOSS_DarkTrader`). |
| `jackpot` | Use only four- or five-token targets. |
| `native` | Preserve the native selected composition; baseline control. |

Profiles never resize Palworld's native member array. A transformation failure leaves that base unranked.

## Complete configuration reference

### Root and compatibility

| Key | Accepted values and effect |
|---|---|
| `schemaVersion` | Must be integer `3`. |
| `mode` | `laboratory` or `production`; alpha.3 invasion preflight permits only `laboratory`. |
| `compatibility.requiredAdapter` | Must exactly match the runtime adapter, currently `palworld-1.0.3-lab`. |
| `compatibility.allowedServerBuildIds` | Exact numeric Steam build IDs. Mutation requires at least one and also requires the process environment `PAL_EVENT_DIRECTOR_SERVER_BUILD_ID` to match. |
| `compatibility.allowedUe4ssVersions` | Exact `major.minor.patch` values returned by `UE4SS.GetVersion()`. Mutation requires a non-empty exact-match list. Do not guess this value from an archive filename. |

### Runtime and capabilities

| Key | Accepted values and effect |
|---|---|
| `runtime.pollIntervalMs` | 250–5000; drives schedules, late joins, and event settlement. |
| `runtime.checkpointIntervalSeconds` | 1–300; maximum interval for dirty score/lifecycle snapshots. Critical transitions checkpoint immediately. |
| `runtime.logLevel` | `debug`, `info`, `warn`, or `error`. |
| `capabilities.observeCombat` | Registers damage/death hooks. |
| `capabilities.observeInvasions` | Registers native lifecycle hooks. |
| `capabilities.chatCommands` | Registers the ordinary-chat command hook. |
| `capabilities.startAllInvasions` | Legacy key name for selected eligible-base dispatch. Requires both observation capabilities. |
| `capabilities.substituteBountyMembers` | Registers `SelectInvaders` transformation. Required by enabled non-native starts/schedules. |
| `capabilities.grantItems` | Must remain `false` in alpha.3. |
| `diagnostics.traceHooks` | High-volume focused hook tracing; enable only briefly. |
| `diagnostics.observationProbe` | Logs bounded idle hook payload summaries without opening an event. |

### Bounds and Siege League

| Key | Range or values |
|---|---|
| `limits.maxBases` | 1–256 eligible bases. |
| `limits.maxTargets` | 1–4096 ranked target identities. |
| `limits.maxPlayers` | 1–1024 globally enrolled players; a larger start roster blocks the event. |
| `limits.maxDamageRecords` | 100–1,000,000 records. |
| `limits.maxAnnouncementLength` | 40–1000 bytes after sanitization for detailed chat; red banner titles have an additional hard cap of 80 bytes. |
| `siegeLeague.name` | Event label. |
| `siegeLeague.defaultProfile` | Canonical enabled profile used when omitted. |
| `siegeLeague.allowedProfiles` | Array of unique canonical profile IDs. Arbitrary character IDs/functions are never accepted. |
| `siegeLeague.chatStartPolicy` | `operatorOnly`, `palworldAdminOnly`, `operatorOrPalworldAdmin`, or `anyUser`; applies to all privileged chat commands. |
| `siegeLeague.userStartCooldownSeconds` | 60–604800, global and persistent for ordinary-user starts; authenticated admins and authorized operators are exempt. |
| `siegeLeague.manualCountdownMinutes` | 0–60; zero starts immediately. |
| `siegeLeague.allowCrossBaseRoaming` | Must be `true` in alpha.3; all eligible-base contribution accumulates globally. |
| `siegeLeague.targetPoints` | 1–1,000,000 points budgeted across each target's immutable maximum HP. |
| `siegeLeague.minimumParticipationPoints` | 0 through `targetPoints * maxTargets`. |
| `siegeLeague.leaderboardSize` | 1–50 displayed entries. |
| `siegeLeague.startDiscoverySeconds` | 5–600; bounded callback/request correlation window. |
| `siegeLeague.settleDelaySeconds` | 1–300 after all bases reach terminal outcomes. |
| `siegeLeague.maxRuntimeSeconds` | 60–21600. |
| `siegeLeague.creditDirectPlayer` | Credit enrolled players' direct damage when true. |
| `siegeLeague.creditActivePal` | Credit damage from an enrolled player's active/ridden Pal when true. |
| `siegeLeague.creditBaseWorkers` | Credit a base worker only when its owner is in the event roster; false by default. |
| `schedules` | Array of schedule objects described above; an empty array disables recurrence. |
| `operatorUids` | Canonical GUID strings, 8–64 hex/hyphen characters. |

On IMOUTO, do not start the laboratory server with Steam when testing mutation. Use `PalEventDirectorDeployments\Start-PalEventDirectorImouto.ps1`; it reads the build ID from the verified App ID `2394010` Steam manifest and sets `PAL_EVENT_DIRECTOR_SERVER_BUILD_ID` plus `PAL_EVENT_DIRECTOR_DATA_DIR` only in the launched child process. `-ValidateOnly` checks the manifest/deployment match without starting the server. Missing or mismatched launch build IDs fail before a manual countdown is armed.

### Reward obligations

Reward configuration creates durable obligations during resolution, but alpha.3 does not deliver items.

| Key | Rule |
|---|---|
| `rewards.allowedItemIds` | Explicit alphanumeric/underscore item-ID allowlist. |
| `rewards.participation.enabled` | Create a personal obligation at or above the minimum score. |
| `rewards.participation.itemId` / `count` | Allowlisted ID and count 1–1000. |
| `rewards.baseCompletion.enabled` | Create obligations for successful bases where the player meets the minimum. |
| `rewards.baseCompletion.itemId` / `count` | Allowlisted ID and count 1–1000. |
| `rewards.baseCompletion.maxPerPlayer` | 1 through `maxBases`. |
| `rewards.podium` | Unique rank objects for ranks 1, 2, and/or 3; each has an allowlisted `itemId`, count 1–1000, and optional `enabled=false`. |

Standings sort by contribution points, then final hits, qualified targets, and a deterministic occurrence-specific tie value. Final hits never outrank greater contribution.

The delivery gate remains closed because Palworld's native inventory mutation has no idempotency receipt. A crash after the item is added but before the durable result is written cannot prove whether retrying would duplicate a valuable reward. Alpha.3 records the obligation and moves an interrupted grant to operator review rather than guessing.

Community v1.0.3 index candidates for the next progression-aware reward revision are listed below; none enters the build-`24575149` allowlist until exact static-table extraction verifies it:

- Pal Souls: `PalUpgradeStone`, `PalUpgradeStone2`, `PalUpgradeStone3`, and `PalUpgradeStone4`, selected from a snapshotted recipient progression band;
- trust consumables: `AffectionFruit_02` (Little Kinship Peach) and `AffectionFruit_01` (Kinship Peach); no row literally named `TrustHeart` appears in the cited current community indexes;
- one curated schematic for rare podium events, selected from a verified static family at or below the recipient's actual level/unlocked technology rather than synthesizing an item ID; and
- guild/base level only as audit/coarse maturity context until its relationship to technology progression is proven.

The reward ID and progression evidence must be resolved and journaled at event settlement, not recomputed later when delivery occurs. Schematics and full Kinship Peaches must not be multiplied per defended base. Before enabling delivery, build `24575149` still needs static item/recipe verification, exact `EPalItemOperationResult` handling, 64-bit before/after counts, inventory-full tests, offline retry tests, and crash-boundary reconciliation. The explicit IMOUTO activation command therefore leaves `grantItems=false`.
