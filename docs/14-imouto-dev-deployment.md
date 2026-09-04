# IMOUTO DEV deployment

## Host roles

The laboratory is intentionally split across two Windows machines:

| Host | Role |
|---|---|
| MIKO | Pal Event Director source, tests, clean builds, canonical Git delivery, and the existing Production Palworld server. |
| IMOUTO | Disposable Palworld dedicated-server deployment and manual testing with its locally installed vanilla Palworld client. |

No Pal Event Director operation starts, stops, updates, edits, or deploys into MIKO's Palworld installation. In particular, the existing MIKO Production launchers under `D:\scripts` remain external protected operator assets. The IMOUTO installer contains no MIKO server path or launcher reference, and repository validation rejects any deployment script that gains one.

## Target boundary

The default IMOUTO dedicated-server root is:

```text
D:\SteamLibrary\steamapps\common\PalServer
```

The sibling Palworld client directory is not a valid target. The installer requires all of the following before it writes anything:

- the target leaf directory is named `PalServer`;
- the sibling Steam manifest is App ID `2394010`, Palworld Dedicated Server;
- the manifest build is the validated build `24575149`;
- the dedicated-server executable and `Pal-WindowsServer.pak` match the validated hashes;
- no process whose executable is below the dedicated-server root is running;
- the target path does not traverse an NTFS reparse point;
- the mod archive matches a clean MIKO build manifest; and
- any existing UE4SS runtime is either the exact pinned runtime or explicitly approved for backed-up replacement.

The installer never modifies the Palworld client, Steam manifests, server configuration, world saves, Windows firewall, router, or MIKO. It does not start or stop the IMOUTO server. It installs separate launcher and laboratory-activation commands, but it leaves gameplay capabilities disabled until the explicit activation command is confirmed.

## Continuous deployment workflow

The installer source lives at:

```text
operations\imouto\Install-PalEventDirectorImouto.ps1
```

Because IMOUTO can read MIKO's files, no manual package-copy step is required. MIKO creates a standalone directory containing the installer, clean-build manifest, exact mod archive, and bundle provenance. Run `npm run build:imouto` after the clean artifact build. The resulting directory is named `dist\IMOUTO-<version>-<revision>`.

When `ArtifactPath` is omitted, the bundled installer reads `manifest.json` beside itself and deploys the exact adjacent archive named by that manifest. This works through a UNC share or mapped drive and snapshots both files locally before extraction so a concurrent MIKO build cannot alter an in-progress install.

For each revision:

1. On MIKO, inventory all repository changes.
2. Run the complete test and static-validation gate.
3. Commit and push the coherent revision to canonical `origin/main`.
4. Verify local and remote canonical SHAs match.
5. Build again from the clean pushed revision with `REQUIRE_CLEAN_BUILD=1`, then run `npm run build:imouto`.
6. Stop only the IMOUTO dedicated server.
7. From a PowerShell session on IMOUTO, invoke the installer through the MIKO share.
8. Review the reported version, source revision, artifact SHA-256, and backup path.
9. Run `PalEventDirectorDeployments\Enable-PalEventDirectorLaboratory.ps1` after every install and confirm the configuration validation/mutation. Persistent capability values may survive an upgrade, but the installer deliberately reports them as requiring reactivation against the new deployment.
10. Run `PalEventDirectorDeployments\Start-PalEventDirectorImouto.ps1 -ValidateOnly`, then use the same script without that switch to start the dedicated server. Do not use Steam Play for PED mutation tests because Steam does not supply the required process-local environment.
11. Perform the manual vanilla-client checks on IMOUTO.

The normal invocation needs no arguments when the repository is reached through the script path:

```powershell
& '<MIKO repository share>\dist\IMOUTO-0.1.0-alpha.3-<revision>\Install-PalEventDirectorImouto.ps1'
```

If PowerShell marks network scripts as remote, invoke the same file from a trusted PowerShell session with the appropriate local execution policy. Do not weaken machine-wide execution policy solely for this installer.

The installer and generated launcher support the built-in Windows PowerShell 5.1 on IMOUTO. The startup banner suggesting a newer PowerShell release is informational; upgrading PowerShell is not required for deployment.

## Explicit laboratory activation

