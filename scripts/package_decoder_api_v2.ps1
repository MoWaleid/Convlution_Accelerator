$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stage = Join-Path $root 'work/board_update_decoder_api_v2_20260925'
$archive = Join-Path $root 'deploy/board_updates/conv_lab_decoder_api_v2_20260925.tar.gz'
$sidecar = "$archive.sha256"

if (Test-Path -LiteralPath $stage) {
    throw "Stage already exists: $stage"
}
if (Test-Path -LiteralPath $archive) {
    throw "Archive already exists: $archive"
}

$destination = Join-Path $stage 'home/petalinux/conv_lab'
New-Item -ItemType Directory -Path $destination -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $root 'software/conv_lab/preprocessing.py') `
    -Destination (Join-Path $destination 'preprocessing.py')
Copy-Item -LiteralPath (Join-Path $root 'software/conv_lab/_decoder_worker.py') `
    -Destination (Join-Path $destination '_decoder_worker.py')

$entries = @(
    'home/petalinux/conv_lab/preprocessing.py'
    'home/petalinux/conv_lab/_decoder_worker.py'
)
$lines = foreach ($entry in $entries) {
    $path = Join-Path $stage $entry
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $entry"
}
[IO.File]::WriteAllText(
    (Join-Path $stage 'SHA256SUMS.txt'),
    (($lines -join "`n") + "`n"),
    [Text.UTF8Encoding]::new($false)
)

& tar.exe -czf $archive -C $stage .
if ($LASTEXITCODE -ne 0) {
    throw 'tar creation failed'
}

$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(
    $sidecar,
    "$archiveHash  $([IO.Path]::GetFileName($archive))`n",
    [Text.UTF8Encoding]::new($false)
)

Write-Output "ARCHIVE: $archive"
Write-Output "SHA256: $archiveHash"
