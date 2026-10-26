#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Opens an Android emulator and runs FluffyChat on it. Assumes everything is already installed.
#
# Usage:
#   ./scripts/run-android.sh                           # Pixel 10 Pro
#   ./scripts/run-android.sh Pixel_9                   # another emulator, by AVD name
#   ./scripts/run-android.sh Pixel_9 --release         # extra arguments go to `flutter run`

set -e

cd "$(dirname "$0")/.."

avd="Pixel_10_Pro"
if [[ $# -gt 0 && "$1" != -* ]]; then
  avd="$1"
  shift
fi

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
adb="$sdk/platform-tools/adb"
emulator="$sdk/emulator/emulator"
if [[ ! -x "$adb" || ! -x "$emulator" ]]; then
  echo "Error: Android SDK not found in $sdk. Set ANDROID_HOME to its location." >&2
  exit 1
fi

if ! "$emulator" -list-avds | grep -qx "$avd"; then
  echo "Error: no emulator named \"$avd\". Available ones:" >&2
  "$emulator" -list-avds >&2
  exit 1
fi

"$adb" start-server >/dev/null 2>&1

running_emulators() {
  "$adb" devices | awk '/^emulator-/ {print $1}'
}

# Reuses the emulator if it is already running
serial=""
for s in $(running_emulators); do
  if [[ "$("$adb" -s "$s" emu avd name 2>/dev/null | head -n1 | tr -d '\r')" == "$avd" ]]; then
    serial="$s"
    break
  fi
done

pid=""
if [[ -z "$serial" ]]; then
  # Picks a free console port, so we know the new emulator's serial
  port=5554
  while running_emulators | grep -qx "emulator-$port"; do
    port=$((port + 2))
  done
  serial="emulator-$port"

  echo "Starting $avd..."
  # Job control gives the emulator its own process group, so Ctrl+C on `flutter run` leaves it open
  set -m
  nohup "$emulator" -avd "$avd" -port "$port" >/dev/null 2>&1 &
  pid=$!
  set +m
fi

# Waits until Android has finished booting
until [[ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
    echo "Error: the emulator closed before it finished booting." >&2
    exit 1
  fi
  sleep 1
done

# Silences the "restricted method" warnings that Gradle's launcher triggers on Java 24+
export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }--enable-native-access=ALL-UNNAMED"

flutter run -d "$serial" "$@"
