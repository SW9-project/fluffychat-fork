# SPDX-FileCopyrightText: 2026 SW9-project contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
$ErrorActionPreference = 'Stop'
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk'
$env:JAVA_HOME = 'C:/Program Files/Android/Android Studio/jbr'
$env:JAVA_OPTS = '-Xmx512m'
$image = 'system-images;android-30;default;x86_64'
if (!(Test-Path (Join-Path $androidSdk 'system-images/android-30/default/x86_64/system.img'))) {
    & "$androidSdk/cmdline-tools/latest/bin/sdkmanager.bat" --install $image
    if ($LASTEXITCODE -ne 0) { throw 'Android image installation failed' }
}
$avdFolder = Join-Path $env:USERPROFILE '.android/avd/FluffyChat_Light.avd'
if (Test-Path -LiteralPath $avdFolder) {
    Write-Host 'FluffyChat_Light already exists; keeping its configuration and data.'
    return
}
'no' | & "$androidSdk/cmdline-tools/latest/bin/avdmanager.bat" create avd --name FluffyChat_Light --package $image --device pixel_2
if ($LASTEXITCODE -ne 0) { throw 'AVD creation failed' }
$avdConfig = Join-Path $avdFolder 'config.ini'
$avdText = [IO.File]::ReadAllText($avdConfig)
$lightOptions = [ordered]@{
    'hw.ramSize'='2048'; 'hw.cpu.ncore'='2'; 'vm.heapSize'='192'
    'hw.lcd.width'='720'; 'hw.lcd.height'='1280'; 'hw.lcd.density'='240'
    'hw.gpu.enabled'='yes'; 'hw.gpu.mode'='host'; 'showDeviceFrame'='no'
    'skin.name'='720x1280'; 'skin.dynamic'='yes'; 'disk.dataPartition.size'='4G'
}
foreach ($option in $lightOptions.GetEnumerator()) {
    $pattern = '(?m)^' + [regex]::Escape($option.Key) + '=.*$'
    if ($avdText -match $pattern) {
        $avdText = [regex]::Replace($avdText,$pattern,($option.Key + '=' + $option.Value))
    } else { $avdText += "`n$($option.Key)=$($option.Value)" }
}
[IO.File]::WriteAllText($avdConfig,$avdText)
Write-Host 'Created FluffyChat_Light (Android 11 AOSP, 2 GB RAM). Original AVD kept.'
