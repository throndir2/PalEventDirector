# Event definition format

## Goals

The event definition format should let operators and designers create rich events without writing Lua or naming Unreal classes. Definitions are declarative, schema-versioned, bounded, and validated against the capabilities enabled for the current Palworld revision.

The proposed authoring format is JSONC. Comments are useful for private server configuration, while a bundled audited parser can load JSONC after comments are removed safely. Published templates use canonical JSON. A build-time validator produces normalized runtime JSON and a human-readable preview.

## Design rules

- No executable expressions or arbitrary Lua callbacks.
- No arbitrary object, class, function, asset, or property paths.
- IDs come from typed allowlists: existing Pal, NPC, item, incident, zone, sign, or approved modifier.
- Every action names a registered capability adapter.
- Every numeric field has schema and operator-policy bounds.
- Cleanup and downtime behavior are mandatory for mutating events.
- Templates declare resource claims before activation.
- Randomness is seeded and recorded for reproducibility.
- Template upgrades never mutate an already-running occurrence implicitly.

## Top-level model

| Field | Purpose |
|---|---|
| `schemaVersion` | Definition schema version. |
| `id` | Stable alphanumeric/dotted template identity. |
| `version` | Human-readable template revision. |
| `name` / `description` | Player-facing text with strict size limits. |
| `tags` | Catalog and policy classification. |
| `compatibility` | Required capabilities, evidence floor, and allowed platforms. |
| `parameters` | Typed values selected when an occurrence is scheduled. |
| `schedule` | Optional recurrence or game-time trigger. |
| `eligibility` | Player, guild, progression, online-count, and cooldown rules. |
| `participation` | Forced world event, automatic, opt-in, guild, team, draft, zone, or solo-attempt behavior. |
| `resources` | Shared-system claims and spawn/message budgets. |
| `phases` | Announcement, registration, warm-up, active, grace, resolution, reward, cleanup. |
| `objectives` | Normalized signals/state samples and scoring rules. |
| `actions` | Phase, trigger, interval, threshold, and completion actions. |
| `rewards` | Participation, tier, placement, global, or staff awards. |
| `fallbacks` | Approved degradation when optional capabilities are unavailable. |
| `recovery` | Restart, downtime, abort, and uncertain-action behavior. |
| `safety` | Per-template limits below global policy ceilings. |
| `presentation` | Announcement cadence, commands, sign leases, and leaderboard size. |

## Illustrative definition

This is a design example, not a currently runnable configuration.

