# IMOUTO preflight crash diagnostics

## Current safety status

**Diagnostic-only quarantine. Do not issue another siege start on revision `575a9f521977069dcfcb244994f6c017044e9604`.**

That revision produced a dedicated-server native crash, not client desynchronization. This replacement preserves the event implementation for simulation but blocks manual, recurring, direct, fanout, and native-all start routes before unsafe preflight. There are no chat/combat/invasion hooks or gameplay polling. A file-only poll accepts explicit trusted-local requests and transfers one requested diagnostic step to the game thread; it does not advance or retry native diagnostics automatically. Existing enabled persistent capabilities are ignored through an in-memory safety overlay; configuration cannot lift the native-start quarantine.

The package version remains alpha.3 to preserve configuration and state schemas; the clean commit SHA, artifact hash, and `deliveryProfile=preflight-diagnostic-only` distinguish this diagnostic revision. Installing it is **not** evidence that the native ABI or gameplay adapter is safe.

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

## Source and signature audit

Pins:

- Dedicated build `24575149`, server pak SHA-256 `bffab47cbd3b3c6d14d616376d4e0b060b2429a5eb4c2022820d4f38d36a0770`.
- UE4SS API `3.0.1`, tag `2281fa31`, source `2281fa311e417b1dfddedbcd49972d764fddb244`.
- UE4SS DLL SHA-256 `21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8`.
- Generated Palworld Modding Kit `e6632458b97af0083eb81715775651b08104ef6a`; its headers are discovery evidence, **not** a build-24575149 UFunction layout dump.

| Boundary | Audited declaration / binding | Diagnostic treatment |
|---|---|---|
| `GetInvaderManager` | Static native UFunction: `(const UObject* WorldContextObject) -> UPalInvaderManager*` | Before invoking, inspect current UFunction flags, two parameter/return properties, names, object-property types/classes, and expected Windows x64 offsets 0/8. Each metadata read is a separate command step. |
| `manager:GetWorld()` | Zero-argument UE4SS UObject binding returning a UWorld wrapper; **not a Palworld UFunction** | Invoke only after the manager-call after-marker and a separate validity step. |
| `GetAddress()` | Zero-argument UE4SS object binding returning a pointer-sized integer; **not a Palworld UFunction** | Separate manager/world operations. Compare only in memory; never print or persist the numbers. |
| `GetOptionWorldSettings` | Static native UFunction: `(const UObject* WorldContextObject) -> FPalOptionWorldSettings` **by value** | Metadata-only inspection. Do not materialize settings in this diagnostic revision. |
| `bEnableInvaderEnemy` | Reflected Boolean inside the settings struct | Not read until the large return is proven safe in a later revision. No credential-bearing settings object is created here. |
| World-filtered incident scan | Per-incident `GetWorld`, `GetAddress`, reflected `IsExecuting() -> bool` | Deferred; never batch-run after the unverified settings boundary. |
| Eligibility | Guild lookup, observer map, base GUID returns and Boolean property reads | Deferred; exact per-call ABI review is still required before advancing beyond the blocked settings boundary. |

### Concrete buffer hazard

The exact pinned [LuaUFunction header](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/include/LuaType/LuaUFunction.hpp) defines `DynamicUnrealFunctionData` as a fixed `uint8_t data[0x200]` stack buffer: **512 bytes**. The pinned [LuaUObject implementation](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUObject.cpp) passes it to `ProcessEvent`, using reflected offsets without a visible `ParmsSize` capacity check. Returned structs are converted to Lua after that call.

The generated `FPalOptionWorldSettings` header contains 120 reflected fields, including strings and arrays. An x64 estimate using 16-byte FString/TArray and 8-byte FName is **520 bytes for the struct**, roughly 528 bytes including the world-context argument. That estimate is not a measured runtime `sizeof`, but it exceeds the fixed buffer and is a concrete reason **not to reproduce the settings getter blindly**.

The diagnostic inspects only the return struct's metadata handles and field offsets, from the last field backwards. If `returnOffset + fieldOffset + 1 > 512`, it stops with an explicit oversized-return finding. A smaller observed lower bound is not a safe upper bound: the pinned [UFunction Lua bindings](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUFunction.cpp) do not expose exact `ParmsSize`/return extent, so that case also stops rather than guessing. The metadata inspection itself is native code and still requires a disposable run.

