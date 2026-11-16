#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later

<<<<<<< Updated upstream
# Downloads the on-device FunctionGemma model into assets/models so it is
# bundled into the app. See assets/models/README.md for the license terms.
=======
# Downloads the models kept for comparison into assets/models/baseline, which is
# not bundled into the app:
#
#   --baseline  the base model, which training/convert.py also needs
#   --pilot     the earlier pilot, from the pilot1 release of the private
#               functiongemma-heuristics repository (needs the GitHub CLI)
#
# The model the app runs is built by training/convert.py, see
# assets/models/README.md.
#
# See assets/models/README.md for the license terms.
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
if [[ "$(checksum "$file.part")" != "$sha256" ]]; then
  rm -f "$file.part"
  echo "Checksum mismatch, download removed." >&2
  exit 1
fi
mv "$file.part" "$file"
echo "Saved $file"
=======
fetch_pilot() {
  local file="assets/models/baseline/functiongemma-270M-sw9-pilot1.litertlm"
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
  --pilot) fetch_pilot ;;
  --baseline) fetch_baseline ;;
  *)
    echo "Usage: $0 --baseline | --pilot" >&2
    echo "The model the app runs is built by training/convert.py." >&2
    exit 2
    ;;
esac
>>>>>>> Stashed changes
