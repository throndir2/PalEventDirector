# IMOUTO preflight crash diagnostics

## Current safety status

**Diagnostic-only quarantine. Do not issue another siege start on revision `575a9f521977069dcfcb244994f6c017044e9604`.**

That revision produced a dedicated-server native crash, not client desynchronization. The original `preflight-diagnostic-only` profile remains fully quarantined. The `laboratory-native-test` profile enables chat, combat/invasion observation, substitution, and ordinary invasion starts for testing. There is no mandatory stepped preflight. Native-all comparison remains unavailable. No diagnostic or restart automatically starts an event.

The package version remains alpha.3 to preserve configuration and state schemas. The clean commit SHA, artifact hash, and attested delivery profile identify the package. Both profiles force recurring schedules and item delivery off. Installing the test profile is **not** evidence that an invasion has worked: acceptance still requires its native lifecycle callback.

In-game status, profiles, schedule, score, and leaderboard commands are available after test-profile preparation. An authorized `!siege start native 0` or `!siege start all-bounty 0` runs the normal start validation and, if eligible, dispatches the native probe. Version pins, capability switches, authorization, world settings, base eligibility, and active-incident checks remain automatic requirements; the operator does not have to complete a separate diagnostic.

### Normal gameplay test loop

Start the installed test profile, join, and issue the ordinary in-game command. The adapter automatically brackets roster resolution, world-manager resolution, the manager/option-subsystem calls, the invasion-enable flag read, base/incident/eligibility inspection, dispatch snapshots, and the actual march request with flushed before/after breadcrumbs. Labels are developer-authored; player IDs, addresses, settings, and returned objects are not recorded there.

Ordinary eligibility rejections return an error normally. A native Lua error, missing recorder, or failed before/after write records a fixed error classification and disables further native starts for that process. There is no retry or fallback. Native fail-fast cannot be caught: preserve the last before-marker, private logs, and crash evidence, then stop/fix/redeploy/restart. Do not replay the interrupted event.

Authorized admin starts now use the exact-base `RequestIncidentInvaderEnemy(Guid, Observer)` entry point, with `admin-request-incident` and `admin-admission-result` trace boundaries. Ordinary starts retain the march path and cooldown veto. Admin cooldown flags/timers are not altered: the native Boolean admission result and lifecycle callbacks decide whether the request actually worked. This direct admission path is source-audited but still requires live confirmation.

### Native pathfinding boundary observed on IMOUTO

The `9141b3d4b46c` test reached the direct native request and returned Boolean `true`. The probe observer changed from not path-searching to path-searching, and the manager acquired a pathfinder. Its incident map stayed empty, and no declaration, selection, or invasion-start callback was observed before the discovery timeout. All automatic before/after markers returned; this was not another stack-cookie crash. Ten hash-verified files remain private under `PalEventDirectorDiagnosticBackups/native-admission-1788633154-pathfinding-timeout`.

That probe was the first GUID-sorted target among ten bases and had no cached players in its base. Probe selection now prefers an eligible base with observed player presence, with deterministic ID ordering as the fallback; it does not remove any other target or dispatch fanout before confirmation. This avoids choosing an unoccupied remote base ahead of a known occupied one, but does not prove that navigation was the cause of the timeout.

Timeout handling now captures the native state at the deadline, not just immediately after submission. It records observer/pathfinding/incident state, hook-entry counters, and aggregate loaded start-point actor/navigation-invoker counts. The editable `bIsWaitWorldPartition` flag is reported as configuration, not current waiting: it defaults true in the generated constructor and cannot prove a streaming stall. No positions, player IDs, or invoker state are changed. `InvadeStartLocationList` is a start-point inventory: a key not matching a base ID is not proof that the base lacks a usable start point.

### Higher-level native entry-point control

The occupied-base run still ended its path search without an incident or lifecycle callback. The next explicit control is `!siege test-native` (also `!ped test-native`), not another all-base attempt. It requires fresh admin authority and a current requester controller, checks the controller/base-manager world, and requires the native nearest-base and in-range-base queries to agree on an eligible online-guild base. Those checks are repeated immediately before dispatch, so movement cannot silently redirect the RPC.

