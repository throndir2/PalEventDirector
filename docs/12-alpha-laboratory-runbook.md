# Alpha laboratory runbook

## Scope

Version `0.1.0-alpha.1` is a runnable, fail-closed UE4SS Lua laboratory build. It is not authorized for the production world. The purpose of this release is to prove current Palworld hook signatures and native invasion behavior without requiring client files.

## Implemented

- Official-loader `Info.json` with one server-only Lua rule and an explicit `UE4SS` dependency.
- Persistent validated JSON configuration outside the managed package.
- Checksummed append-only journal and atomic snapshot/backup writes.
- Siege League lifecycle with an all-base native start adapter.
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
- `grantItems=false`

`grantItems=true` is rejected by the alpha configuration validator. Reward obligation creation and transaction tests exist, but live delivery remains blocked until journal replay and every crash boundary are proven against a copied world.

This alpha also does not yet substitute bounty characters, alter levels, schedule recurring events, privately message players, or stop native invasions. `abort` stops director scoring and leaves Palworld's native incidents to their normal lifecycle.

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

Enable `startAllInvasions` only while `observeCombat` and `observeInvasions` remain enabled. Keep `grantItems=false`.

The process environment must also set `PAL_EVENT_DIRECTOR_SERVER_BUILD_ID` to the exact Steam dedicated-server build ID in the configured allowlist. For this inspected build that value is `24575149`. An absent or changed value blocks mutation.

Start through `ped start`, then verify:

- every technically eligible base receives one classified attempted outcome;
- players can move between all active bases and score at each;
- each native group GUID belongs only to this occurrence;
- natural/overlapping incidents never enter the event;
- one target's eligible plus uncredited damage never exceeds its immutable health budget;
- final hits require attack death and never duplicate;
- standings show cross-base count and aggregate contribution;
- completion creates pending personal, per-successful-base, and podium reward obligations exactly once;
- `ped abort` never destroys an unknown/native actor;
- restart during active scoring enters recovery-required instead of starting another siege.

## Gate 5: rewards and bounty substitution

Not available in `alpha.1`. The next release must add and prove:

- replayable reward state transitions anchored to the journal;
- full/partial inventory behavior and exact `EPalItemOperationResult` handling;
- crash injection before intent, after intent, during grant, after grant, and before result checkpoint;
- login retry and operator-review resolution;
- current item-row allowlist verification;
- bounty-member substitution, capture behavior, native drops, wave completion, level policy, and vanilla-client compatibility.

## Failure response

- Disable the affected capability in persistent configuration.
- Use `ped abort` if director scoring is active.
- Let native invasions finish; this alpha never force-cleans them.
- Gracefully save and stop through the established server-management scripts.
- Preserve logs, journal, snapshot, exact package, UE4SS version, server build ID, and world backup.
- Do not enable the next gate until the source fix is validated, committed, pushed, rebuilt, and retested.
