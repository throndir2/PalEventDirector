# Alpha.3 administration and scheduling

## Scope and safety

Alpha.3 is a laboratory-only release. Its mutation preflight rejects any mode other than `laboratory`, and every capability is disabled in the generated configuration. It never requires a client mod: players connect with normal vanilla clients and use ordinary Palworld chat and server notices.

The persistent configuration is `Pal/Saved/PalEventDirector/config.json` below the dedicated-server root, or the directory selected by `PAL_EVENT_DIRECTOR_DATA_DIR`. It is strict JSON, not JSONC. Stop the laboratory server before editing it and restart after every edit; configuration is loaded only at mod startup.

Schema 3 intentionally has no migration from earlier alpha configurations or state. Archive the complete `Pal/Saved/PalEventDirector` directory before an upgrade, start once to generate a safe schema-3 configuration, stop, and reapply reviewed values. Never copy the Production event-state directory into DEV.

## Event boundary

A start is mandatory for the eligible target set; it is not a consent vote. At the start boundary the adapter:

1. snapshots every valid online player controller;
2. resolves every online player UID to a native guild ID, failing the whole start if any lookup is uncertain;
3. selects only available, idle invasion observers whose base belongs to one of those online guilds;
4. rejects the start if any native invasion/visitor slot, eligible observer, required reflected function, runtime version, or configured bound is unsafe;
5. enrolls the same online-player snapshot in one server-wide leaderboard, regardless of guild; and
6. issues one selected-base native request per eligible base.

A guild with no online member at that boundary is not attacked. Every online player is enrolled even if that player's guild has no selected base. Players who join while the event is active are enrolled globally on the next poll and before their first accepted score record. An attribution that cannot be tied to an enrolled online player consumes the target's damage budget but receives no score or final hit.

The start API returns no success value. A base is considered started only after a matching native lifecycle callback. Synchronous call failures, missing callbacks, composition failures, timeouts, and completions remain separate per-base outcomes.

## Mandatory warnings

Every external start uses a countdown. There is no `start-now` command.

- Manual starts accept an integer from 10 through 60 minutes and always announce at 10, 5, and 1 minute.
- Daily and weekly schedules must contain warning offsets `600`, `300`, and `60` seconds. Extra offsets are allowed.
- The poll interval is limited to 250–5000 ms. A failed announcement is retried only inside a small poll-derived delivery window.
- If any configured warning cannot be durably recorded and broadcast near its required boundary, that occurrence is marked missed and does not mutate Palworld.
- `lateStartToleranceSeconds` permits a previously warned occurrence to start slightly late; it never excuses a missing warning.

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

## Chat commands

Chat handling is available only when `capabilities.chatCommands=true`. Queries are rate-limited per player and globally to avoid announcement spam.

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
| `!siege start <profile> [minutes]` | Arms a 10–60-minute warning countdown when policy permits. Omitted minutes use `manualCountdownMinutes`. |

`chatStartPolicy=operatorOnly` permits only UIDs listed in `operatorUids`. `chatStartPolicy=anyUser` permits any player to request an allowed profile, subject to the persistent global `userStartCooldownSeconds` and all ordinary safety checks. Display names never authorize a command.

Operator-only chat forms:

| Command | Result |
|---|---|
| `!siege cancel` | Cancels one planned manual countdown; it does not cancel recurrence or a native invasion. |
| `!siege resolve` | Resolves a starting, active, or recovery event and creates score/reward obligations. |
| `!siege abort` | Stops director scoring/tracking; native Palworld incidents continue normally. |
| `!siege reset` | Returns completed/aborted/recovery state to idle only when no native invasion is active. |
| `!ped <operator command>` | Runs the corresponding console command below after UID authorization. |

Unknown commands print the bounded help form. Chat has a two-second per-UID command limit, public queries share a five-second announcement limit, and start attempts have an additional ten-second process-local limit.

## Server-console commands

The UE4SS global console prefix is `ped`:

| Command | Result |
|---|---|
| `ped start [profile] [minutes]` | Arms the mandatory manual countdown. The configured default profile and countdown are used when omitted. |
| `ped cancel` | Cancels a planned manual countdown. |
| `ped status` | Displays director status. |
| `ped profiles` | Lists enabled profiles. |
| `ped schedule` | Lists upcoming starts in local time. |
| `ped leaderboard` | Displays global standings. |
| `ped resolve` | Resolves the current event. |
| `ped abort` | Stops director scoring without destroying native actors. |
| `ped reset` | Clears a terminal/recovery director state after native incidents finish. |
| `ped rewards` | Processes pending grants only when `grantItems` is available. Alpha.3 validation requires `grantItems=false`, so this command fails closed. |

There is intentionally no immediate-start command and no command that force-stops an unknown native invasion.

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
| `limits.maxAnnouncementLength` | 40–1000 bytes after sanitization. |
| `siegeLeague.name` | Event label. |
| `siegeLeague.defaultProfile` | Canonical enabled profile used when omitted. |
| `siegeLeague.allowedProfiles` | Array of unique canonical profile IDs. Arbitrary character IDs/functions are never accepted. |
| `siegeLeague.chatStartPolicy` | `operatorOnly` or `anyUser`. |
| `siegeLeague.userStartCooldownSeconds` | 60–604800, global and persistent for non-operator starts. |
| `siegeLeague.manualCountdownMinutes` | 10–60. |
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
