param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$materialRoot = Join-Path $ProjectRoot 'assets/airport/terrazzo'
$source = Get-Content -LiteralPath (Join-Path $materialRoot 'source.json') -Raw | ConvertFrom-Json
$needsDownload = $false
foreach ($map in $source.maps) {
    $destination = Join-Path $materialRoot $map.file
    if (-not (Test-Path -LiteralPath $destination) -or (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLower() -ne $map.sha256) { $needsDownload = $true }
}
if ($needsDownload) {
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('airport-terrazzo-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    $archive = Join-Path $stagingRoot 'Tiles040_2K-JPG.zip'
    Invoke-WebRequest -Uri $source.download -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLower() -ne $source.archive_sha256) { throw 'Terrazzo archive checksum mismatch' }
    Expand-Archive -LiteralPath $archive -DestinationPath $stagingRoot
    foreach ($pair in @(@('Color', 'albedo.jpg'), @('NormalGL', 'normal.jpg'), @('Roughness', 'roughness.jpg'))) {
        Copy-Item -LiteralPath (Join-Path $stagingRoot ('Tiles040_2K-JPG_' + $pair[0] + '.jpg')) -Destination (Join-Path $materialRoot $pair[1])
    }
}
foreach ($map in $source.maps) {
    if ((Get-FileHash -LiteralPath (Join-Path $materialRoot $map.file) -Algorithm SHA256).Hash.ToLower() -ne $map.sha256) { throw ('Terrazzo map checksum mismatch: ' + $map.file) }
}
Write-Output 'Verified CC0 ambientCG Tiles040 Color, OpenGL Normal and Roughness maps.'
