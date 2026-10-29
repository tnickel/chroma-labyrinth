param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot), [string]$PythonExecutable = 'python')
$ErrorActionPreference = 'Stop'
$airportAssetRoot = Join-Path $ProjectRoot 'assets/airport'
New-Item -ItemType Directory -Path $airportAssetRoot -Force | Out-Null
$airportSelections = @(
    @{ id='large_floor_tiles_02'; resolution='2k'; folder='stone' },
    @{ id='wood_table_001'; resolution='1k'; folder='wood' },
    @{ id='leather_white'; resolution='1k'; folder='leather' },
    @{ id='denmin_fabric_02'; resolution='1k'; folder='fabric' },
    @{ id='smooth_concrete_floor'; resolution='1k'; folder='concrete' },
    @{ id='concrete_tiles_02'; resolution='2k'; folder='apron_concrete'; normal_format='jpg' },
    @{ id='clean_asphalt'; resolution='1k'; folder='asphalt' }
)
$airportManifest = @()
foreach ($selection in $airportSelections) {
    $files = Invoke-RestMethod -Uri ('https://api.polyhaven.com/files/' + $selection.id)
    $folder = Join-Path $airportAssetRoot $selection.folder
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    foreach ($map in @(@{api='Diffuse';name='albedo'}, @{api='nor_gl';name='normal'}, @{api='Rough';name='roughness'})) {
        $formats = $files.($map.api).($selection.resolution)
        $format = if ($map.name -eq 'normal' -and $selection.normal_format) { $selection.normal_format } elseif ($map.name -eq 'normal' -and $formats.png) { 'png' } else { 'jpg' }
        $remote = $formats.($format)
        if (-not $remote.url) { throw ('Missing map: ' + $selection.id + '/' + $map.api) }
        $relative = $selection.folder + '/' + $map.name + '.' + $format
        $destination = Join-Path $airportAssetRoot $relative
        if (-not (Test-Path -LiteralPath $destination) -or (Get-FileHash -LiteralPath $destination -Algorithm MD5).Hash.ToLower() -ne $remote.md5) {
            Invoke-WebRequest -Uri $remote.url -OutFile $destination
        }
        if ((Get-FileHash -LiteralPath $destination -Algorithm MD5).Hash.ToLower() -ne $remote.md5) { throw ('Checksum mismatch: ' + $relative) }
        $airportManifest += @{file=$relative; asset=$selection.id; source=('https://polyhaven.com/a/' + $selection.id); url=$remote.url; md5=$remote.md5; license='CC0-1.0'}
    }
    Write-Output ('Verified PBR maps: ' + $selection.id)
}
$airportSkyId = 'kloofendal_48d_partly_cloudy_puresky'
$airportSkyFiles = Invoke-RestMethod -Uri ('https://api.polyhaven.com/files/' + $airportSkyId)
$airportSkyRemote = $airportSkyFiles.hdri.'2k'.hdr
$airportSkyPath = Join-Path $airportAssetRoot 'daylight_2k.hdr'
if (-not (Test-Path -LiteralPath $airportSkyPath) -or (Get-FileHash -LiteralPath $airportSkyPath -Algorithm MD5).Hash.ToLower() -ne $airportSkyRemote.md5) {
    Invoke-WebRequest -Uri $airportSkyRemote.url -OutFile $airportSkyPath
}
if ((Get-FileHash -LiteralPath $airportSkyPath -Algorithm MD5).Hash.ToLower() -ne $airportSkyRemote.md5) { throw 'Sky checksum mismatch' }
$airportManifest += @{file='daylight_2k.hdr'; asset=$airportSkyId; source=('https://polyhaven.com/a/' + $airportSkyId); url=$airportSkyRemote.url; md5=$airportSkyRemote.md5; license='CC0-1.0'}
$airportManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $airportAssetRoot 'sources.json') -Encoding utf8
Write-Output 'All airport texture checksums verified.'
$airportEarthPath = Join-Path $airportAssetRoot 'earth_july_5400.jpg'
$airportEarthHash = 'f55226d46d27e05511f2118dc6aa24f5dbf9b6b2cddc87cc6e0e7dd067c00b11'
if (-not (Test-Path -LiteralPath $airportEarthPath) -or (Get-FileHash -LiteralPath $airportEarthPath -Algorithm SHA256).Hash.ToLower() -ne $airportEarthHash) {
    Invoke-WebRequest -Uri 'https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/july/world.200407.3x5400x2700.jpg' -OutFile $airportEarthPath
}
if ((Get-FileHash -LiteralPath $airportEarthPath -Algorithm SHA256).Hash.ToLower() -ne $airportEarthHash) { throw 'NASA image checksum mismatch' }
Write-Output 'NASA Earth composite SHA256 verified (separate usage terms in EARTH-SOURCE.txt).'
$airportRegionalPath = Join-Path $airportAssetRoot 'earth_mediterranean_500m.jpg'
$airportRegionalManifest = Get-Content -LiteralPath (Join-Path $airportAssetRoot 'earth-region-source.json') -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $airportRegionalPath) -or (Get-FileHash -LiteralPath $airportRegionalPath -Algorithm SHA256).Hash.ToLower() -ne $airportRegionalManifest.sha256) {
    & $PythonExecutable (Join-Path $PSScriptRoot 'fetch_airport_earth.py') --project-root $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw 'NASA regional image rebuild failed (requires Python 3 and Pillow).' }
}
Write-Output 'NASA 500-m Mediterranean region verified.'
