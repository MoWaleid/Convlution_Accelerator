param(
    [ValidateSet('Software')][string]$Suite = 'Software',
    [string]$ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Python = '',
    [ValidateRange(30,3600)][int]$ToolTimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not $Python) { $Python = Join-Path $ProjectRoot '.venv\Scripts\python.exe' }
$Python = (Resolve-Path -LiteralPath $Python).Path
$runRoot = Join-Path ([IO.Path]::GetTempPath()) ('m7_profiles_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot | Out-Null
Write-Output "M7_LOG_ROOT $runRoot"

# Machine-independence note: this host has a shadowing
# Microsoft.PowerShell.Utility v7.0.0.0 manifest in Program Files that hides
# Get-FileHash from Windows PowerShell 5.1 sessions. Hash via .NET directly so
# the suite depends only on the base framework, not module resolution.
function Get-Sha256Hex([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            return ([System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-','').ToLowerInvariant()
        } finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
}

function Quote-PS([string]$Value) { return "'" + $Value.Replace("'","''") + "'" }
function Invoke-Bounded {
    param([string]$Exe,[string[]]$Arguments,[string]$Directory,[string]$Log,[switch]$AllowFailure)
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "Missing executable: $Exe" }
    $command = '& ' + (Quote-PS $Exe) + ' ' + (($Arguments | ForEach-Object {Quote-PS $_}) -join ' ')
    $child = '$ErrorActionPreference="Stop"; try { Set-Location -LiteralPath ' +
        (Quote-PS $Directory) + '; $ErrorActionPreference="Continue"; ' + $command + ' *> ' + (Quote-PS $Log) +
        '; exit $LASTEXITCODE } catch { $_ | Out-File -Append -LiteralPath ' +
        (Quote-PS $Log) + '; exit 1 }'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
    $process = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded)
    $null = $process.Handle
    if (-not $process.WaitForExit($ToolTimeoutSeconds*1000)) {
        # Kill only this timed-out child tree; retain all logs and snapshots.
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        throw "M7_TIMEOUT $Log"
    }
    $process.Refresh()
    if ($process.ExitCode -ne 0 -and -not $AllowFailure) {
        throw "M7_FAIL exit=$($process.ExitCode) log=$Log"
    }
    return $process.ExitCode
}
if ($Suite -eq 'Software') {
    $log = Join-Path $runRoot 'software.log'
    $null = Invoke-Bounded $Python @('-B','-m','unittest','-v','tests.test_m7_profiles') (Join-Path $ProjectRoot 'software') $log
    $text = Get-Content -Raw -LiteralPath $log
    if ($text -notmatch '(?m)^Ran [1-9][0-9]* tests? in ' -or
        $text -notmatch '(?m)^OK\s*$' -or $text -match '(?m)^FAILED|^ERROR:|^FAIL:') {
        throw "M7_FAIL missing software self-check completion: $log"
    }
    Write-Output "M7_SOFTWARE_PASS $log"
}
Write-Output "M7_FOCUSED_PASS suite=$Suite logs=$runRoot"
