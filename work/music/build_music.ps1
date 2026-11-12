$ErrorActionPreference = 'Stop'
$w = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$ndk = "$sdk\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin"
$inc = "$w\tools\game-music-emu-0.6.5\gme"

foreach ($p in @(@('arm64-v8a', 'aarch64-linux-android24'), @('x86_64', 'x86_64-linux-android24'))) {
    $abi = $p[0]
    New-Item -ItemType Directory -Force "$PSScriptRoot\lib\$abi" | Out-Null
    & "$ndk\clang++.exe" "--target=$($p[1])" -O2 -fPIC -shared -std=c++17 -static-libstdc++ `
        "-I$inc" "-I$w\android-gme-$abi\gme" "$PSScriptRoot\gme_bridge.cpp" "$w\android-gme-$abi\gme\libgme.a" `
        -llog -lz '-Wl,-z,max-page-size=16384' -o "$PSScriptRoot\lib\$abi\libmmgme.so"
    if ($LASTEXITCODE) { throw "clang failed for $abi" }
}

Remove-Item -Recurse -Force "$PSScriptRoot\classes", "$PSScriptRoot\dex" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$PSScriptRoot\classes", "$PSScriptRoot\dex" | Out-Null
javac --release 8 -d "$PSScriptRoot\classes" (Get-ChildItem "$PSScriptRoot\com" -Recurse -Filter *.java).FullName
if ($LASTEXITCODE) { throw 'javac failed' }
& "$sdk\build-tools\36.0.0\d8.bat" --release --min-api 24 --output "$PSScriptRoot\dex" (Get-ChildItem "$PSScriptRoot\classes" -Recurse -Filter *.class).FullName
if ($LASTEXITCODE) { throw 'd8 failed' }
