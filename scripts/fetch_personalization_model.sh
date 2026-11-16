#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Imports the team-supplied FunctionGemma v2 model into assets/models so it is
# bundled into the app. See assets/models/README.md for the license terms.
set -euo pipefail

cd "$(dirname "$0")/.."

filename="functiongemma-270M-sw9-v2.litertlm"
file="assets/models/$filename"
source_file="${1:-${SW9_MODEL_FILE:-$HOME/Downloads/$filename}}"
sha256="37e92741110b1a7bff2607905a3598186d42de36beabe9091400879ef7d1383b"

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

if [[ ! -f "$source_file" ]]; then
  echo "Supply the team v2 model: $0 /path/to/$filename" >&2
  exit 1
fi
if [[ "$(checksum "$source_file")" != "$sha256" ]]; then
  echo "Model checksum mismatch; existing assets have not been changed." >&2
  exit 1
fi
cp "$source_file" "$file"
echo "Imported $file"
