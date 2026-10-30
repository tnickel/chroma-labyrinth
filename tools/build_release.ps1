#requires -Version 5.1
<#
.SYNOPSIS
Build the offline Windows-x64 ZIP; does not install, download, commit or publish.
.EXAMPLE
.\tools\build_release.ps1 -GodotExe 'C:\Tools\Godot\godot.exe' -Version '0.1.0'
#>
[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$')]
    [string]$Version,
    [string]$OutputRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$buildRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build'))
$utf8 = New-Object Text.UTF8Encoding($false)

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}

function Resolve-Godot([string]$Requested) {
    if ($Requested) {
        if (Test-Path -LiteralPath $Requested -PathType Leaf) {
            return (Resolve-Path -LiteralPath $Requested).ProviderPath
        }
        $found = Get-Command $Requested -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.Source }
        throw "Godot executable not found: $Requested"
    }
    foreach ($candidate in @('godot.exe', 'godot4.exe', 'Godot_v4.7.2-stable_win64_console.exe', 'Godot_v4.7.2-stable_win64.exe')) {
        $found = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.Source }
    }
    throw 'Godot is not on PATH. Pass -GodotExe with an explicit executable path.'
}

function Invoke-GodotStep([string]$Name, [string[]]$Arguments) {
    $consoleLog = Join-Path $script:logRoot ($Name + '-console.log')
    $lines = New-Object 'System.Collections.Generic.List[string]'
    Write-Host "Godot: $Name"
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell presents native stderr as ErrorRecords. Capture it
        # first, then judge the native exit status and Godot error text together.
        $ErrorActionPreference = 'Continue'
        & $script:resolvedGodot @Arguments 2>&1 | ForEach-Object {
            $line = [regex]::Replace($_.ToString(), '\x1b\[[0-9;]*m', '')
            $lines.Add($line)
            Write-Host $line
        }
        $nativeExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    $text = $lines -join [Environment]::NewLine
    Write-Utf8 $consoleLog $text
    $engineLog = Join-Path $script:logRoot ($Name + '-engine.log')
    if (Test-Path -LiteralPath $engineLog) {
        $text += [Environment]::NewLine + [IO.File]::ReadAllText($engineLog)
    }
    if ($nativeExit -ne 0 -or $text -match '(?im)^\s*(SCRIPT ERROR|ERROR)\s*:' -or $text -match '(?i)failed to export|export failed|failed to load script') {
        throw "Godot $Name failed (exit $nativeExit). Inspect $consoleLog"
    }
    return ($lines -join [Environment]::NewLine)
}

