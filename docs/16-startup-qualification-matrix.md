# Server-side interest and efficient operator qualification

## Goal and current boundary

Remove human timing from engine qualification where possible. A server-side interest experiment must use a qualified native source and natural game policy, not a fake login, a forged player/admin identity, or forced collision flags. It is not evidence of client replication.

The build-25080279 investigation found **no qualified, bounded, identity-free simulation-interest source** in the inspected native and cooked Blueprint surfaces. This is a qualification refusal, not a failed live simulation experiment or a claim that all headless approaches are inherently impossible. No proposed interest mutator was invoked. The existing streaming/nav helper and the separate one-NPC AI cadence lease remain the only implemented headless interventions.

The human-readable target is the **high Sunreach base**, currently saved-base ordinal **3**. Give the operator its map coordinates in the private run handoff rather than publishing saved-world locations here. Stand on its actual platform, not the ground below. The ordinal is an exact registry selection for this disposable world, not a permanent in-game base name.

## Server-side route: evidence and decision

The current cooked game instance selects `BP_PalCharacterImportanceManager_C`. That Blueprint adds no functions, bytecode or property overrides to the native manager. Both the native distance/sight classifier and the separate nearest-NPC calculation consume registered `APalPlayerCharacter` sources. Generic actors, standalone controllers, WorldPartition sources and base-camp locations are not inputs to those character-importance calculations.

| Candidate | Current Shipping implementation | Decision |
|---|---|---|
| `PalUtility.Editor_AddCharacterToImportanceManager` | Its reflected entry consumes the parameter and calls a return-only native body | Do not call it as a supposed source |
| `PalCheatManager.BotOn`, `BotOff`, `SetDummyPlayerList` | Reflected names remain, but their shipped native bodies are no-ops | Do not manufacture a passing bot experiment |
| `PalStreamingSourceActor` | A genuine WorldPartition provider with paired registration/removal | Useful for streaming, not a character simulation-interest replacement |
| `PalOptiTestCharacter` / controller / game mode | Thin engine base-class construction; no player-source enrollment | Not a substitute for registered player lifecycle |
| Standalone spectator/view target | The classifier consults the special view only after a registered player source exists | Does not supply independent enrollment |
| Significance-manager viewpoints / collector base locations | Separate map-object/spawner pipelines | No qualified bridge to character importance |

Normal player BeginPlay/EndPlay adds/removes the exact player pointer, but that is not a safe certificate for spawning an anonymous full player. The inspected manager exposes four read-only output-array functions, not a radius-limited, token-owned register/unregister API. Direct source-list edits, fake identities, global policy overrides and raw native-address calls remain outside this experiment.

Removal also means eventual **stock recomputation**, not immediate restoration of an old snapshot. Collector publication and batched manager updates introduce lag. Other players, changed entities and existing importance-disable reasons can alter the result. Do not force manager indices, maps, timers or resets to obtain a desired tier.

Private primary evidence is retained in `server-interest-25080279/qualification.json` and its hash-linked native/Blueprint records. The qualification digest is `5f915500f38b4afbda4725d0d5dfc1750c93eba153c64e98cc2c151627e6a1da`; evidence-manifest digest is `768554117bd706eed93ff5bd26abc16ff553b857e615909217ef171d05760834`. No game calls, hooks or simulation changes were performed by that investigation.

## Evidence already available

| Observation | What it establishes | What it does not establish |
|---|---|---|
| Owned streaming/nav helper, real floor/nav queries and two same-instance shape matches | Bounded headless placement can reach real engine geometry | Player-equivalent interest, every base or every bounty class |
| AI interval 10 -> 0.1 with delivered action deltas near 0.1, stock shots and reloads | The AI clock intervention works | Movement cadence, bullet contact or outgoing damage |
| Movement active, primary interval 0, cached interval 10 | Primary tick interval alone misses the effective movement policy | That movement is disabled or that SetActiveAI is the fix |
| Real stock bullets; selected defender's eight damage parts use Overlap but have overlap notifications off | A sampled headless target contact gate is closed | That every missed shot or every death has this cause |
| Player detected inside Sunreach; 30 same-world water actors including an alternate stock mesh | Real presence loads a different cohort; the base was correctly identified | Successful player-present combat |
| Exact Sunreach mesh's cooked triangles and simple-query compatibility qualified offline | Narrow support for that mesh is justified under its stock source/stability contract | Live success of the new source checks after a player reconnects |
| Restored cadence and verified owned cleanup in completed runs | Those particular runs settled normally | Permission to clear an interrupted run or replay cleanup |

