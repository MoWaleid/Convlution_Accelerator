param(
    [string]$ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$VivadoBin = 'D:\Program_Files_2\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$buildDir = Join-Path ([System.IO.Path]::GetTempPath()) (
    'conv_axi_address_' + [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $buildDir | Out-Null
Write-Output "Fresh XSim build: $buildDir"

function Invoke-XilinxTool {
    param([string]$Tool, [string[]]$ToolArguments)
    $executable = Join-Path $VivadoBin ($Tool + '.bat')
    Write-Output ("COMMAND: {0} {1}" -f $executable, ($ToolArguments -join ' '))
    & $executable @ToolArguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE; build retained: $buildDir"
    }
}

# Compile source RTL directly. Never open/save the project or regenerate BD/IP.
$rtlDir = Join-Path $ProjectRoot 'Convlution_Accelerator.srcs\sources_1\new'
$vhdlNames = @(
    'config_pkg.vhd', 'conv_pkg.vhd', 'coeff_bias_shift_regfile.vhd',
    'axi_lite_ctrl.vhd', 'sync_fifo.vhd', 'axi_stream_input_frontend.vhd',
    'axi_stream_output_serializer.vhd', 'window_generator.vhd',
    'conv_channel.vhd', 'conv_engine.vhd', 'conv_top.vhd', 'conv_axis_wrapper.vhd'
)
$vhdlPaths = @($vhdlNames | ForEach-Object { Join-Path $rtlDir $_ })
$adapter = Join-Path $rtlDir 'conv_axis_wrapper_bd.v'
$testbench = Join-Path $PSScriptRoot 'tb_axi_address_normalization.sv'
$snapshot = 'tb_axi_address_normalization_sim'

Push-Location -LiteralPath $buildDir
try {
    Invoke-XilinxTool -Tool 'xvhdl' -ToolArguments (@('--2008') + $vhdlPaths)
    Invoke-XilinxTool -Tool 'xvlog' -ToolArguments @($adapter)
    Invoke-XilinxTool -Tool 'xvlog' -ToolArguments @('--sv', $testbench)
    Invoke-XilinxTool -Tool 'xelab' -ToolArguments @(
        '--debug', 'typical', '--mt', '2', 'work.tb_axi_address_normalization',
        '-s', $snapshot
    )
    Invoke-XilinxTool -Tool 'xsim' -ToolArguments @(
        $snapshot, '-runall', '-log', 'adapter_simulation.log'
    )
    # XSim can return zero after HDL failure; require the explicit PASS marker.
    $simulationLog = Get-Content -Raw -LiteralPath 'adapter_simulation.log'
    if ($simulationLog -notmatch 'PASS: AXI physical address normalization' -or
        $simulationLog -match '(?m)^Fatal:|FAIL:|WATCHDOG:') {
        throw "Adapter regression failed; inspect $buildDir\adapter_simulation.log"
    }
    Write-Output 'Verified: real Verilog adapter + complete VHDL hierarchy passed.'
} finally {
    Pop-Location
}
