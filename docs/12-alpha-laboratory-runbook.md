# Alpha laboratory runbook

## Scope

Version `0.1.0-alpha.2` is a runnable, fail-closed UE4SS Lua laboratory build. It is not authorized for the production world. The purpose of this release is to prove current Palworld hook signatures, native invasion behavior, chat authorization, and bounty-member substitution without requiring client files.

## Implemented

- Official-loader `Info.json` with one server-only Lua rule and an explicit `UE4SS` dependency.
- Persistent validated JSON configuration outside the managed package.
- Checksummed append-only journal and atomic snapshot/backup writes.
- Siege League lifecycle with an all-base native start adapter.
- Admin or cooldown-bound user activation through `!siege start <profile>` after chat validation.
- Seven fixed composition profiles, including `all-bounty`, which attempts to replace every intercepted native member while cycling the complete audited 34-ID bounty catalog across the event.
- Cross-base roaming: a player may defend every event base and accumulate contribution, final hits, base count, participation, and per-successful-base reward obligations.
- Target-budgeted contribution with direct-player, active-Pal, optional base-worker, uncredited-damage, overkill, duplicate, and final-hit accounting.
- Deterministic standings and exactly-once reward-obligation identities.
- Public server notices, bounded console controls, and optional rate-limited chat queries.
- Deterministic package build and pure-Lua simulation tests.

## Deliberately disabled

The generated default has every Palworld observation/mutation switch off:

- `observeCombat=false`
- `observeInvasions=false`
- `chatCommands=false`
- `startAllInvasions=false`
- `substituteBountyMembers=false`
- `grantItems=false`

`grantItems=true` is rejected by the alpha configuration validator. Reward obligation creation and transaction tests exist, but live delivery remains blocked until journal replay and every crash boundary are proven against a copied world.

This alpha implements but does not enable bounty substitution. It does not yet alter levels, schedule recurring events, privately message players, or stop native invasions. `abort` stops director scoring and leaves Palworld's native incidents to their normal lifecycle.

## Chat authorization and profiles

After the chat hook passes Gate 2, set `chatCommands=true` and add canonical player GUIDs to `operatorUids`. The default `chatStartPolicy` is `operatorOnly`; an operator can run:

`!siege start all-bounty`

Setting `chatStartPolicy` to `anyUser` lets any user run the same allowlisted command, but `userStartCooldownSeconds` applies globally and active/recovery/native-concurrency guards still fail closed. User text can select only IDs in `allowedProfiles`; it cannot name an Unreal path, character ID, item, or arbitrary function.

Recommended profile cadence:

- `all-bounty` — flagship special event; every attacker is a bounty target and the full roster rotates globally;
- `patrol` — frequent, lower-token alarm;
- `mixed` — safest first substitution probe: one bounty leader and native escorts;
- `most-wanted` — harder mid/high-token event;
- `kingpin` — rare all-Ram spectacle with a severe token-economy multiplier;
- `jackpot` — explicit rare economy event using only four/five-token targets;
- `native` — control run with no substitution.

`all-bounty` does not resize native arrays. It attempts to replace every member in each intercepted Palworld selection. If live call timing and initialization match the reflected contract, the complete 34-ID catalog is attempted once the event supplies at least 34 concrete member slots; smaller events use a deterministic subset and continue the rotation. Actual spawned IDs, drops, capture, and wave behavior remain live gates.

The transform remains armed for repeated or asynchronous selections until the occurrence ends. It acts only on enemy incidents whose base was in the pre-start observer snapshot; once a base accepts a native group GUID, later selections and damage must match that same group. Visitor selections and groups from unrelated incidents are ignored.

Alpha.2 uses configuration schema 2 and intentionally rejects schema 1. Before upgrading, stop the laboratory server, rename the alpha.1 `config.json` to a timestamped audit backup, start alpha.2 once to create a fresh fail-closed schema-2 file, stop it, then reapply reviewed values explicitly.

## Native concurrency conclusion

Current reflected structures strongly indicate **one native invader-family incident per base**: `UPalInvaderManager.Incidents` maps one camp GUID to one incident, and each base observer has scalar invading/path-search flags. Different bases are structurally capable of one concurrent incident each. One global declaration/wave-info pointer makes normal simultaneous declarations uncertain.