`SetDisableTickOptimization` is not a faithful movement rollback for the observed Cache10/Reserve0 state. `SetActiveAI`, importance freeze flags and `ResetTickInterval` are not substitutes for a qualified interest source. Do not combine those interventions simply to obtain a passing result.

## Hypotheses and discriminating tests

Use one treatment change at a time. A run that fails placement cannot answer a combat hypothesis. A native fault or missing after-marker ends the campaign on that artifact; never advance to another case as a workaround.

| ID | Hypothesis | Test and evidence | Interpretation / operator cost |
|---|---|---|---|
| I1 | Missing player-derived interest, rather than missing initialization, causes sparse simulation and closed damage shapes | Compare the existing headless baseline with one legitimate, non-spectating player close to both the owned NPC and actual defender; keep PED controls unchanged | The synthetic-source variant is BLOCKED by the native findings above. Actual tier/period/overlap changes are the witness, not simply a controller or login |
| I2 | A streaming source is not consumed by character importance | Keep the existing streaming/nav helper constant in the headless and player-present controls | The two native importance input paths exclude that provider. Runtime streaming readiness must not be reported as player-equivalent simulation |
| W1 | Player-loaded Sunreach water geometry was the placement blocker | In the first player-present control, collect water cohort/source identities, body policy, stable bounds and the full dry-placement result before any NPC | New mesh admitted with all safeguards intact closes this particular blocker. Another unsupported water shape remains BLOCKED. Same login as M1/C1 |
| M1 | Real presence changes the effective movement policy that the AI-only lease leaves slow | Record movement active/tick flags, primary/cache/reserve intervals, gravity, last-update displacement and grounded 3D position while the operator remains stationary on the platform | A changed cached period with real motion separates scheduling from floor/path failure. No movement mutation or teleport. Same stationary observation as W1/C1 |
| C1 | Enabling natural near-player interest opens the defender's damage-part overlap gate | At natural shots, record the actual equipped rifle, bullet state, exact target body parts, both collision responses, native hit/applicability observations and accepted outgoing damage | Target gates opening without damage points downstream. Positive outgoing damage to an exact-base character is required for combat PASS. Operator does not attack |
| C2 | Early creation snapshots or exhausted contact samples hide later valid bullet behavior | Distinguish creation-time initialization from later natural hit callbacks; retain current sample caps and report when capped | Creation-time collision-off is not a later-lifetime failure. Three unscoped contacts do not prove absence of later target hits. A separate bounded sampling change is needed before testing that theory; do not retain pooled bullet pointers casually |
| V1 | Camera direction affects Mid/Far importance independently of distance | Only if the close control is inconclusive, use a separate safe fixed-position comparison: ordinary camera toward the subjects, then away, with unchanged PED settings | Native sight uses a direction dot product greater than float32 0.7, not a rendered-frame or LOS test. Skip this inside view-independent Near or when Nearest dominates. Current harness does not automatically sequence this comparison |
| L1 | Losing presence correctly retires participation and settles owned resources | After a successful stationary control, use a separate explicitly selected departure scenario: operator leaves the base once on cue; record exact last presence, generation retirement, restoration and cleanup | Requires one deliberate move and its own planned run. Never leave during the baseline as an unannounced intervention. Not automatically chained or currently selected by the launcher |
| R1 | Server-authoritative actions replicate correctly to an unmodified client | During the same stationary combat control, operator reports whether the NPC appears grounded, moves and visibly attacks; correlate with server evidence | One short observation can expose server/client disagreement. Visual effects alone do not prove damage; interest emulation cannot close this question |
| T1 | The approved normal networked-sphere fence restores/revokes before capture and leaves the captured entity untouched | Only after engine combat and ownership qualify, run a separate capture scenario with one normal sphere on cue, recording the existing synchronous pre-transfer fence and subsequent ownership outcome | Requires explicit readiness for this separate scenario. Never capture during W1/M1/C1; no scripted, legacy or third-party transfers. This does not grant universal capture coverage |
| A1 | Native engine behavior passes, but player/active-Pal attribution or the normal simultaneous all-base backend still fails | After the lab-only gates pass, separately exercise direct player damage, active-Pal damage and simultaneous targets against their event journals | Later integration campaign, not a reason to unlock ordinary `all-bounty` now. Keep request16 recovery separate |

## Make one operator visit answer several questions