```jsonc
{
  "schemaVersion": 1,
  "id": "ped.weekly.meteorSafari",
  "version": "1.0.0",
  "name": "Meteor Safari",
  "description": "Chase the impact, capture spotlight Pals, then defeat the guardian wave.",
  "tags": ["weekly", "cooperative", "capture", "combat"],

  "compatibility": {
    "required": [
      "messaging.public",
      "messaging.private",
      "players.roster",
      "observations.capture",
      "characters.spawnExisting",
      "incidents.meteor",
      "rewards.itemExisting"
    ],
    "minimumEvidence": "confirmed",
    "vanillaClientsRequired": true
  },

  "parameters": {
    "spotlightPal": { "type": "palId", "default": "SheepBall" },
    "captureGoal": { "type": "integer", "default": 20, "min": 5, "max": 100 },
    "guardianLevel": { "type": "integer", "default": 40, "min": 1, "maxPolicy": "spawnLevel" }
  },

  "schedule": {
    "timezone": "operatorDefault",
    "rrule": "FREQ=WEEKLY;BYDAY=SA;BYHOUR=19;BYMINUTE=0",
    "duration": "PT90M",
    "missed": "skip",
    "minimumOnline": 2,
    "delayForPlayers": "PT15M"
  },

  "participation": {
    "mode": "automaticOnContribution",
    "lateJoin": "allowed",
    "disconnect": "retainScore",
    "grouping": "serverCooperative"
  },

  "resources": {
    "claims": [
      { "key": "incident.supply", "mode": "exclusive" },
      { "key": "zone:meteorSafari", "mode": "exclusive" }
    ],
    "budgets": {
      "spawnAlive": 12,
      "spawnTotal": 30,
      "announcementsPerMinute": 1,
      "gameThreadJobsPerCycle": 4
    }
  },

  "phases": {
    "announce": { "startsBefore": "PT30M", "repeat": ["PT30M", "PT10M", "PT1M"] },
    "active": { "duration": "PT75M" },
    "grace": { "duration": "PT2M" },
    "cleanup": { "timeout": "PT10M" }
  },

  "objectives": [
    {
      "id": "captures",
      "type": "count",
      "signal": "pal.captured",
      "where": { "palId": "$spotlightPal", "source": "wild" },
      "credit": "capturingPlayer",
      "target": "$captureGoal",
      "scope": "global",
      "dedupe": ["captureInstanceId"]
    },
    {
      "id": "guardians",
      "type": "count",
      "signal": "character.defeated",
      "where": { "spawnOwner": "$occurrenceId", "wave": "guardian" },
      "credit": "participantsInZone",
      "target": 3,
      "scope": "global",
      "lockedUntil": { "objectiveComplete": "captures" }
    }
  ],

  "actions": [
    {
      "id": "startMeteor",
      "when": { "phaseEnter": "active" },
      "use": "incidents.startMeteor",
      "args": { "target": "eligibleOnlinePlayer", "selection": "seededRandom" },
      "required": true
    },
    {
      "id": "guardianWave",
      "when": { "objectiveComplete": "captures" },
      "use": "characters.spawnWave",
      "args": {
        "profile": "guardianTrio",
        "level": "$guardianLevel",
        "location": "zone:meteorSafari",
        "expiry": "PT20M"
      },
      "required": true
    }
  ],

  "rewards": [
    {
      "id": "participation",
      "when": { "minimumContribution": 1 },
      "grant": [{ "type": "item", "id": "PalSphere_Mega", "count": 5 }],
      "delivery": "onlineOrPending"
    },
    {
      "id": "completion",
      "when": { "allObjectivesComplete": true },
      "recipients": "contributors",
      "grant": [{ "type": "experience", "amount": 2500 }],
      "delivery": "onlineOrPending"
    }
  ],

  "presentation": {
    "commands": ["event", "score", "leaderboard"],
    "leaderboardSize": 10,
    "signLease": "weeklyEventBoard",
    "progressAnnouncements": [0.25, 0.5, 0.75, 1.0]
  },

  "recovery": {
    "restartDuringActive": "resumeIfBeforeDeadline",
    "restartAfterDeadline": "resolveFromJournal",
    "mandatoryActionFailure": "abortAndCleanup",
    "uncertainReward": "operatorReview",
    "missedCleanup": "blockConflictingEvents"
  },

  "safety": {
    "abortBelowServerFps": 20,
    "pauseSpawnsBelowServerFps": 30,
    "maximumRuntime": "PT2H",
    "saveImpact": "transientPlusRewards"
  }
}
```

## Parameters

Supported parameter types are intentionally finite:

- `boolean`, `integer`, `number`, `string`, `duration`;
- `palId`, `npcId`, `itemId`, `incidentId`, `invasionProfileId`, `modifierId`;
- `invasionLevelPolicy` with only the registered modes and bounds described below;
- `zoneId`, `signId`, `spawnProfileId`, `rewardTableId`;
- bounded arrays and weighted choices of those types.

A parameter can define default, minimum, maximum, allowed set, policy-derived maximum, and whether an operator must supply it. Substitution uses exact `$parameterName` tokens; it is not a general expression language.

## Schedules

### Wall clock

Use an RFC 5545-like recurrence rule plus an IANA timezone configured by the operator. The normalized occurrence stores UTC instants, timezone identity, and the offset used when generated. Daylight-saving transitions use an explicit policy:

- nonexistent local time: skip or move forward;
- repeated local time: first, second, or once-by-date.

### Game clock

Templates may trigger on:

- game hour/minute;
- sunrise/night transition;
- every N in-game days;
- span after a prior game-time event.

A game-time trigger must specify behavior when time is jumped by an administrator or another leased event.

### Conditional/manual

Conditions may require online count, server health, no conflicting event, campaign state, or an operator/vote command. The scheduler reevaluates at bounded intervals.

### Missed occurrences

