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

The installer never modifies the Palworld client, Steam manifests, server configuration, world saves, Windows firewall, router, or MIKO. It does not start or stop the IMOUTO server.

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
9. Start the IMOUTO dedicated server through its normal local method.
10. Perform the manual vanilla-client checks on IMOUTO.

The normal invocation needs no arguments when the repository is reached through the script path:

```powershell
& '<MIKO repository share>\dist\IMOUTO-0.1.0-alpha.3-<revision>\Install-PalEventDirectorImouto.ps1'
```

If PowerShell marks network scripts as remote, invoke the same file from a trusted PowerShell session with the appropriate local execution policy. Do not weaken machine-wide execution policy solely for this installer.

The installer supports the built-in Windows PowerShell 5.1 on IMOUTO. The startup banner suggesting a newer PowerShell release is informational; upgrading PowerShell is not required for deployment.

Optional parameters:

| Parameter | Purpose |
|---|---|
| `ServerRoot` | Override the default IMOUTO dedicated-server path. The target must still pass the dedicated-server identity and hash gates. |
| `ArtifactPath` | Deploy a specific clean-build archive. Its adjacent `manifest.json` remains mandatory. |
| `RuntimeArchivePath` | Use an already downloaded pinned UE4SS archive instead of downloading it from GitHub. |
| `ExpectedSourceRevision` | Optional exact 40-character pushed commit SHA that must match the clean-build manifest. |
| `ReplaceExistingUe4ss` | Back up and replace a different/incomplete UE4SS runtime. Without this explicit switch, a mismatch aborts. |
| `DisableOtherUe4ssMods` | Disable existing enabled UE4SS mods. Without this explicit switch, any enabled non-PED mod aborts the deployment. |
| `WhatIf` | Show the target action without staging, downloading, or writing files. |

## Installer behavior

The installer stages and validates everything before mutating the dedicated-server tree. It then:

1. creates a timestamped backup under `PalEventDirectorInstallerBackups`;
2. installs or preserves the exact pinned Palworld-specific UE4SS runtime;
3. disables UE4SS hot reload and debug consoles;
4. places the clean package under `Pal\Binaries\Win64\ue4ss\Mods\PalEventDirector`;
5. enables exactly Pal Event Director in both UE4SS mod-control files;
6. verifies installed runtime and package files again; and
7. writes provenance to `PalEventDirectorDeployments\deployment.json`.

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

The first successful server boot creates the persistent Pal Event Director configuration below the IMOUTO server's save directory. Every capability remains disabled. Stop the IMOUTO server before editing the generated configuration and follow the staged laboratory gates in the alpha runbook.

Before enabling invasion mutation, record the exact value returned by `UE4SS.GetVersion()` and add it to `compatibility.allowedUe4ssVersions`. The process environment must also provide the allowlisted dedicated-server build ID. Do not infer the runtime version from its release tag.

Item grants remain validator-blocked in alpha.3.

## Manual test loop on IMOUTO

The Palworld client remains completely vanilla. For each meaningful revision:

- verify one UE4SS load and one Pal Event Director load;
- verify the client connects without a mod requirement or missing-content error;
- verify the 10-, 5-, and 1-minute notices;
- verify only bases belonging to guilds with an online member at the start boundary are requested;
- verify every online player and late joiner enters one global leaderboard regardless of guild;
- verify unrelated native incidents never score;
- verify cross-base contribution and final-hit tie-breaking;
- verify shutdown/restart recovery; and
- preserve logs, state, deployment record, and backup when a failure occurs.

Running the local client and dedicated server concurrently increases IMOUTO's CPU/GPU/RAM load. That load is isolated from MIKO Production, but performance observations should distinguish client contention from server/mod behavior.

## Rollback

Stop the IMOUTO dedicated server. The previous runtime/mod state is retained beneath the backup path reported by the installer. Restore the complete backed-up `ue4ss` directory and `dwmapi.dll` together; never mix files from two UE4SS releases. Restore the previous deployment record if provenance history matters.

A successful IMOUTO test is not authorization to deploy MIKO Production.