The first human block combines **I1, W1, M1, C1 and R1** in one existing player-present `CadencedEngagement` run. The operator only reconnects, goes to the named platform and watches. The agent collects all server-side observations already available; it must not ask the operator to manually execute native diagnostics or approve each routine restart.

**Being somewhere inside the base is not the strongest interest control.** The pinned nearest-NPC collector uses a 1000 cm sphere around each actual source, then collision eligibility and a configured nearest-count selection. If the platform permits it, use a safe point within roughly **8 metres of both the NPC and its defender**. Never move a Pal, teleport an attacker or approach an unsafe edge to force that condition. The distance is an experimental positioning target, not a guarantee of Nearest membership; larger collider bounds, the configured count and other characters matter. When that common point is unavailable, record the limitation rather than silently changing the base or geometry.

Keep the first block adaptive, not a Cartesian product. If it produces natural promotion, enabled target contact and accepted outgoing damage, skip the camera experiment. If promotion occurs without overlap changes, investigate existing policy suppression before another combat run. If overlap changes without damage, prioritize actual hit/applicability and sample-cap evidence rather than another login with the same conditions.

Before arranging a human block, finish the offline/source work, build a clean identifiable artifact, check the prior run's durable disposition, and verify the installed launcher with `-ValidateOnly`. Do not consume an operator visit merely to discover a known parser, signature or packaging problem.

Agree on readiness before starting the finite waiting window. After the agent reports the server ready, ask the operator for one **"on the Sunreach platform"** acknowledgement. If the run is not detecting them, inspect its counts/distance immediately rather than waiting silently for the timeout or assuming the wrong base. Never fabricate presence or extend an already consumed run.

Current waiting mode lasts up to 15 minutes and does not create helpers or NPCs until presence is established. The existing launcher creates a fresh run at process start; live rearming and a multi-scenario campaign runner are **not implemented**. Do not present invented commands or promise multiple mutation scenarios without a restart. If a window expires, record the safe timeout and coordinate a fresh window only when the operator is ready.

The current operator sequence is:

1. Connect to the IMOUTO disposable server on port **8213**, using the ordinary client.
2. Enter the **high Sunreach base platform**, then say **"on the platform"**.
3. Remain at the agreed safe close observation point and face the subjects. Do not shoot, throw spheres, move base Pals, change their work/combat settings, or trigger an invasion. Let the natural control run.
4. When asked for the visual result, report whether the test NPC was visible, grounded, moving and firing. Say **"not seen"** if uncertain; do not turn uncertainty into PASS.
5. Wait for the agent's terminal result before leaving or attempting another scenario.

No admin commands are needed for this block. Lab startup journals do not require clearing request16. If a later normal-event integration test is explicitly enabled, handle its authorized recovery separately; do not run `!siege abort` or `!siege start all-bounty 0` as part of this laboratory sequence.

Departure/reclassification and capture are separate, later blocks. The current player-present case restores and cleans up when presence is lost, so it cannot also certify prolonged post-departure stock demotion. A future bounded observation phase must first retire gameplay and preserve its exact cleanup obligations; a disconnect alone is not proof of source removal. Likewise, the current run ends after its first accepted outgoing damage witness, so do not ask for a capture after the NPC has already been cleaned up.

## Agent-owned result packet and stop rules

Record source/artifact/run identity, scenario and treatment, base ordinal plus human label, player/source presence counts, completed native boundaries, placement and shape evidence, simulation/collision telemetry, accepted damage and terminal ownership outcomes. Keep player UIDs, raw player-bearing logs, settings, dumps and saves private. Correlate observations by the exact current actor/world/ownership scope, not by a matching class name.

| Result | Required meaning |
|---|---|
| PASS | The case's measured outcome occurred and owned resources/leases settled under its contract |
| BLOCKED | A precondition or gameplay witness was absent, or the observation was inconclusive; cleanup/disposition is reported separately |
| FAIL | A native, persistence, identity or safety boundary failed; stop further native work and preserve evidence |

Do not convert returned handles, ammo consumption, incoming damage, a native hit on an unrelated object, a despawn request or an expired timer into success. An interrupted lease remains unresolved unless its exact approved disposition is recorded. `WORLD_FINALIZED` preserves that history and is never live restoration or gameplay PASS.

Only promote a new interest mechanism after proving its exact native consumer, bounded influence and removal behavior. Preserve stock recomputation and legitimate player/Pal ownership transfers. If that cannot be closed server-side, bring this prepared matrix to the operator instead of repeating one ad hoc login per hypothesis.