- `skip` — archive as missed.
- `startLateWithin` — start only inside a configured tolerance.
- `summarize` — do not play; emit one optional summary.
- `rescheduleNextWindow` — choose the next allowed deterministic window.
- `resume` — only for the same durable occurrence that was already active.

## Phases

Standard phase names are fixed so recovery and tooling understand them. A template may omit registration or grace but may not omit cleanup for a mutating event.

Each phase supports:

- duration/deadline;
- entry/exit messages;
- entry/exit actions;
- subscriptions/objectives active in that phase;
- commands;
- success, timeout, insufficient-player, and failure transitions.

## Signals

Planned normalized signal families:

- `player.joined`, `player.left`, `player.died`, `player.teleported`;
- `chat.command`, `chat.message`;
- `pal.captured`, `pal.defeated`, `pal.spawned`, `pal.fished`;
- `npc.defeated`, `npc.talked`, `npc.traded`;
- `item.gathered`, `item.pickedUp`, `item.crafted`, `item.granted`;
- `build.completed`, `base.created`, `base.removed`, `work.completed`;
- `zone.entered`, `zone.exited`, `zone.held`, `checkpoint.reached`;
- `stage.entered`, `dungeon.completed`, `boss.completed`;
- `raid.started`, `raid.finished`, `invasion.wave`, `oilrig.completed`, `arena.finished`;
- `world.hour`, `world.dayStarted`, `world.nightStarted`;
- `event.phase`, `objective.progress`, `objective.completed`;
- `server.healthChanged`, `operator.command`.

Only signals backed by released adapters are legal in an enabled template.

## Filters and conditions

Filters use typed equality, membership, range, ownership, and spatial predicates. Examples:

- species belongs to an existing element/allowlist group;
- item belongs to an approved resource set;
- actor was spawned by this occurrence;
- player is registered and inside a zone;
- capture source is wild rather than an admin spawn;
- stage identity matches a configured dungeon family;
- server FPS remains above a policy threshold.

No regular expression is applied to unbounded game text in a hot path. Chat matching uses normalized bounded tokens or anchored short patterns.

## Objective operators

| Operator | Result |
|---|---|
| `count` | Count valid deduplicated signals. |
| `sum` | Sum a bounded numeric signal field. |
| `distinct` | Count unique allowlisted IDs. |
| `best` | Highest/lowest valid single value. |
| `firstTo` | First subject reaching a threshold. |
| `streak` | Consecutive valid actions under reset rules. |
| `timer` | Elapsed time between explicit start/end signals. |
| `orderedCheckpoints` | Validate a route in sequence. |
| `occupancy` | Accumulate authoritative zone-hold duration. |
| `survival` | Remain eligible/alive for a duration. |
| `bracket` | Advance deterministic head-to-head rounds. |
| `all` / `any` | Compose child objectives. |
| `stage` | Unlock the next objective after completion. |

Every objective defines scope (`player`, `team`, `guild`, `global`), credit rule, deduplication, target, tie behavior, and late/reconnect semantics.

## Actions

Action timing can be:

- phase enter/exit;
- elapsed offset;
- fixed bounded interval;
- normalized signal;
- objective threshold/completion;
- vote result;
- operator confirmation;
- health degradation/recovery.

Action categories include messaging, sign text, reward obligation, spawn wave, despawn owned actors, incident/invasion start, exact stock invasion-group start, all-base invasion start, pre-spawn invasion-member substitution, time/modifier lease, teleport, heal/revive, score adjustment, phase transition, sidecar notification, and save request.

An action declares whether it is mandatory, retryable, idempotent, compensatable, and allowed to fall back.

### Invasion level policies

An invasion composition transform must choose one explicit level policy. It cannot evaluate an arbitrary expression:

| Mode | Meaning | Initial release status |
|---|---|---|
| `native` | Keep each final level selected by Palworld for that particular target base. | Preferred first release. |
| `fixed` | Replace every transformed member's final level with one bounded configured value. | Supported only after boundary-level spawn tests. |
| `relative` | Add a signed bounded offset to each native final level, then clamp to global and profile limits. | Supported after native baseline logging is proven. |
| `workerDerived` | Snapshot assigned Work-Pal levels for the target base, apply one named and versioned project statistic, then clamp. | Experimental until the native aggregation is measured or a deliberately different formula is approved. |