Ordinary installation does not auto-enable server mutation. To make the private IMOUTO laboratory work without hand-editing JSON, stop the server and run:

```powershell
& 'D:\SteamLibrary\steamapps\common\PalServer\PalEventDirectorDeployments\Enable-PalEventDirectorLaboratory.ps1'
```

The command requires explicit confirmation. It validates dedicated build `24575149`, the pinned UE4SS DLL/API `3.0.1`, deployment provenance, configuration schema 3, laboratory mode, command policy, and every mandatory warning offset. It creates a timestamped configuration backup and enables:

- `chatCommands`;
- `observeCombat`;
- `observeInvasions`;
- `startAllInvasions`; and
- `substituteBountyMembers`.

It sets the recommended `operatorOrPalworldAdmin` policy by default, pins the verified build/runtime allowlists, disables every recurring schedule, leaves the 10/5/1 warning sequence intact, and forcibly leaves `grantItems=false`. Its result reports `RestartRequired=True`. Optional `AuthorizationPolicy` values are `operatorOnly`, `palworldAdminOnly`, and `operatorOrPalworldAdmin`; `anyUser` is intentionally unavailable through this convenience command.

The activation validator accepts `siegeLeague.manualCountdownMinutes` from 0 through 60. Zero is an explicit immediate manual start; it does not alter the mandatory warning offsets retained on recurring schedules.

After restart through the generated launcher, authenticate with Palworld's built-in admin mechanism and run `!siege status`. PED reads the resulting server-side `APalPlayerController.bAdmin` Boolean fresh for each privileged command. It does not inspect the password or authorize by display name.

`StartInvaderMarchForBaseCamp` is a native `void` function. A normal Lua return means only that UE4SS completed the invocation. PED first calls one deterministic selected probe base, records masked native state immediately before and after it, and waits for a correlated `BroadcastInvaderStart`. Only that callback produces `RAID STARTED` and permits fanout. If no probe callback arrives before `startDiscoverySeconds`, PED records `event_start_failed`, skips the remaining calls, and emits no rankings, normal results, or rewards.

## One-time Production world seed

World data is intentionally separate from routine mod bundles because it contains private Production player data. From a clean, pushed MIKO revision, run `npm run build:world-seed`. The MIKO-only builder selects the newest managed daily backup that is at least ten minutes old, requires the nonempty settings file copied as the managed backup producer's final completion sentinel without reading or packaging its contents, verifies that the currently running Production process was launched after that snapshot, confirms every selected save predates the relaunch, reads the save files into immutable buffers, verifies they remain unchanged during the snapshot, and creates:

```text
dist\IMOUTO-WORLD-SEED-<snapshot>-<revision>\
```

That sensitive local bundle contains `Import-MikoProductionWorldImouto.ps1`, `world-seed.zip`, a per-file hash manifest, and bundle provenance. It contains only active `.sav` data below the one world directory; it omits the backup's `PalWorldSettings.ini` and redundant in-world `backup` history. Never publish or commit this directory.

The snapshot used for the first bundle was `daily_2026-09-03_150014`. It contains 13 primary character saves plus 5 `_dps` player sidecars, not 18 distinct characters.

Run the importer once on IMOUTO after installing the mod and while the IMOUTO dedicated server is stopped:

```powershell
& '<MIKO repository share>\dist\IMOUTO-WORLD-SEED-2026-09-03_150014-<revision>\Import-MikoProductionWorldImouto.ps1'
```

The importer:

1. requires local execution on the machine named IMOUTO;
2. validates the local dedicated-server App ID, build, executable, and server pak;
3. requires the IMOUTO server to be stopped and rejects reparse-point targets;
4. accepts only the immutable adjacent world-seed archive and per-file manifest produced on MIKO from a stable managed `daily_*` backup;
5. imports the active world, base/guild state, primary character saves, and player sidecars, excluding redundant in-world backup history;
6. snapshots the network archive locally and verifies every staged/destination file before changing or accepting IMOUTO;
7. moves any existing IMOUTO world and Pal Event Director runtime state into a unique local rollback directory;
8. changes only IMOUTO's `DedicatedServerName` world selector while preserving the rest of `GameUserSettings.ini`;
9. verifies that IMOUTO's `PalWorldSettings.ini` did not change; and
10. journals the replacement phases and records the source snapshot, world ID, primary/sidecar counts, byte count, and rollback path under `PalworldWorldSeedImports`.