The command records a normal durable native-profile occurrence with exactly one target, then invokes `APalPlayerController.Debug_InvaderMarchForNearCamp(FName, true)` using the previously audited stock `GroupName` `Invader_Group_NPC_Grade5_Hunter`. Bounty substitution and fanout are absent from this control. The broader debug RPC is not used. The exact declaration is available in the pinned local Modding Kit; its generated stub does not prove successful behavior on this server.

Requester-only chat states the one-base scope and emits validation/return/outcome progress. A void return is not success; native lifecycle confirmation remains required. Normal `start` commands retain their existing scope and route. This control is never an automatic fallback and must not be run in parallel with another pending start.

### Callable FName binding correction

On `29125a8b34c0`, request 6 was another ten-target `all-bounty` attempt: its probe started and then stopped pathfinding without an incident, and the other nine targets were not dispatched. The separate request 7 correctly selected one native-test base and completed both sets of requester/world/base checks, but stopped at `1788642873-0064-start-test-native-group.before`. No matching after-marker or `debug-nearest-native` invocation exists. The server survived, native calls were locked, and the journal ended at sequence 45. Ten hash-verified files for each attempt are private under `PalEventDirectorDiagnosticBackups\20260905-142854-request-6-all-bounty-timeout-29125a8b34c0` and `PalEventDirectorDiagnosticBackups\20260905-143319-request-7-fname-construction-29125a8b34c0`.

