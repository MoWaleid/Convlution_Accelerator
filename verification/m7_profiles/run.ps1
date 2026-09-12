param(
    [ValidateSet('Software','RTL','All')][string]$Suite = 'All',
    [string]$ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$VivadoBin = 'D:\Program_Files_2\2025.2\Vivado\bin',
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
if ($Suite -in @('Software','All')) {
    $log = Join-Path $runRoot 'software.log'
    $null = Invoke-Bounded $Python @('-B','-m','unittest','-v','tests.test_m7_profiles') (Join-Path $ProjectRoot 'software') $log
    $text = Get-Content -Raw -LiteralPath $log
    if ($text -notmatch '(?m)^Ran [1-9][0-9]* tests? in ' -or
        $text -notmatch '(?m)^OK\s*$' -or $text -match '(?m)^FAILED|^ERROR:|^FAIL:') {
        throw "M7_FAIL missing software self-check completion: $log"
    }
    Write-Output "M7_SOFTWARE_PASS $log"
}
if ($Suite -in @('RTL','All')) {
    foreach ($tool in @('xvhdl','xvlog','xelab','xsim')) {
        if (-not (Test-Path -LiteralPath (Join-Path $VivadoBin "$tool.bat"))) {
            throw "Missing Vivado tool $tool in $VivadoBin"
        }
    }
    $names = @('config_pkg.vhd','conv_pkg.vhd','coeff_bias_shift_regfile.vhd',
        'axi_lite_ctrl.vhd','sync_fifo.vhd','axi_stream_input_frontend.vhd',
        'axi_stream_output_serializer.vhd','window_generator.vhd','conv_channel.vhd',
        'conv_engine.vhd','conv_top.vhd','conv_axis_wrapper.vhd')
    foreach ($case in @('A32','B32','C32','D32','D640','B32_reject_A32')) {
        $negative = $case -eq 'B32_reject_A32'
        $profile = if ($negative) {'B32'} else {$case}
        $directory = Join-Path $runRoot $case
        New-Item -ItemType Directory -Path $directory | Out-Null
        $inputDir = Join-Path $directory 'inputs'
        $null = Invoke-Bounded $Python @('-B',(Join-Path $ProjectRoot 'scripts\prepare_profile.py'),
            '--profile',$profile,'--out',$inputDir) $directory (Join-Path $directory 'prepare.log')
        # Verify snapshot before any intentional negative-test mutation.
        foreach ($line in Get-Content -LiteralPath (Join-Path $inputDir 'SHA256SUMS.txt')) {
            if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw 'Malformed input checksum' }
            $expected = $Matches[1]; $relative = $Matches[2]
            $actual = Get-Sha256Hex (Join-Path $inputDir $relative)
            if ($actual -ne $expected) { throw "Snapshot hash mismatch: $relative" }
        }
        if ($negative) {
            $wrapper = Join-Path $inputDir 'rtl\conv_axis_wrapper.vhd'
            $text = [IO.File]::ReadAllText($wrapper)
            $pattern = '(C_BUILD_ID\s*:\s*std_logic_vector\(127 downto 0\)\s*:=\s*)CFG_BUILD_ID'
            if ([regex]::Matches($text,$pattern).Count -ne 1) { throw 'Cannot inject A32 leakage test' }
            $text = [regex]::Replace($text,$pattern,'${1}x"4d344e334b385733322d323630393131"')
            [IO.File]::WriteAllText($wrapper,$text,[Text.UTF8Encoding]::new($false))
            'Intentional fault: only isolated outer wrapper default changed to A32; original snapshot hashes retained.' |
                Set-Content -LiteralPath (Join-Path $directory 'fault_injection.txt')
        }
        Copy-Item -LiteralPath (Join-Path $inputDir 'expected.svh') -Destination $directory
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tb_m7_profile.sv') -Destination $directory
        $paths = @($names | ForEach-Object {Join-Path $inputDir "rtl\$_"})
        $null = Invoke-Bounded (Join-Path $VivadoBin 'xvhdl.bat') (@('--2008')+$paths) $directory (Join-Path $directory 'compile_vhdl.log')
        $null = Invoke-Bounded (Join-Path $VivadoBin 'xvlog.bat') @(
            (Join-Path $inputDir 'rtl\conv_axis_wrapper_bd.v')) $directory (Join-Path $directory 'compile_adapter.log')
        $null = Invoke-Bounded (Join-Path $VivadoBin 'xvlog.bat') @('--sv','tb_m7_profile.sv') $directory (Join-Path $directory 'compile_test.log')
        $elabExit = Invoke-Bounded (Join-Path $VivadoBin 'xelab.bat') @('--debug','typical','--mt','2',
            'work.tb_m7_profile','-s','m7_profile_sim') $directory (Join-Path $directory 'elaborate.log') -AllowFailure
        if ($elabExit -ne 0) {
            $elabText = Get-Content -Raw -LiteralPath (Join-Path $directory 'elaborate.log')
            if ($negative -and $elabText -match 'M7_PROFILE_ID_MISMATCH') {
                Write-Output "M7_ID_LEAK_REJECT_PASS $directory (elaboration rejection)"
                continue
            }
            throw "M7_FAIL elaboration: $directory"
        }
        $exitCode = Invoke-Bounded (Join-Path $VivadoBin 'xsim.bat') @('m7_profile_sim','-runall',
            '-log','simulation.log') $directory (Join-Path $directory 'xsim_console.log') -AllowFailure
        $text = Get-Content -Raw -LiteralPath (Join-Path $directory 'simulation.log')
        if ($negative) {
            if ($text -notmatch 'M7_PROFILE_ID_MISMATCH' -or $text -match 'M7_RTL_PASS') {
                throw "M7_FAIL expected ID rejection missing: $directory"
            }
            Write-Output "M7_ID_LEAK_REJECT_PASS $directory"
        } else {
            if ($exitCode -ne 0 -or $text -notmatch 'M7_RTL_PASS .*checks=42' -or
                $text -match '(?i)M7_FAIL|M7_WATCHDOG|Fatal:|Failure:|Error:') {
                throw "M7_FAIL integrated discovery: $directory"
            }
            Write-Output "M7_PROFILE_PASS $profile $directory"
        }
    }
    Write-Output "M7_RTL_SUITE_PASS $runRoot"
}
Write-Output "M7_FOCUSED_PASS suite=$Suite logs=$runRoot"