If Pal Event Director has already booted, its runtime journal/snapshot is archived so stale event state cannot refer to the replaced world. Its existing `config.json` is preserved. Review that configuration before restart; enabled schedules remain configuration and can still fire after boot.

The first successful import creates a marker and refuses accidental repetition. `ReplaceExistingSeed` permits only a bundle with a newer managed-snapshot timestamp. A pending transaction marker blocks retries after an interrupted replacement until the prior rollback directory is reviewed. The normal target is fixed to `D:\SteamLibrary\steamapps\common\PalServer`.

This is a real copy of Production progression. Treat it as sensitive: do not publish or commit the save files, do not expose the DEV server publicly without authentication, and never copy DEV changes back to Production. Some copied characters may contain private player identity data. Players retain their copied guilds, bases, levels, and inventory as of the snapshot, but all DEV progression diverges permanently after import.

Mod-installer optional parameters:

| Parameter | Purpose |
|---|---|
| `ServerRoot` | Override the default IMOUTO dedicated-server path. The target must still pass the dedicated-server identity and hash gates. |
| `ArtifactPath` | Deploy a specific clean-build archive. Its adjacent `manifest.json` remains mandatory. |
| `RuntimeArchivePath` | Use an already downloaded pinned UE4SS archive instead of downloading it from GitHub. |
| `ExpectedSourceRevision` | Optional exact 40-character pushed commit SHA that must match the clean-build manifest. |
| `ReplaceExistingUe4ss` | Back up and replace a different/incomplete UE4SS runtime. Without this explicit switch, a mismatch aborts. |
| `DisableOtherUe4ssMods` | Disable existing enabled UE4SS mods. Without this explicit switch, any enabled non-PED mod aborts the deployment. |
| `WhatIf` | Show the target action without staging, downloading, or writing files. |

The world importer exposes only `ReplaceExistingSeed` and `WhatIf`; source and destination overrides are not available in normal execution.

## Installer behavior

The installer stages and validates everything before mutating the dedicated-server tree. It then:

1. creates a timestamped backup under `PalEventDirectorInstallerBackups`;
2. installs or preserves the exact pinned Palworld-specific UE4SS runtime;
3. disables UE4SS hot reload and debug consoles;
4. places the clean package under `Pal\Binaries\Win64\ue4ss\Mods\PalEventDirector`;
5. enables exactly Pal Event Director in both UE4SS mod-control files;
6. verifies installed runtime and package files again; and
7. installs verified `Start-PalEventDirectorImouto.ps1` and `Enable-PalEventDirectorLaboratory.ps1` commands; and
8. writes its verified manifest build ID, runtime API, data path, script hashes, and package provenance to `PalEventDirectorDeployments\deployment.json`.

If any mutation step fails, the installer removes the partial runtime and restores the backed-up UE4SS tree, proxy DLL, and prior deployment record. It never rolls back or edits Palworld saves because it never touches them.

Repeated deployment is supported. Every run replaces only the Pal Event Director package after preserving the preceding UE4SS/mod state in a new timestamped backup.

## Pinned dependencies

The current gate permits:

- Palworld Dedicated Server App ID `2394010`;
- server build ID `24575149`;
- server pak SHA-256 `bffab47cbd3b3c6d14d616376d4e0b060b2429a5eb4c2022820d4f38d36a0770`;
- Okaetsu Palworld UE4SS tag `2281fa31`;
- archive `UE4SS-Palworld-g2281fa31-zDev.zip`; and
- archive SHA-256 `3b5c8ad11ed7983edde08412eac214222749e83e4b47f12476741c6c536bf060`.

The installer downloads that exact GitHub release asset only when the pinned runtime is absent and no local archive is supplied. A newer Palworld server or UE4SS release fails closed until source compatibility, bytes, tests, and this pin are deliberately updated.

## First boot and configuration