The alpha therefore refuses to start if any native invasion/visitor incident is already executing. `StartInvaderMarchAll()` remains a focused test: it may fan out per-base incidents concurrently, serialize them, or reject some native states. Runtime evidence decides which claim can ship.

## Gate 1: clean boot

1. Use a disposable copied world and verified backup.
2. Install exactly one compatible `UE4SS` package and this package through the official loader.
3. Leave all capabilities off.
4. Restart and verify one `Pal Event Director loaded` record.
5. Verify persistent files are under `Pal/Saved/PalEventDirector`, not under managed `Scripts`.
6. Verify an unmodified remote client connects.
7. Restart twice and verify hooks/timers do not multiply.

## Gate 2: observation only

Enable `diagnostics.observationProbe`, `observeInvasions`, and then `observeCombat`; leave both mutations off. The probe logs primitive payload summaries while no director event is open and does not scan invasion membership. Use `diagnostics.traceHooks` only for a short focused cardinality trace.

Verify:

- hooks register once and emit bounded traces;
- a natural invasion reports non-empty target base and group GUIDs;
- only native invasion members enter scoring context;
- one accepted hit produces one damage record;
- death arrives after damage and closes the same target once;
- `ActualDamage`, maximum HP, shields, overkill, environmental deaths, active/ridden Pals, worker Pals, projectiles, explosions, and status effects match the documented policy;
- idle combat does not scan or retain world actors;
- vanilla clients see no missing content or behavioral desynchronization.

If any identity, cardinality, or ordering differs, disable the capability and update the adapter plus fixtures before proceeding.

## Gate 3: native concurrency

With three widely separated eligible bases, test and record:

1. second request to the same base during declaration, path search, and active wave;
2. base A active followed by base B start;
3. `StartInvaderMarchAll()` with A/B/C idle;
4. enemy versus visitor occupancy at the same base and different bases;
5. victory, timeout, cancellation, path failure, restart, and base removal cleanup.

Expected safety policy is at most one invader-family incident per camp. Do not interpret a `void` start call as success; group-correlated lifecycle callbacks are authoritative.

## Gate 4: all-base Siege League mutation

Enable `startAllInvasions` and `substituteBountyMembers` only while `observeCombat` and `observeInvasions` remain enabled. Keep `grantItems=false`.

The process environment must also set `PAL_EVENT_DIRECTOR_SERVER_BUILD_ID` to the exact Steam dedicated-server build ID in the configured allowlist. For this inspected build that value is `24575149`. An absent or changed value blocks mutation.

Start the lowest-risk replacement through `ped start mixed`, then test `ped start all-bounty`. After chat validation, repeat as an operator with `!siege start all-bounty`, and optionally repeat under the any-user cooldown policy. Verify:

- every technically eligible base receives one classified attempted outcome;
- every concrete member in `all-bounty` has an audited `BOSS_*` ID while retaining Palworld's native level and companion fields;
- `mixed` changes exactly one concrete member per native selection;
- unauthorized users cannot start under `operatorOnly`, while `anyUser` starts once and then observes the durable global cooldown;
- players can move between all active bases and score at each;
- each native group GUID belongs only to this occurrence;
- natural/overlapping incidents never enter the event;
- one target's eligible plus uncredited damage never exceeds its immutable health budget;
- final hits require attack death and never duplicate;
- standings show cross-base count and aggregate contribution;
- completion creates pending personal, per-successful-base, and podium reward obligations exactly once;
- `ped abort` never destroys an unknown/native actor;
- restart during active scoring enters recovery-required instead of starting another siege.

## Gate 5: rewards and bounty outcomes

Not available in `alpha.2`. The next release must add and prove:

- replayable reward state transitions anchored to the journal;
- full/partial inventory behavior and exact `EPalItemOperationResult` handling;
- crash injection before intent, after intent, during grant, after grant, and before result checkpoint;
- login retry and operator-review resolution;
- current item-row allowlist verification;
- capture behavior, native bounty drops, wave completion, level policy, and vanilla-client compatibility for each enabled composition profile.

## Failure response

- Disable the affected capability in persistent configuration.
- Use `ped abort` if director scoring is active.
- Let native invasions finish; this alpha never force-cleans them.
- Gracefully save and stop through the established server-management scripts.
- Preserve logs, journal, snapshot, exact package, UE4SS version, server build ID, and world backup.
- Do not enable the next gate until the source fix is validated, committed, pushed, rebuilt, and retested.