The pinned [global registration](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/Mod/LuaMod.cpp#L5742-L5748) publishes a **userdata instance** as `FName`. Its [call metamethod](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaFName.cpp) implements construction. PED incorrectly rejected it because `type(FName)` was not `"function"`; its function-only mocks hid that mismatch.

The shared lookup now accepts the pinned userdata binding as well as function-based fixtures. The same correction applies to bounty substitution and item-name preparation without enabling item grants or changing event scope. The regression fixture uses real Lua userdata with a call metamethod and verifies both ordinary construction and `pcall` invocation. Native failure replies now include the fixed operation label and an allowlisted classification; raw errors remain suppressed, missing after-markers remain preserved, and a failure still prohibits further native calls in that process. Request 7 is evidence of a construction failure, not evidence that the higher-level raid RPC failed.

### Higher-level RPC returned without raid creation

Request 8 on `a1048cdc4153` selected one occupied base and returned from both `test-native-group` and `debug-nearest-native`. All 45 operation pairs returned. The probe had no path search, pathfinder, cooldown, incident, or declaration/selection/start callback before dispatch, immediately afterward, or at the 60-second deadline. Its in-base timer increased from about 25.5 to 84.6 seconds. The request became `aborted` at `2026-09-05T21:50:50Z`, journal sequence 52; no fanout, results, or rewards occurred. Ten hash-verified files remain private under `PalEventDirectorDiagnosticBackups\20260905-145326-request-8-nearest-rpc-no-incident-a1048cdc4153`.

This is different from the lower-level Boolean admission path, which started and then ended pathfinding without an incident. Neither outcome establishes a working invasion trigger. The live manager class is `BP_PalInvaderManager_C`, so observing only the native base declaration of its Blueprint handoff would be insufficient. The dedicated engine log directory contains no files, and the UE4SS log supplied no independent engine rejection message. Further diagnostics must inspect loaded group/spawn prerequisites and the concrete Blueprint handoff without treating absent reflected hook entries as proof that a direct C++ call did not execute.

### Automatic probe prerequisite evidence

Each new probe now samples these facts before its native dispatch, on the game thread. Fanout does not repeat this heavier inventory, and polling does not scan it every tick. This is logging around an ordinary authorized start, not another manual preflight or an eligibility override.

| Evidence | Read-only source and interpretation |
|---|---|
| Loaded invasion rows | The manager's `InvaderEnemyDataTable` must expose the pinned `UDataTable` wrapper and `PalInvaderDatabaseRow` schema. `ForEachRow` reads only `GroupName`, `BiomeID`, grade bounds and weight through live property views. It never uses numeric row keys as group names or calls the wildcard `GetDataTableRowFromName` thunk. |
| Named group availability | The one-base control compares the fixed stock name with `GroupName`. Ordinary starts report the native-selection row inventory instead. Counts, positive-weight counts and grade bounds are evidence, not a claim that every native selection condition has passed. |
| Spawn geometry | The base's `Transform.Translation` and each cached start point's `Location` are used only in memory. Counts show how many points lie between the loaded minimum/maximum radii in 2D and 3D, plus overlap with scanned row biomes. Neither metric is asserted to be the game's complete selection algorithm or proof of a traversable path. No coordinates or point keys enter output. |
| Game data thresholds | `GetGameSetting(world)` returns the `UPalGameSetting` data-asset pointer. Only fixed radius, water-threshold and required-base-level fields are read. This is not the prohibited by-value world-options getter or a dump of server settings. |
| Navigation disable state | For a bounded sample of radius matches, the source actor/component must be valid and the component must belong to the event world. `IsDisableInvorker()` supplies the actual Boolean disable state. No activate/deactivate/setter is called; the default world-partition wait flag is not treated as live activity. |
| Blueprint handoff | The actual manager class and bounded superclass chain are enumerated for `RequestIncidentInvaderEnemy_BP`. The function's owner must be a Blueprint class and its native flag must be clear. The exact `GetFullName()` is passed to `RegisterHook`, without reconstructing a guessed path. A native base declaration is reported as such and is not misrepresented as an observed override. |

Limits are 512 table rows, 256 start-point callbacks, 32 navigation candidates, 128 functions per class and eight classes. Partial coverage is explicitly reported; an incomplete group scan cannot establish absence. These caps bound Lua callbacks and native read requests, not all internal sparse-map slot checks or wall-clock time. All iterators use an explicit `true` only to stop and `nil` to continue: the pinned [DataTable](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUDataTable.cpp#L195-L213), [TMap](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaTMap.cpp#L149-L166), and [function](https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUStruct.cpp#L57-L94) loops each contain the false-result double-removal defect.

The script hook uses the first callback slot, which is post-execution and has `(Context, Base, Parameter)` arguments, without the native post-hook's extra return-value argument. It returns nothing, writes no native parameters, and records only event-scoped counts and whether the probe identity matched. Existing native hooks retain their original routing. A positive callback establishes an observed handoff, not successful incident creation. Registration alone does not verify the script backend; zero callbacks do not prove that no direct C++ call or unobserved execution path occurred.

Private chat includes the request number, complete/partial sample status, group presence, radius counts, navigation counts, and whether the Blueprint observer registered. Timeout chat adds observed/matched Blueprint counts. Each added native boundary has flushed markers. An error preserves the first failing boundary, suppresses raw error content and locks further native operations; no diagnostic automatically retries, selects another group, moves a spawn point, clears a cooldown or fabricates a raid.

Occupied-slot rejections are inspected before the existing global start veto returns. At most 16 incident objects are sampled for enemy/visitor type and their read-only initialized/executing/completed/canceled predicates, with explicit partial coverage and invalid-object counts. Only aggregate overlap with the latest PED event's target set is reported; no base IDs are emitted. Process-wide reflected handoff/lifecycle counters are included in the private log because callbacks can occur outside the event's confirmation window. A completed, canceled, invalid or unrelated slot still does not get deleted or bypassed: these observations are not authorization to force-stop native activity.

On `b538ea86cf6a`, request 9 successfully collected the complete prerequisite inventory: 240 rows, six positive-weight stock-group variants with grade bounds 61-80, a level-35 base above the required level 8, and one player inside. The loaded radius bounds were **5000-15000 cm**, not the generated constructor's defaults. All 55 start points were inspected: three matched the 2D radius, one matched the 3D radius, their biomes overlapped the stock group, and all three sampled invokers were in the correct world and not disabled. The concrete script observer registered, but no handoff, pathfinding or incident was observed through the 60-second timeout. All 63 marker pairs returned. Evidence is private under `PalEventDirectorDiagnosticBackups\20260905-174952-request-9-prerequisites-b538ea86cf6a`, journal sequence 59. Invasion grade must not be equated with base level.

The next attempt, request 10, used `all-bounty` and was rejected at registered-base inspection: the native incident map had become nonempty. No new native dispatch ran; the journal ended at sequence 62. The user had reconnected and reported no visible raid or visitor at their current base. That does not establish whether the slot belongs to another base, represents delayed work, or is stale. Reconnecting does not clear server-side incident state. A restart may clear transient activity and must not be misrepresented as a fix for its unknown cause.

### Consolidated native experiments

The expanded harness separates inspection from mutation. `inspect-native` reads the current base even when the incident-slot guard would reject a new start; it does not change the current event or scheduler. The `test-native` route argument selects one of three audited entry points on the same validated base: Boolean admission, ordinary selected-base march, or the controller debug RPC. A debug group argument is resolved against the loaded table and canonicalized before dispatch. Unknown groups, arbitrary methods and wider scopes are rejected. No route automatically falls back to another.

`native-experiments.ndjson` is a private, schema-checked scalar journal with a run ID, observation ID, request number where applicable, timestamp and monotonically increasing record sequence. Its sections include group/biome/grade/weight/wave/build-condition summaries, anonymous point distances and navigation state, bounded worker-level samples, function flags and parameter offsets, per-slot lifecycle/member/controller state, and reflected hook outcomes. Raw player/base/group GUIDs, native addresses, absolute coordinates, native objects, settings objects and opaque errors are not admitted by the record schema. Worker reads cap at 32 and recheck native array length before each 1-based access: the pinned TArray getter can extend an array on an out-of-range **read**.

The observer obtains the incident system through its world-context pointer getter and reads its loaded `IncidentClassMap`. Relevant subclasses are identified through bounded metadata inheritance walks, not guessed Blueprint asset paths. Observation hooks cover enemy/visitor manager handoffs, incident generation and admission gates, native selection grade/biome/member count, candidate-location results, and available concrete Blueprint generation/initialization/begin/spawn/end/cancel stages. Hook coverage and metadata are recorded; callbacks return nothing and never replace native results. Missing hooks and absent reflected callbacks do not establish coverage of direct C++ calls.

Passive observation is independent of the gameplay event and remains bounded to eight scopes and ten minutes. It captures occupied slots, state predicates, actual member/controller counts, native invader-info grade/wave state and native remaining-time getters when available. It does not repeat the full group/spawn inventory every tick. Sampling never invokes a start method; stale handles close an observation, and native faults stop further native work. Late native activity remains diagnostic evidence only, without replay or retroactive scoring.

`test-path` is a separate, explicitly requested query experiment. Before any query it validates the live `NavigationSystemV1` function names, field classes, counts, offsets and exact three-field numeric FVector layout against the small Windows x64 float/double-vector signatures. The known query parameter payload is 56 or 80 bytes, not a by-value large settings struct. It passes independently copied numeric vectors, the validated requester pawn and the base navigation-filter class; neither choice is assumed equivalent to Palworld's invader-specific pathfinder. At most three nearby candidates are queried. Results distinguish navigation building/locked flags, returned-object validity, actual native path validity, partial paths, point counts, length, cost and unavailable/sentinel costs. Path coordinates are not logged.

The native navigation-path predicate is invoked through its exact unbound UFunction because the pinned UE4SS `UObject:IsValid()` member would otherwise shadow `UNavigationPath::IsValid()`. The harness does not invent a `GetPathPoints()` method: it counts the `PathPoints` property without indexing or dumping it. Unsupported live metadata stops the experiment before any query; no signature bypass or retry is supplied.

## Preserved IMOUTO evidence

Operator-provided evidence, not independently read from IMOUTO in the MIKO coding session:

- Affected source: `575a9f521977069dcfcb244994f6c017044e9604`.
- Artifact SHA-256: `cd9f72b047b93d9abe504bf9255e93eeb4f5aa6123ea429e62a9fec515471cbf`.
- Authorized command: `!siege start native 0`, at `2026-09-04T22:11:03Z`.
- Journal: sequence 14 `manual_countdown_armed`, sequence 15 `schedule_start_intent`; no `event_start_intent` or probe-dispatch snapshot.
- Fault: `2026-09-04T22:11:04.641Z`, Shipping server, UE4SS module, `0xc0000409` / BEX64.
- Pinned PDB attribution: `UE4SS!__report_gsfailure+0x5`, RVA `0xC482C5`.
- Dump SHA-256: `699105f4e39efd7a59eb234932aaecddbae43d23d9c87ede14e4f39479e640de`.
- Evidence is retained on IMOUTO beneath `PalEventDirectorDiagnosticBackups/20260904-151244-crash-575a9f521977` in its dedicated-server root. Leave that directory and the original dump unchanged. Never add a dump, world, settings file, or player data to Git or a public issue.

The reported boundary is `Bridge:preflight_start`, before native invasion dispatch. Stack-cookie failure is consistent with memory corruption; it does not by itself establish which reflected call damaged the stack. Lua `pcall` cannot catch this native fail-fast.

Local inspection of the preserved dump on IMOUTO confirmed fast-fail parameter `2` (stack-cookie check failure). The dump's UE4SS CodeView identity matches the pinned local DLL, whose GUID/age matches its PDB. The first stack slot is return RVA `0x288DFC`, resolving to `RC::LuaType::call_ufunction_from_lua+0x12FC`; the preceding instruction calls `__security_check_cookie` at RVA `0xC477B0`. This places the failed cookie in the reflected-call wrapper that owns the fixed parameter buffer, rather than identifying only the terminal `__report_gsfailure` routine. It still does not identify the particular UFunction that corrupted that frame. The original dump hash remains unchanged.

## Source and signature audit

Pins:

- Dedicated build `24575149`, server pak SHA-256 `bffab47cbd3b3c6d14d616376d4e0b060b2429a5eb4c2022820d4f38d36a0770`.
- UE4SS API `3.0.1`, tag `2281fa31`, source `2281fa311e417b1dfddedbcd49972d764fddb244`.
- UE4SS DLL SHA-256 `21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8`.
- Generated Palworld Modding Kit `e6632458b97af0083eb81715775651b08104ef6a`; its headers are discovery evidence, **not** a build-24575149 UFunction layout dump.

| Boundary | Audited declaration / binding | Diagnostic treatment |
|---|---|---|
| `GetInvaderManager` | Static native UFunction: `(const UObject* WorldContextObject) -> UPalInvaderManager*` | Before invoking, inspect current UFunction flags, exactly two parameter/return properties, their exact FNames and field-class FNames, object-property classes, and expected Windows x64 offsets 0/8. Each metadata read is a separate command step. |
| `manager:GetWorld()` | Zero-argument UE4SS UObject binding returning a UWorld wrapper; **not a Palworld UFunction** | Invoke only after the manager-call after-marker and a separate validity step. |
| `GetAddress()` | Zero-argument UE4SS object binding returning a pointer-sized integer; **not a Palworld UFunction** | Separate manager/world operations. Compare only in memory; never print or persist the numbers. |
| `GetOptionWorldSettings` | Static native UFunction: `(const UObject* WorldContextObject) -> FPalOptionWorldSettings` **by value** | Metadata-only inspection. Do not materialize settings in this diagnostic revision. |
| `GetOptionSubsystem` | Static native UFunction: `(const UObject* WorldContextObject) -> UPalOptionSubsystem*` | Test-profile preflight audits the same two-property pointer signature, then calls it in a separate step and verifies the returned object's world. |
| `OptionWorldSettings.bEnableInvaderEnemy` | Reflected struct property on the world-scoped option subsystem, then a Boolean field | Read through a `UScriptStruct` property view, never through a by-value UFunction. Do not enumerate, format, or log settings values. |
| `bEnableInvaderEnemy` | Reflected Boolean inside the settings struct | Not read until the large return is proven safe in a later revision. No credential-bearing settings object is created here. |
| World-filtered incident scan | Per-incident `GetWorld`, `GetAddress`, reflected `IsExecuting() -> bool` | Deferred; never batch-run after the unverified settings boundary. |
| Eligibility | Guild lookup, observer map, base GUID returns and Boolean property reads | Deferred; exact per-call ABI review is still required before advancing beyond the blocked settings boundary. |

### Concrete buffer hazard

The exact pinned [LuaUFunction header](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/include/LuaType/LuaUFunction.hpp) defines `DynamicUnrealFunctionData` as a fixed `uint8_t data[0x200]` stack buffer: **512 bytes**. The pinned [LuaUObject implementation](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUObject.cpp) passes it to `ProcessEvent`, using reflected offsets without a visible `ParmsSize` capacity check. Returned structs are converted to Lua after that call.

The generated `FPalOptionWorldSettings` header contains 120 reflected fields, including strings and arrays. An x64 estimate using 16-byte FString/TArray and 8-byte FName is **520 bytes for the struct**, roughly 528 bytes including the world-context argument. That estimate is not a measured runtime `sizeof`, but it exceeds the fixed buffer and is a concrete reason **not to reproduce the settings getter blindly**.

The isolated diagnostic profile inspects only the return struct's metadata handles and field offsets, from the last field backwards. If `returnOffset + fieldOffset + 1 > 512`, it stops with an explicit oversized-return finding. A smaller observed lower bound is not a safe upper bound: the pinned [UFunction Lua bindings](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUFunction.cpp) do not expose exact `ParmsSize`/return extent, so that case also stops rather than guessing.

The guarded gameplay adapter removes **both** calls to this getter, including the dispatch snapshot's call. It uses the audited [GetOptionSubsystem declaration](https://github.com/localcc/PalworldModdingKit/blob/e6632458b97af0083eb81715775651b08104ef6a/Source/Pal/Public/PalUtility.h) and the [OptionWorldSettings property](https://github.com/localcc/PalworldModdingKit/blob/e6632458b97af0083eb81715775651b08104ef6a/Source/Pal/Public/PalOptionSubsystem.h). A property view does not pass the large struct through `ProcessEvent`'s fixed call buffer. The subsystem must belong to the selected world, and only a readable, Boolean `true` invasion-enable flag passes. Missing data, a different world, or a disabled flag fails closed; there is no fallback to the old getter.

For optional isolated investigation, the test profile's stepped sequence follows manager verification with the option-subsystem pointer-signature audit, a separately bracketed getter call, world identity checks, the struct-view wrapper check, and the single Boolean read. It does not open or close a gameplay gate. Native invasion acceptance still requires a correlated lifecycle callback during an ordinary gameplay test.

`GetWorld` and `GetAddress` behavior is documented by the pinned [UObject binding source](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/include/LuaType/LuaUObject.hpp). Metadata property enumeration and offsets use only methods exposed by the pinned [UStruct](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUStruct.cpp) and [property](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaXProperty.cpp) bindings. No raw-memory offsets, custom-property hacks, or invented size getters are used.

### Metadata iterator calling convention

The `daa7ffaa2597` dot-call repair was incorrect. The pinned [LuaMadeSimple implementation](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/deps/first/LuaMadeSimple/src/LuaMadeSimple.cpp) requires userdata as argument 1. Its [get_userdata helper](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/deps/first/LuaMadeSimple/include/LuaMadeSimple/LuaMadeSimple.hpp) then removes the receiver, leaving the callback at index 1. The receiver is not an upvalue. Correct invocation is `owner:ForEachProperty(callback)`, or `enumerate(owner, callback)` after separately obtaining the method. `UFunction::construct` registers the UStruct member functions; no cast or alternate wrapper is required by that registration path.

The iterator explicitly supports Boolean early termination. However, tracing the complete pinned stack operations reveals a narrower hazard: `get_bool(2)` removes a Boolean result, and the false branch also calls `discard_value(2)`. A false continuation therefore attempts to remove the callback result twice. The helper uses `nil` to continue and `true` to stop at the first excess property. This retains the inventory bound; it does not ignore signature mismatches.

An isolated fixture using the existing Fengari C API reproduces the receiver requirement and detects the invalid cleanup index before performing that undefined stack operation. It exercises the actual diagnostic helper with nil continuation and true termination. This is source-level evidence, not proof of the exact cause of run `1788569461`'s live Lua error or the original native crash.

Method lookup now has its own `*-properties-method` before/after boundary, separate from `*-properties` iteration. Missing/non-callable methods halt without trying another API. An ordinary Lua error identifies the operation and a fixed, privacy-safe classification; it never permits a retry or skip.

### Exact declaration checks without display-path assumptions

On IMOUTO, revision `a7165dfc403e`, run `1788579044` passed the separate method-exposure and property-enumeration operations. It then halted at `0015-manager-parameter-1-name` because the compound `GetFullName()` string did not match the assumed declaration text. Both markers exist for that read. The server survived, the journal stayed at sequence 16, and no manager getter ran. Ten hash-verified evidence files remain private under `PalEventDirectorDiagnosticBackups/preflight-1788579044-parameter-name-mismatch`. Do not resume that halted run.

The mismatch did not reveal the actual field name or type. Rather than guess alternate separators or accept arbitrary suffixes, the diagnostic now checks the declaration directly: `FProperty:GetFName()` identifies the exact `WorldContextObject` or `ReturnValue` symbol, and `FProperty:GetClass():GetFName()` identifies the exact `ObjectProperty` or `StructProperty` kind. These are separately stepped bindings exposed by the pinned [property source](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaXProperty.cpp), [field-class source](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaXFieldClass.cpp), and [FName source](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaFName.cpp). `ToString()` is a separate step for each copied FName.

FName and FieldClass wrappers expose `type()` but not `IsValid()` in this pin. Their copied wrapper types are checked separately, while the owning UFunction and property remain subject to the existing liveness checks. The exact function lookup, flags, property count, field names/types, offsets, and pointed-to classes are still mandatory. A fresh run must demonstrate that they match; a display-name mismatch is not taken as permission to invoke a getter.

**Unresolved evidence:** no permitted local build-stamped runtime UFunction dump, exact struct size/alignment, or decoded crash stack beyond the operator's report was available. Header inspection and mocked tests do not establish exact ABI safety. The new IMOUTO breadcrumb run and a build-specific layout audit remain required.

## Install on the disposable IMOUTO server

1. Preserve the crash evidence directory unchanged. Stop only IMOUTO through the existing managed/operator shutdown procedure. Do not restart or change MIKO Production.
2. Run the installer from the new diagnostic-profile bundle. Existing UE4SS installations require the explicit `-ReplaceExistingUe4ss` switch. It backs up and replaces the entire runtime from the hash-pinned archive rather than adopting existing files; enabled unrelated mods still require separate review. It rejects an older normal-profile artifact and retains rollback evidence.
3. Run the installed laboratory activation command. The isolated profile reports `PreflightDiagnosticsOnly` and disables all six capabilities. The test profile reports `LaboratoryTestEnabled` and enables chat/combat/invasion/substitution capabilities without manual preflight. Both back up configuration, disable recurring schedules and item delivery, and leave event recovery files untouched.
4. Run the installed launcher with `-ValidateOnly`, then without that switch. The launcher verifies the installed PED scripts, runtime/proxy/layout/settings/mod-control inventory, operator scripts, and pinned DLL; it exports the verified build, runtime API, and runtime tag only into the child server process.
5. For gameplay testing, join and use the ordinary in-game commands directly. For optional isolated diagnostics instead, use the installed `PalEventDirectorDeployments/Invoke-PalEventDirectorPreflight.ps1`: `-Preview`, `-ReadResult`, then one exact `-ExpectedStep` at a time. The operator may delegate confirmations to the agent, but the isolated diagnostic still has no bulk-run option or automatic retry.
6. If a trusted engine console is already available, the equivalent `ped diagnose-preflight` commands below also work and return output to its output device. No player/chat variant or debug-console enabling is needed.

Local ingress is confined to `Pal/Saved/PalEventDirector/preflight-commands`. The file is renamed to `in-flight.json` before game-thread execution and cleared only after a response is written. A stale queued or in-flight request at startup blocks ingress and is never replayed. After a crash, preserve and archive that directory with the evidence while the server is stopped before beginning a deliberately new diagnostic run. Do not remove it as a way to retry automatically.

## One command, one operation

`ped diagnose-preflight` previews the next step and performs **zero native operations**.

`ped diagnose-preflight confirm-disposable-readonly <expected-step>` executes **one** requested operation, flushes its before/after markers, and returns control to the operator. Owning objects and retained handles are rechecked for liveness immediately before use on the same game-thread callback, each with separate `-liveness-N.before/after` breadcrumbs. These checks do not advance to any later diagnostic step. Inspect the requested after-marker before entering the command again. There is no bulk loop, automatic advance, native-all fallback, or execution on mod load.

The third word is mandatory: use the exact step identifier shown by preview. A missing, stale, skipped, or repeated identifier is rejected without executing anything. Token-only confirmation does not execute the next step.

The shared sequence is:

1. UE4SS version, utility lookup/validity, controller lookup/validity, existing controller-world retrieval/validity.
2. Individual `GetInvaderManager` UFunction signature metadata reads.
3. `get-invader-manager` **only**, then a separate `manager-valid` operation.
4. `manager-get-world`, its validity check, then separate manager/world address operations.
5. In the isolated profile, individual settings-function signature/return-struct metadata reads and the return-offset screen, ending in an explicit block.
6. In the test profile, optional option-subsystem signature reads, its getter/world checks, the settings property-view type, and the invasion-enable Boolean. This inspection is independent of ordinary in-game starts and does not dispatch automatically.

The first missing after-marker identifies the exact operation that did not return. For example, a surviving `get-invader-manager.after` permits the next explicit validity command; it does not run `manager-get-world` for the operator. A metadata mismatch or unreadable size is a stop condition, not permission to weaken checks.

## Breadcrumb format and privacy

The dedicated data directory receives `native-preflight-breadcrumbs.ndjson`. Each record has exactly three fields: `step`, `buildId`, and `objectValid`. Example:

```json
{"step":"1788559863-0028-get-invader-manager.before","buildId":"24575149","objectValid":true}
```

The leading run identifier and incrementing operation ordinal distinguish steps within a run. Step names are static labels/ordinal indexes, never object-derived names or IDs. `objectValid` describes the context's latest explicit validity result; lookup steps start false and do not claim validity until the separate validity operation. An after-marker means only that the operation returned and the marker was written; it is not a native invasion acceptance signal.

Automatic gameplay traces use `timestamp-ordinal-start-operation.before/after` labels. Their `objectValid` is false because a generic operation boundary makes no separate object-validity claim. They preserve multiple return values internally but never serialize those values into the breadcrumb file.

The recorder bypasses normal log-level filtering and flushes/closes the file before each native operation and immediately after return. Before-write failure means **no operation runs**. After-write failure, Lua error, invalid object, or signature mismatch halts that diagnostic session. Raw native/Lua error strings are suppressed; pointers, UIDs, object names, settings values, credentials, worlds, and result tables never enter the breadcrumb file.

On an ordinary Lua failure, the operator response includes only an allowlisted operation/cause pair such as `metadata-enumeration/receiver-required` or `metadata-method-lookup/non-string-error`. Classification inspects at most the first 1024 bytes of a string error, never stringifies non-string errors, and retains only fixed labels. Raw error text is never formatted or persisted. On native fail-fast, preserve the new breadcrumbs and crash artifacts and stop the experiment. The file is never read to resume or retry a diagnostic. A restarted mod does not run any operation until another explicit operator command. Existing `starting` and `awaiting_confirmation` event occurrences remain `recovery_required`; the diagnostic does not reset, cancel, or replay them.

## Validation scope

- Pure-Lua tests count native-operation mocks and require one operation per confirmation and zero at preview/startup.
- They cover host/build/API/tag/token/step-order gates, no raw object/error formatting, fail-closed file writes, signature mismatch, oversized/unknown settings layouts, and quarantine despite persisted enabled configuration.
- A Fengari C-API binding fixture covers explicit receivers, the pinned false-result cleanup hazard, nil continuation, Boolean early-stop bounds, and separate method-lookup/iteration markers. It does not load UE4SS or call Palworld.
- A separate process exits abruptly immediately after a real flushed before-marker; the test verifies there is no after-marker. Fengari lacks `io.open`, so a test-only, temp-directory-confined Node filesystem shim supplies write/fsync/close while exercising the actual Lua writer. This proves the writer contract, **not** recovery from a real UE4SS stack-cookie failure or native Palworld ABI safety.
- Windows PowerShell 5.1 tests validate diagnostic-only activation, backups, runtime-tamper rejection, and child-only attestation variables.
- No local test invokes a real Palworld getter, siege, native-all diagnostic, or Production operation.