The installed `Pal/Binaries/Win64/ue4ss/Mods/PalEventDirector/Scripts` layout resolves automatically to `Pal/Saved/PalEventDirector`; no manual data-directory variable is needed merely to load PED. The installer-generated launcher nevertheless supplies that same absolute path explicitly as defense in depth. The first successful server boot creates the persistent configuration and PED log there. Every capability remains disabled. Stop the IMOUTO server before editing the generated configuration and follow the staged laboratory gates in the alpha runbook.

Validate without starting:

```powershell
& 'D:\SteamLibrary\steamapps\common\PalServer\PalEventDirectorDeployments\Start-PalEventDirectorImouto.ps1' -ValidateOnly
```

Start for testing:

```powershell
& 'D:\SteamLibrary\steamapps\common\PalServer\PalEventDirectorDeployments\Start-PalEventDirectorImouto.ps1'
```

The launcher reads App ID and build ID from IMOUTO's Steam dedicated-server manifest, requires the deployment record to match, and exports `PAL_EVENT_DIRECTOR_SERVER_BUILD_ID` and `PAL_EVENT_DIRECTOR_DATA_DIR` only to the spawned PalServer process. It does not modify user/machine environment variables, Steam settings, the client, or MIKO.

Before enabling invasion mutation, record the exact value returned by `UE4SS.GetVersion()` and add it to `compatibility.allowedUe4ssVersions`. The process environment must also provide the allowlisted dedicated-server build ID. Do not infer the runtime version from its release tag.

Item grants remain validator-blocked in alpha.3.

## Manual test loop on IMOUTO

The Palworld client remains completely vanilla. For each meaningful revision:

- verify one UE4SS load and one Pal Event Director load;
- verify the client connects without a mod requirement or missing-content error;
- verify event red banners contain only short titles and the matching details arrive in Palworld system chat;
- verify the 10-, 5-, and 1-minute notices;
- verify `!siege start native 0` reaches dispatch without a countdown, while still enforcing every normal preflight and authorization gate;
- verify only bases belonging to guilds with an online member at the start boundary are requested;
- verify every online player and late joiner enters one global leaderboard regardless of guild;
- verify unrelated native incidents never score;
- verify cross-base contribution and final-hit tie-breaking;
- verify shutdown/restart recovery; and
- preserve logs, state, deployment record, and backup when a failure occurs.

For the selected-base versus native-all comparison, use two independent runs from the same disposable world snapshot:

1. In the first copy, run `!siege start native 0`. Preserve the PED journal/log and note the probe's masked pre/post `Selected-base native invasion state` records plus any declaration, selection, start, or arrival callbacks.
2. Stop IMOUTO and restore the same pre-test disposable snapshot. Do not reuse the mutated first-run world.
3. Start through the generated launcher, leave PED idle, and run `ped diagnose-native-all confirm-disposable-start-all` in the server console.
4. Preserve the resulting masked `native-all-before`, `native-all-after`, declaration, selection, start, and arrival records.
5. Compare map/flag transitions and callbacks. A normal return from either native function is not acceptance.

The native-all command is console-only, requires the exact confirmation token, creates no PED event or score, and must never be used as automatic fallback. It may target bases outside the online-guild policy.

Running the local client and dedicated server concurrently increases IMOUTO's CPU/GPU/RAM load. That load is isolated from MIKO Production, but performance observations should distinguish client contention from server/mod behavior.

## Rollback

Stop the IMOUTO dedicated server. The previous runtime/mod state is retained beneath the backup path reported by the installer. Restore the complete backed-up `ue4ss` directory and `dwmapi.dll` together; never mix files from two UE4SS releases. Restore or remove `deployment.json`, `Start-PalEventDirectorImouto.ps1`, and `Enable-PalEventDirectorLaboratory.ps1` together because the commands validate themselves against that deployment.

World-import rollback is separate. Keep IMOUTO stopped and use the path reported as `ImoutoBackup`. Preserve the replacement world for diagnosis, restore the backup's complete `SaveGames` directory, restore `GameUserSettings.ini`, restore the backup's `PalEventDirector` directory when present, and restore or remove the prior `PalworldWorldSeedImports` marker according to `backup.json`. Confirm `PalWorldSettings.ini` remained unchanged before starting. Never copy any IMOUTO world or event state back to MIKO Production.

A successful IMOUTO test is not authorization to deploy MIKO Production.