`GetWorld` and `GetAddress` behavior is documented by the pinned [UObject binding source](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/include/LuaType/LuaUObject.hpp). Metadata property enumeration and offsets use only methods exposed by the pinned [UStruct](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaUStruct.cpp) and [property](https://github.com/Okaetsu/RE-UE4SS/blob/2281fa311e417b1dfddedbcd49972d764fddb244/UE4SS/src/LuaType/LuaXProperty.cpp) bindings. No raw-memory offsets, custom-property hacks, or invented size getters are used.

**Unresolved evidence:** no permitted local build-stamped runtime UFunction dump, exact struct size/alignment, or decoded crash stack beyond the operator's report was available. Header inspection and mocked tests do not establish exact ABI safety. The new IMOUTO breadcrumb run and a build-specific layout audit remain required.

## Install on the disposable IMOUTO server

1. Preserve the crash evidence directory unchanged. Stop only IMOUTO through the existing managed/operator shutdown procedure. Do not restart or change MIKO Production.
2. Run the installer from the new diagnostic-profile bundle. Existing UE4SS installations require the explicit `-ReplaceExistingUe4ss` switch. It backs up and replaces the entire runtime from the hash-pinned archive rather than adopting existing files; enabled unrelated mods still require separate review. It rejects an older normal-profile artifact and retains rollback evidence.
3. Run the installed laboratory activation command. In this revision its result is `PreflightDiagnosticsOnly`: it backs up configuration, turns **all six** gameplay capabilities off, disables every recurring schedule, and leaves event recovery files untouched.
4. Run the installed launcher with `-ValidateOnly`, then without that switch. The launcher verifies the installed PED scripts, runtime/proxy/layout/settings/mod-control inventory, operator scripts, and pinned DLL; it exports the verified build, runtime API, and runtime tag only into the child server process.
5. Use the installed `PalEventDirectorDeployments/Invoke-PalEventDirectorPreflight.ps1` on IMOUTO. `-Preview` queues a no-native-call preview; `-ReadResult` reads its result. Submit one step with `-ExpectedStep` set to the exact identifier returned by preview and explicitly confirm the prompt. Use `-ReadResult` again after processing. There is no bulk-run option. The helper is fixed to IMOUTO and is hash-attested with the deployment.
6. If a trusted engine console is already available, the equivalent `ped diagnose-preflight` commands below also work and return output to its output device. No player/chat variant or debug-console enabling is needed.

Local ingress is confined to `Pal/Saved/PalEventDirector/preflight-commands`. The file is renamed to `in-flight.json` before game-thread execution and cleared only after a response is written. A stale queued or in-flight request at startup blocks ingress and is never replayed. After a crash, preserve and archive that directory with the evidence while the server is stopped before beginning a deliberately new diagnostic run. Do not remove it as a way to retry automatically.

## One command, one operation

`ped diagnose-preflight` previews the next step and performs **zero native operations**.

`ped diagnose-preflight confirm-disposable-readonly <expected-step>` executes **one** requested operation, flushes its before/after markers, and returns control to the operator. Owning objects and retained handles are rechecked for liveness immediately before use on the same game-thread callback, each with separate `-liveness-N.before/after` breadcrumbs. These checks do not advance to any later diagnostic step. Inspect the requested after-marker before entering the command again. There is no bulk loop, automatic advance, native-all fallback, or execution on mod load.

The third word is mandatory: use the exact step identifier shown by preview. A missing, stale, skipped, or repeated identifier is rejected without executing anything. Token-only confirmation does not execute the next step.

The sequence is:

1. UE4SS version, utility lookup/validity, controller lookup/validity, existing controller-world retrieval/validity.
2. Individual `GetInvaderManager` UFunction signature metadata reads.
3. `get-invader-manager` **only**, then a separate `manager-valid` operation.
4. `manager-get-world`, its validity check, then separate manager/world address operations.
5. Individual settings-function signature and return-struct metadata reads.
6. The return-offset safety screen, ending in an explicit block. The settings getter, enable-flag read, incident scan, and eligibility traversal do **not** follow automatically.

The first missing after-marker identifies the exact operation that did not return. For example, a surviving `get-invader-manager.after` permits the next explicit validity command; it does not run `manager-get-world` for the operator. A metadata mismatch or unreadable size is a stop condition, not permission to weaken checks.

## Breadcrumb format and privacy

The dedicated data directory receives `native-preflight-breadcrumbs.ndjson`. Each record has exactly three fields: `step`, `buildId`, and `objectValid`. Example:

```json
{"step":"1788559863-0028-get-invader-manager.before","buildId":"24575149","objectValid":true}
```

The leading run identifier and incrementing operation ordinal distinguish steps within a run. Step names are static labels/ordinal indexes, never object-derived names or IDs. `objectValid` describes the context's latest explicit validity result; lookup steps start false and do not claim validity until the separate validity operation. An after-marker means only that the operation returned and the marker was written; it is not a native invasion acceptance signal.

The recorder bypasses normal log-level filtering and flushes/closes the file before each native operation and immediately after return. Before-write failure means **no operation runs**. After-write failure, Lua error, invalid object, or signature mismatch halts that diagnostic session. Raw native/Lua error strings are suppressed; pointers, UIDs, object names, settings values, credentials, worlds, and result tables never enter the breadcrumb file.

On native fail-fast, preserve the new breadcrumbs and crash artifacts and stop the experiment. The file is never read to resume or retry a diagnostic. A restarted mod does not run any operation until another explicit operator command. Existing `starting` and `awaiting_confirmation` event occurrences remain `recovery_required`; the diagnostic does not reset, cancel, or replay them.

## Validation scope

- Pure-Lua tests count native-operation mocks and require one operation per confirmation and zero at preview/startup.
- They cover host/build/API/tag/token/step-order gates, no raw object/error formatting, fail-closed file writes, signature mismatch, oversized/unknown settings layouts, and quarantine despite persisted enabled configuration.
- A separate process exits abruptly immediately after a real flushed before-marker; the test verifies there is no after-marker. Fengari lacks `io.open`, so a test-only, temp-directory-confined Node filesystem shim supplies write/fsync/close while exercising the actual Lua writer. This proves the writer contract, **not** recovery from a real UE4SS stack-cookie failure or native Palworld ABI safety.
- Windows PowerShell 5.1 tests validate diagnostic-only activation, backups, runtime-tamper rejection, and child-only attestation variables.
- No local test invokes a real Palworld getter, siege, native-all diagnostic, or Production operation.