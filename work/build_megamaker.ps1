# Full Mega Maker build: GML patches -> game.droid -> APK on top of base-v1.apk.
param([string]$Out = 'outputs\Mega Maker.apk', [switch]$ReuseNative)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$bt = Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools\36.0.0'
$cli = '.\work\tools\utmt\UndertaleModCli.exe'

if (-not (Test-Path work\base-v1.apk)) { Copy-Item 'outputs\Mega Maker.apk' work\base-v1.apk }

python work/patch_startup.py --touch
if ($LASTEXITCODE) { throw 'Could not prepare the GML changes' }
if (-not $ReuseNative) { & .\work\music\build_music.ps1 }

# Extension changes first: the patched GML calls the new extension functions.
Remove-Item work\build-ext.droid, work\build.droid -ErrorAction SilentlyContinue
& $cli load '.\work\windows-original\data.win' -s work\music\set_extension_class.csx -o work\build-ext.droid
if ($LASTEXITCODE -or -not (Test-Path work\build-ext.droid)) { throw 'Could not update the extension' }
$replacements = @(Get-ChildItem 'work\android-gml' -Filter '*.gml' | ForEach-Object { '-c'; "$($_.BaseName)=$($_.FullName)" })
& $cli replace work\build-ext.droid -o work\build.droid @replacements
if ($LASTEXITCODE -or -not (Test-Path work\build.droid)) { throw 'Could not compile the GML changes' }

python work/manifest_extensions.py work/base-v1.apk work/build-manifest.xml GameMusicEmu
if ($LASTEXITCODE) { throw 'Could not patch the manifest' }
python work/package_megamaker.py work/base-v1.apk work/build.droid work/music work/build-raw.apk --manifest work/build-manifest.xml
if ($LASTEXITCODE) { throw 'Could not assemble the APK' }
& "$bt\zipalign.exe" -P 16 -f 4 work/build-raw.apk work/build-aligned.apk
if ($LASTEXITCODE) { throw 'Could not align the APK' }
& "$bt\apksigner.bat" sign --ks work/probe-key.jks --ks-key-alias mmmprobe --ks-pass pass:android --key-pass pass:android --v1-signing-enabled false --v4-signing-enabled false --min-sdk-version 24 --out $Out work/build-aligned.apk
if ($LASTEXITCODE) { throw 'Could not sign the APK' }
Write-Host "Built $Out"
