#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Downloads the base model into assets/models/baseline, which is not bundled
# into the app:
#
#   --baseline  the base model, kept for comparison; training/convert.py needs it
#
# The model the app runs is built by training/convert.py, see
# assets/models/README.md.
#
# See assets/models/README.md for the license terms.
set -euo pipefail

cd "$(dirname "$0")/.."

checksum() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Moves a finished download into place, or removes it when its checksum is wrong.
finish() {
  local file="$1" sha256="$2"
  if [[ "$(checksum "$file.part")" != "$sha256" ]]; then
    rm -f "$file.part"
    echo "Checksum mismatch, download removed." >&2
    exit 1
  fi
  mv "$file.part" "$file"
  echo "Saved $file"
}

present() {
  [[ -f "$1" && "$(checksum "$1")" == "$2" ]]
}

fetch_baseline() {
  local file="assets/models/baseline/functiongemma-270M-it.litertlm"
  local url="https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm"
  local sha256="680fead1cca41a23220c904500a515d06e41f5c66d130aa4a9cc5905ec529a8e"
  if present "$file" "$sha256"; then
    echo "Model already present: $file"
    return
  fi
  mkdir -p "$(dirname "$file")"
  echo "Downloading FunctionGemma 270M (about 284 MB)..."
  curl --fail --location --progress-bar --output "$file.part" "$url"
  finish "$file" "$sha256"
}

case "${1:-}" in
  --baseline) fetch_baseline ;;
  *)
    echo "Usage: $0 --baseline" >&2
    echo "The model the app runs is built by training/convert.py." >&2
    exit 2
    ;;
esac
