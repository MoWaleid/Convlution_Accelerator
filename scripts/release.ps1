param(
    [ValidateSet('All','Test','Build','Package','Check')][string]$Action = 'All',
    [string]$Vivado = 'vivado',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path $PSScriptRoot -Parent
Push-Location -LiteralPath $releaseRoot
try {
    $metadata = Get-Content -Raw -LiteralPath 'release/hardware.json' | ConvertFrom-Json
    $mhz = $metadata.accelerator.clock_mhz
    if ($Action -in @('All','Test')) {
        & $Python software/tests/test_edgefree_release.py
        if ($LASTEXITCODE -ne 0) { throw 'Host package/runner regression failed' }
        & $Vivado -mode batch -source scripts/release_test.tcl -log release_test.log -journal release_test.jou
        if ($LASTEXITCODE -ne 0) { throw 'RTL regression failed' }
    }
    if ($Action -in @('All','Build')) {
        & $Vivado -mode batch -source scripts/release_build.tcl -log release_build.log -journal release_build.jou
        if ($LASTEXITCODE -ne 0) { throw 'Hardware build failed; inspect release_build.log' }
    }
    if ($Action -in @('All','Package')) {
        & $Python scripts/package_release.py --out "dist/edgefree$mhz"
        if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
    }
    if ($Action -in @('All','Check')) {
        & $Python "dist/edgefree$mhz/software/edgefree_board.py" --check-only
        if ($LASTEXITCODE -ne 0) { throw 'Package integrity/reference check failed' }
    }
} finally { Pop-Location }
