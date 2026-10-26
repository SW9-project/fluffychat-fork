#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Downloads the on-device FunctionGemma model into assets/models so it is
# bundled into the app. See assets/models/README.md for the license terms.
set -euo pipefail

cd "$(dirname "$0")/.."

file="assets/models/functiongemma-270M-it.litertlm"
url="https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm"
sha256="680fead1cca41a23220c904500a515d06e41f5c66d130aa4a9cc5905ec529a8e"

checksum() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

if [[ -f "$file" && "$(checksum "$file")" == "$sha256" ]]; then
  echo "Model already present: $file"
  exit 0
fi

echo "Downloading FunctionGemma 270M (about 284 MB)..."
curl --fail --location --progress-bar --output "$file.part" "$url"

if [[ "$(checksum "$file.part")" != "$sha256" ]]; then
  rm -f "$file.part"
  echo "Checksum mismatch, download removed." >&2
  exit 1
fi
mv "$file.part" "$file"
echo "Saved $file"
