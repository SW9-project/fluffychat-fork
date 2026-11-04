#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Builds the APK for study phones, with the model inside, so a session does not
# depend on Wi-Fi. Other builds download the model when the user taps Set up.
#
# Flutter bundles whatever is in assets/models/, and a dart-define cannot change
# that. So this puts the file there only for this build, and removes it after,
# or every normal build would silently grow by the size of the model.
#
# The URL and checksum come from lib/personalization/model/model_release.dart.
# Arguments go to flutter build apk. The default is --release.
# See assets/models/README.md for the license terms.
set -euo pipefail

cd "$(dirname "$0")/.."

constant=lib/personalization/model/model_release.dart
url="$(grep -oE "https://[^']+\.litertlm" "$constant")"
sha256="$(grep -oE "[0-9a-f]{64}" "$constant")"
file="assets/models/$(basename "$url")"

checksum() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

trap 'rm -f "$file" "$file.part"' EXIT

echo "Downloading $url"
curl --fail --location --progress-bar --output "$file.part" "$url"
if [[ "$(checksum "$file.part")" != "$sha256" ]]; then
  echo "Checksum mismatch, nothing built." >&2
  exit 1
fi
mv "$file.part" "$file"

if [[ $# -eq 0 ]]; then
  set -- --release
fi
flutter build apk --target-platform android-arm64 \
  --dart-define=SW9_BUNDLED_MODEL=true "$@"
