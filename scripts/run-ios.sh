#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Opens an iOS simulator and runs FluffyChat on it. Assumes everything is already installed.
#
# Usage:
#   ./scripts/run-ios.sh                           # iPhone 17 Pro
#   ./scripts/run-ios.sh "iPhone Air"              # another simulator, by name or UDID
#   ./scripts/run-ios.sh "iPhone Air" --release    # extra arguments go to `flutter run`

set -e

cd "$(dirname "$0")/.."

device="iPhone 17 Pro"
if [[ $# -gt 0 && "$1" != -* ]]; then
  device="$1"
  shift
fi

# Boots the simulator if needed and waits until it is ready
xcrun simctl bootstatus "$device" -b >/dev/null

# Xcode 27+ shows simulators in DeviceHub, older versions in the Simulator app
open -a DeviceHub 2>/dev/null || open -a Simulator 2>/dev/null ||
  echo "Warning: neither DeviceHub nor Simulator found, running without a window." >&2

flutter run -d "$device" "$@"
