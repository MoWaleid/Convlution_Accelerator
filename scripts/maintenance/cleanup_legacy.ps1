param(
    [ValidateSet('Generated', 'Historical')]
    [string[]]$Scope = @('Generated'),
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ($repo -ne 'D:\MyProjects\Convlution_Accelerator') {
    throw "Unexpected repository root: $repo"
}

# This helper is intentionally project-only. It never touches VMShare, other
# repositories, user documents, or external checkpoint directories.
$generatedTargets = @(
    '.venv', 'work', 'profile_builds', 'tmp', '.Xil',
    'Convlution_Accelerator.cache', 'Convlution_Accelerator.gen',
    'Convlution_Accelerator.hw', 'Convlution_Accelerator.ip_user_files',
    'Convlution_Accelerator.runs', 'Convlution_Accelerator.sim', 'xsim.dir',
    'golden_model\cifar-10-python.tar.gz',
    'golden_model\data\cifar10_raw',
    'golden_model\data\cifar10_images',
    'golden_model\__pycache__'
)

$historicalTargets = @(
    'checkpoints', 'debug_captures', 'profiles\history',
    'report\research_builds\B32_CFGLUT100',
    'scripts\research_release\builds\B32_CFGLUT100.spec.tcl',
    'software\hardware_B32_CFGLUT100.json',
    'software\hardware_A.json', 'software\hardware_B.json',
    'software\hardware_C.json', 'software\hardware_D.json',
    'software\hardware_D640.json',
    'CLEANUP_SCAN_20260914.md', 'feedback.md',
    'HANDOFF_v1bringup_to_edgefree125.md', 'INTEGRATION_PLAN_M10_M12.md',
    'M10_DECISION_RECORD.md', 'M10_RESUME_HANDOFF.md',
    'M7_CONTINUATION.md', 'M7_FIX_PLAN.md', 'M7_STATE.md',
    'M9_CHECKLIST.md', 'RELEASE_MANIFEST_v1-m9-release.md',
    'm4_final_utilization.rpt', 'dfx_runtime.txt',
    'build_b32.jou', 'build_b32.log', 'retry_open_fs.log',
    'vivado.jou', 'vivado.log'
)

function Get-Bytes([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    if (-not $item.PSIsContainer) { return [long]$item.Length }
    return [long]((Get-ChildItem -LiteralPath $Path -Recurse -Force -File |
        Measure-Object Length -Sum).Sum)
}

$relative = @()
if ('Generated' -in $Scope) { $relative += $generatedTargets }
if ('Historical' -in $Scope) { $relative += $historicalTargets }
$relative = @($relative | Sort-Object -Unique)

$candidates = foreach ($entry in $relative) {
    $full = [IO.Path]::GetFullPath((Join-Path $repo $entry))
    if (-not $full.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside project root: $full"
    }
    if (Test-Path -LiteralPath $full) {
        [pscustomobject]@{ Path = $full; Bytes = Get-Bytes $full }
    }
}
$candidates = @($candidates)
$total = [long](($candidates | Measure-Object Bytes -Sum).Sum)

$candidates | Sort-Object Bytes -Descending | ForEach-Object {
    '{0,10:N2} MiB  {1}' -f ($_.Bytes / 1MB), $_.Path
}
'REVIEW: {0:N2} MiB across {1} project-local targets' -f ($total / 1MB), $candidates.Count

if (-not $Execute) {
    'DRY RUN ONLY. Re-run with -Execute only after reviewing every target.'
    exit 0
}

foreach ($candidate in $candidates) {
    Remove-Item -LiteralPath $candidate.Path -Recurse -Force
    "REMOVED  $($candidate.Path)"
}
'CLEANUP COMPLETE: {0:N2} MiB selected' -f ($total / 1MB)
