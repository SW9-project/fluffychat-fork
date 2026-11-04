#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Downloads the on-device model so it is bundled into the app. It comes from the
# pilot1 release of the private functiongemma-heuristics repository, which takes
# the GitHub CLI and access to that repository.
#
# With --baseline, downloads the base model instead: kept for comparison, in
# assets/models/baseline, which is not bundled into the app.
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

fetch_pilot() {
  local file="assets/models/functiongemma-270M-sw9-pilot1.litertlm"
  local sha256="834126ed04d2cba810eb2de65da6dc580983afa6d25be3518157d1dfbb27cc74"
  if present "$file" "$sha256"; then
    echo "Model already present: $file"
    return
  fi
  if ! command -v gh >/dev/null; then
    echo "The pilot model needs the GitHub CLI (gh): https://cli.github.com" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$file")"
  echo "Downloading the FunctionGemma pilot (about 285 MB)..."
  if ! gh release download pilot1 \
    --repo SW9-project/functiongemma-heuristics \
    --pattern "$(basename "$file")" \
    --output "$file.part" \
    --clobber; then
    rm -f "$file.part"
    echo "Download failed. Are you signed in to gh (gh auth status), with access to SW9-project/functiongemma-heuristics?" >&2
    exit 1
  fi
  finish "$file" "$sha256"
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
  "") fetch_pilot ;;
  --baseline) fetch_baseline ;;
  *)
    echo "Usage: $0 [--baseline]" >&2
    exit 2
    ;;
esac