`native` does not mean “make the bounty equal to a worker.” Palworld 1.0 says assigned Work-Pal levels drive raid scaling, while current data shows a grade-and-row pipeline that yields a concrete level range. The definition records both the native level and effective level for every transformed member so previews, recovery, and audits can explain the result.

Illustrative composition fragment:

```jsonc
{
  "composition": {
    "mode": "replaceSelectedMembers",
    "profile": "bounty.mixedByGrade",
    "levelPolicy": {
      "mode": "native"
    }
  }
}
```

A `fixed` policy requires `level`; a `relative` policy requires `offset`, `minimum`, and `maximum`; a `workerDerived` policy requires an allowlisted `statistic`, empty-base behavior, snapshot boundary, minimum, and maximum. Global policy may further lower every maximum.

## Rewards

Reward selectors:

- all eligible participants;
- contributors above a threshold;
- placement/rank band;
- winning team or guild;
- personal milestone;
- seeded raffle among eligible contributors;
- staff-judged allowlist;
- server-wide completion award.

Reward types are adapter-backed and allowlisted. Definitions cannot issue arbitrary console commands. Global operator policy caps reward value, frequency, and per-player accumulation regardless of template values.

## Resource claims and overlap

Definitions statically declare shared resources. The validator rejects missing claims when an action requires one. Examples:

- `world.clock` for fixed-time events;
- `setting:ExpRate` for an XP lease;
- `incident.supply` for meteor/supply events;
- `invasion` and `base:<id>` for base defense;
- `invasion:allBases` for one mandatory server-wide siege occurrence;
- `spawn.global` plus a zone for waves;
- `player:<uid>:movement` acquired dynamically for an opt-in race reset;
- `sign:<id>` for an event board.

The calendar preview displays conflicts before deployment. Runtime acquisition is still authoritative because dynamic targets can differ.

## Safety policy

Template limits can only reduce global ceilings. Proposed ceilings include:

- alive and total spawn counts;
- maximum spawn level and rarity;
- minimum spawn distance from bases/players and restricted areas;
- messages per minute and maximum text length;
- teleport count/cooldown;
- rewards per occurrence/day/player;
- polling interval and tracked-zone count;
- game-thread jobs per cycle;
- event duration and retries;
- minimum FPS / maximum frame time.

## Fallbacks

A fallback explicitly maps an unavailable optional capability to another approved behavior. For example:

```json
{
  "whenUnavailable": "incidents.meteor",
  "replaceActions": ["announceNaturalSafari"],
  "disableObjectives": ["reachImpactZone"],
  "requiredCapabilities": ["observations.capture"]
}
```

Fallbacks are validated like normal definitions. There is no automatic best-effort substitution.

## Validation stages

1. Parse and schema validation.
2. Canonical ID and version validation.
3. Parameter type/bound validation.
4. Capability existence and evidence-floor validation.
5. Vanilla-client policy validation.
6. Action-to-resource-claim validation.
7. Cleanup and recovery completeness.
8. Reward and spawn policy ceilings.
9. Static overlap/calendar analysis.
10. Deterministic simulation with a recorded seed.
11. Operator preview and explicit enablement.

## Simulation

The simulator feeds synthetic normalized signals and time changes into the generic core. It verifies:

- phase transitions;
- deduplication;
- objective/scoring results;
- tie behavior;
- reward obligation count;
- claims and cleanup;
- restart replay at every journal record;
- missed schedules;
- fallback paths;
- bounded action volume.

Simulation proves orchestration logic, not engine compatibility. Adapter integration tests remain separate.

## Template versioning

- `id` remains stable for the conceptual template.
- `version` changes whenever behavior or defaults change.
- A scheduled occurrence captures an immutable normalized definition and parameters.
- Updating a template affects only future occurrences unless an operator performs a validated migration.
- Archived seasons retain definition digest and random seed.

## Community templates

Future imported templates are treated as untrusted data. They must pass the same schema, capability, bounds, and vanilla-policy checks. A template cannot bring scripts, native files, paks, assets, or dependencies. This permits creative sharing without turning event definitions into a code-execution channel.
