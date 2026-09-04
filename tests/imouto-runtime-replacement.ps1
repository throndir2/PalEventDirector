Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installer = Join-Path $repository 'operations\imouto\Install-PalEventDirectorImouto.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Installer has parse errors.' }
# Load only pure filesystem helpers, never the installer's operational body.
foreach ($name in @('Assert-NoReparseTree', 'Remove-InstallationTarget', 'Get-InstallationInventory', 'Assert-InstallationInventory')) {
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $definition) { throw "Missing installer filesystem helper: $name" }
    . ([ScriptBlock]::Create($definition.Extent.Text))
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('ped-runtime-replacement-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'staged'
$destination = Join-Path $root 'installed'
$locked = $null
try {
    New-Item -ItemType Directory -Path $source, $destination -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'known.txt'), 'audited runtime fixture')
    [IO.File]::WriteAllText((Join-Path $destination 'retained.txt'), 'must not be adopted')
    $locked = [IO.File]::Open((Join-Path $destination 'retained.txt'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $blocked = $false
    try { Remove-InstallationTarget -Path $destination } catch { $blocked = $true }
    if (-not $blocked) { throw 'Locked runtime removal did not fail closed.' }
    if (-not (Test-Path (Join-Path $destination 'retained.txt'))) { throw 'Locked sentinel unexpectedly disappeared.' }
    $locked.Dispose()
    $locked = $null
    Remove-InstallationTarget -Path $destination
    if (Test-Path $destination) { throw 'Complete removal left an existing destination.' }
    $expected = Get-InstallationInventory -Root $source
    Copy-Item $source $destination -Recurse
    Assert-InstallationInventory -Root $destination -Expected $expected
    [IO.File]::WriteAllText((Join-Path $destination 'unknown.txt'), 'unexpected')
    $blocked = $false
    try { Assert-InstallationInventory -Root $destination -Expected $expected } catch { $blocked = $true }
    if (-not $blocked) { throw 'Extra runtime file was self-attested instead of rejected.' }
    Remove-Item (Join-Path $destination 'unknown.txt')
    [IO.File]::AppendAllText((Join-Path $destination 'known.txt'), 'tampered')
    $blocked = $false
    try { Assert-InstallationInventory -Root $destination -Expected $expected } catch { $blocked = $true }
    if (-not $blocked) { throw 'Changed runtime bytes were self-attested instead of rejected.' }
    Write-Output 'PASS runtime removal fails closed on retained files; immutable staged inventory rejects unknown and modified bytes'
} finally {
    if ($locked) { $locked.Dispose() }
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}