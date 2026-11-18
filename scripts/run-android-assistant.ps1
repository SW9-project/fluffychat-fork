# SPDX-FileCopyrightText: 2026 SW9-project contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
param([switch]$SkipBuild, [string]$Avd = 'FluffyChat_Light', [string]$ModelFile)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk'
$adb = Join-Path $androidSdk 'platform-tools/adb.exe'
$javaRoot = 'C:/Program Files/Android/Android Studio/jbr'
$java = Join-Path $javaRoot 'bin/java.exe'
$env:JAVA_HOME = $javaRoot
$env:Path = "$javaRoot/bin;C:/src/flutter/bin;$env:Path"
$env:GRADLE_OPTS = "$env:GRADLE_OPTS -Dorg.gradle.jvmargs=-Xmx1536m -Dorg.gradle.workers.max=2"
$hostBuild = Join-Path $projectRoot 'build/assistant-host'
New-Item -ItemType Directory -Force $hostBuild | Out-Null
$modelConfig = Get-Content -LiteralPath (Join-Path $projectRoot 'assets/models/model.json') -Raw | ConvertFrom-Json
$expectedHash = $modelConfig.sha256
$assetModel = Join-Path $projectRoot ('assets/models/' + $modelConfig.filename)
if (!(Test-Path -LiteralPath $assetModel) -or (Get-FileHash -LiteralPath $assetModel -Algorithm SHA256).Hash -ne $expectedHash) {
    if (!$ModelFile) { $ModelFile = Join-Path $env:USERPROFILE ('Downloads/' + $modelConfig.filename) }
    if (!(Test-Path -LiteralPath $ModelFile)) { throw "Missing model. Pass -ModelFile with the path to $($modelConfig.filename)." }
    if ((Get-FileHash -LiteralPath $ModelFile -Algorithm SHA256).Hash -ne $expectedHash) { throw 'The supplied model does not match the configured SHA-256.' }
    Copy-Item -LiteralPath $ModelFile -Destination $assetModel -Force
}
$modelPath = Join-Path $hostBuild $modelConfig.filename
if (!(Test-Path -LiteralPath $modelPath) -or (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash -ne $expectedHash) {
    Copy-Item -LiteralPath $assetModel -Destination $modelPath -Force
}
$apkPath = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-debug.apk'
if ($SkipBuild -and (!(Test-Path -LiteralPath $apkPath) -or (Get-Item -LiteralPath $apkPath).LastWriteTime -lt (Get-Item -LiteralPath (Join-Path $projectRoot 'assets/models/model.json')).LastWriteTime)) {
    throw 'The APK predates the configured model. Run this script without -SkipBuild first.'
}
function Test-Sw9ModelHost {
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8787/health' -TimeoutSec 3
        return $health.ready -and $health.model -eq $modelConfig.id -and $health.sha256 -eq $expectedHash
    } catch { return $false }
}
# Retire only this project's old host, never another application's server.
if (!(Test-Sw9ModelHost)) {
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'java.exe' -and $_.CommandLine -match '\bAssistantHost\b' -and $_.CommandLine.Contains($projectRoot)
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

if (!$SkipBuild) {
    # Release emulator memory during compilation on an 8 GB PC.
    if ((& $adb devices) -match 'emulator-\d+\s+device') {
        & $adb emu kill
    }
    & $java -Xmx256m -classpath android/gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain -p scripts/assistant-host --no-daemon '-Dorg.gradle.jvmargs=-Xmx512m' installDist
    if ($LASTEXITCODE -ne 0) { throw 'Host build failed' }
    & flutter build apk --debug --target-platform android-x64 --dart-define=SW9_EMULATOR_ASSIST=true
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
    & $java -classpath android/gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain --stop
}

$hostReady = Test-Sw9ModelHost
if (!$hostReady) {
    Write-Host "Starting $($modelConfig.id) on this computer..."
    $hostClasspath = Join-Path $PSScriptRoot 'assistant-host/build/install/sw9-assistant-host/lib/*'
    if (!(Test-Path (Split-Path $hostClasspath -Parent))) { throw 'Run without -SkipBuild first' }
    Start-Process $java -ArgumentList '-Xmx768m','--enable-native-access=ALL-UNNAMED','-cp',"`"$hostClasspath`"",'AssistantHost',"`"$modelPath`"" -WindowStyle Hidden -RedirectStandardOutput "$hostBuild/server.log" -RedirectStandardError "$hostBuild/server-error.log"
    $hostDeadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 2
        $hostReady = Test-Sw9ModelHost
    } until ($hostReady -or (Get-Date) -gt $hostDeadline)
    if (!$hostReady) { throw "Host failed to start. See $hostBuild/server-error.log" }
}

if ($Avd -eq 'FluffyChat_Light' -and
    !(Test-Path (Join-Path $env:USERPROFILE '.android/avd/FluffyChat_Light.avd'))) {
    & "$PSScriptRoot/setup-light-emulator.ps1"
}
if ((& $adb devices) -match 'emulator-\d+\s+device') {
    $activeAvd = (& $adb emu avd name | Where-Object { $_ -and $_ -ne 'OK' } | Select-Object -First 1).Trim()
    if ($activeAvd -ne $Avd) {
        Write-Host "Closing $activeAvd before starting $Avd (data kept)..."
        & $adb emu kill
        $stopDeadline = (Get-Date).AddSeconds(30)
        do { Start-Sleep -Seconds 1 } while (
            ((& $adb devices) -match 'emulator-\d+') -and (Get-Date) -lt $stopDeadline
        )
    }
}
if (!((& $adb devices) -match 'emulator-\d+\s+device')) {
    Write-Host 'Starting Android Emulator...'
    Start-Process (Join-Path $androidSdk 'emulator/emulator.exe') -ArgumentList '-avd',$Avd,'-no-snapshot','-no-boot-anim','-gpu','host','-cores','2' -WindowStyle Hidden -RedirectStandardOutput "$hostBuild/emulator.log" -RedirectStandardError "$hostBuild/emulator-error.log"
}
$bootDeadline = (Get-Date).AddMinutes(4)
do {
    Start-Sleep -Seconds 3
    $booted = $false
    try { $booted = (& $adb shell getprop sys.boot_completed 2>$null) -match '1' } catch {}
} until ($booted -or (Get-Date) -gt $bootDeadline)
if (!$booted) { throw 'Android did not finish booting' }
& $adb reverse tcp:8787 tcp:8787
if ($LASTEXITCODE -ne 0) { throw 'adb reverse failed' }
Write-Host 'Installing the development APK (preserving your session)...'
& $adb install -r build/app/outputs/flutter-apk/app-debug.apk
if ($LASTEXITCODE -ne 0) { throw 'APK installation failed' }
& $adb shell input keyevent 224
& $adb shell wm dismiss-keyguard
& $adb shell am start -n chat.fluffy.fluffychat/.MainActivity
Write-Host 'Open Assistant and tap Set up. The model runs on this computer, not in the x86 emulator.'