try {
    $resolvedGodot = Resolve-Godot $GodotExe
    if (-not $OutputRoot) { $OutputRoot = $buildRoot }
    if (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $projectRoot $OutputRoot }
    $OutputRoot = [IO.Path]::GetFullPath($OutputRoot).TrimEnd([char[]]'\/')
    # Keep all generated packages, helpers and logs inside the ignored build tree.
    if ($OutputRoot -ne $buildRoot -and -not $OutputRoot.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputRoot must be the ignored project build directory or a child: $buildRoot"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'export_presets.cfg'))) { throw 'export_presets.cfg is missing.' }
    $packageName = 'Chroma-Labyrinth-' + $Version + '-windows-x64'
    $runName = $packageName + '-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $runRoot = Join-Path $OutputRoot $runName
    $packageRoot = Join-Path $runRoot $packageName
    $logRoot = Join-Path $runRoot 'logs'
    [void][IO.Directory]::CreateDirectory($packageRoot)
    [void][IO.Directory]::CreateDirectory($logRoot)
    # Git ignore rules do not prevent Godot from importing cached source images.
    # Keep raw astronomy downloads and previous exports outside its asset scan.
    Write-Utf8 (Join-Path $buildRoot '.gdignore') ''
    $engineVersion = (Invoke-GodotStep 'version' @('--version')).Trim()
    [void](Invoke-GodotStep 'import' @('--headless', '--path', $projectRoot, '--log-file', (Join-Path $logRoot 'import-engine.log'), '--import'))

    $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $sourceCommit = (& $git.Source -C $projectRoot rev-parse --verify HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[a-f0-9]{40,64}$') { throw 'Cannot identify the source Git commit.' }
    $sourceStatus = (& $git.Source -C $projectRoot status --porcelain --untracked-files=normal | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine whether the source checkout is clean.' }
    if ($sourceStatus) { throw 'Release source is not clean. Commit the intended source before building a published release.' }

    $exe = Join-Path $packageRoot 'Chroma-Labyrinth.exe'
    [void](Invoke-GodotStep 'export' @('--headless', '--path', $projectRoot, '--log-file', (Join-Path $logRoot 'export-engine.log'), '--export-release', 'Windows Desktop', $exe))
    $pck = Join-Path $packageRoot 'Chroma-Labyrinth.pck'
    foreach ($file in @($exe, $pck)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) { throw "Export artifact is missing or empty: $file" }
    }
    $binary = New-Object IO.BinaryReader([IO.File]::OpenRead($exe))
    try {
        if ($binary.ReadUInt16() -ne 0x5A4D) { throw 'Exported executable has no DOS/PE header.' }
        $binary.BaseStream.Position = 0x3C
        $peOffset = $binary.ReadInt32()
        $binary.BaseStream.Position = $peOffset
        if ($binary.ReadUInt32() -ne 0x00004550 -or $binary.ReadUInt16() -ne 0x8664) { throw 'Exported executable is not Windows x86_64.' }
    }
    finally { $binary.Dispose() }
    $binary = New-Object IO.BinaryReader([IO.File]::OpenRead($pck))
    try { if ($binary.ReadUInt32() -ne 0x43504447) { throw 'Exported PCK has an invalid Godot pack header.' } }
    finally { $binary.Dispose() }
    $licenseRoot = Join-Path $packageRoot 'licenses'
    $godotLicenses = Join-Path $licenseRoot 'godot'
    [void][IO.Directory]::CreateDirectory($godotLicenses)
    # Query the exact installed engine, including its bundled dependency notices.
    # The helper remains in ignored build output and never enters the PCK.
    $licenseHelper = Join-Path $runRoot 'collect_engine_licenses.gd'
    Write-Utf8 $licenseHelper @'
extends SceneTree
func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        quit(2)
        return
    var data := {"LICENSE-Godot.txt": Engine.get_license_text(),
        "THIRD-PARTY-LICENSES.json": JSON.stringify(Engine.get_license_info(), "  "),
        "THIRD-PARTY-COPYRIGHT.json": JSON.stringify(Engine.get_copyright_info(), "  ")}
    for name: String in data:
        var file := FileAccess.open(args[0].path_join(name), FileAccess.WRITE)
        if file == null:
            push_error("Cannot write engine license: " + name)
            quit(2)
            return
        file.store_string(data[name])
        file.close()
    quit()
'@
    [void](Invoke-GodotStep 'licenses' @('--headless', '--path', $projectRoot, '--log-file', (Join-Path $logRoot 'licenses-engine.log'), '--script', $licenseHelper, '--', $godotLicenses))
    $assetsRoot = Join-Path $projectRoot 'assets'
    $assetNotices = @(Get-ChildItem -LiteralPath $assetsRoot -File -Recurse | Where-Object {
        $_.Name -match '(?i)license|copying|copyright|notice|source|authors' -and $_.Extension -match '(?i)^\.(txt|md|json|html|license)$'
    })
    if ($assetNotices.Count -lt 1) { throw 'No asset provenance/license files were found.' }
    foreach ($notice in $assetNotices) {
        $relative = $notice.FullName.Substring($assetsRoot.Length).TrimStart([char[]]'\/')
        $target = Join-Path (Join-Path $licenseRoot 'assets') $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Copy-Item -LiteralPath $notice.FullName -Destination $target
    }
    # Copy only existing project notices; do not invent a project-wide license.
    foreach ($notice in @(Get-ChildItem -LiteralPath $projectRoot -File | Where-Object { $_.Name -match '^(LICENSE|COPYING|COPYRIGHT|NOTICE)(\..*)?$' })) {
        Copy-Item -LiteralPath $notice.FullName -Destination (Join-Path $licenseRoot $notice.Name)
    }
    $officialNotices = Join-Path $PSScriptRoot 'release/licenses'
    if (-not (Test-Path -LiteralPath $officialNotices -PathType Container)) { throw 'Pinned official Godot license notices are missing.' }
    foreach ($notice in @(Get-ChildItem -LiteralPath $officialNotices -File -Recurse)) {
        $relative = $notice.FullName.Substring($officialNotices.Length).TrimStart([char[]]'\/')
        $target = Join-Path $godotLicenses $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Copy-Item -LiteralPath $notice.FullName -Destination $target
    }
    Write-Utf8 (Join-Path $packageRoot 'Start-Chroma.bat') (@'
@echo off
setlocal
pushd "%~dp0" || exit /b 1
"%~dp0Chroma-Labyrinth.exe" %*
set "CHROMA_EXIT=%ERRORLEVEL%"
if not "%CHROMA_EXIT%"=="0" (
  echo Chroma-Labyrinth wurde mit Fehler %CHROMA_EXIT% beendet.
  echo Hinweise zum Laufzeitlog stehen in README-Windows.txt.
  pause
)
popd
exit /b %CHROMA_EXIT%
'@ -replace "`r?`n", "`r`n")
    $readme = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'release/README-Windows.txt'))
    $readme = $readme.Replace('@VERSION@', $Version).Replace('@GODOT_VERSION@', $engineVersion).Replace('@SOURCE_COMMIT@', $sourceCommit)
    Write-Utf8 (Join-Path $packageRoot 'README-Windows.txt') $readme
    $finalCommit = (& $git.Source -C $projectRoot rev-parse --verify HEAD | Out-String).Trim()
    $finalStatus = (& $git.Source -C $projectRoot status --porcelain --untracked-files=normal | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $finalCommit -ne $sourceCommit -or $finalStatus) { throw 'Source changed during the release build; no ZIP will be published from this run.' }
    $fileIndex = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{path = $_.FullName.Substring($packageRoot.Length + 1).Replace('\', '/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    $info = [ordered]@{project = 'Chroma-Labyrinth'; version = $Version; source_commit = $sourceCommit; source_dirty = $false;
        engine_version = $engineVersion; platform = 'Windows x86_64'; renderer = 'Forward+'; configuration = 'release';
        built_utc = [DateTime]::UtcNow.ToString('o'); asset_notice_count = $assetNotices.Count; files = $fileIndex}
    Write-Utf8 (Join-Path $packageRoot 'BUILD-INFO.json') ($info | ConvertTo-Json -Depth 8)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $temporaryZip = Join-Path $runRoot ($packageName + '.zip')
    [IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $temporaryZip, [IO.Compression.CompressionLevel]::Optimal, $true)
    $zip = Join-Path $OutputRoot ($packageName + '.zip')
    Move-Item -LiteralPath $temporaryZip -Destination $zip -Force
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8 ($zip + '.sha256') ($hash + ' *' + [IO.Path]::GetFileName($zip) + "`n")
    Write-Host "Release ZIP: $zip"
    Write-Host "SHA256:      $zip.sha256"
    Write-Host "Unpacked:    $packageRoot"
    Write-Host "Build logs:  $logRoot"
    exit 0
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
