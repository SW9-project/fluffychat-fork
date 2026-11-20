#!/usr/bin/env bash
# Zips what the Colab notebook needs to train and evaluate Train2: training/Train2/colab.zip
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

[ -f training/functiongemma-270m-it/model.safetensors ] || { echo "error: base model missing in training/functiongemma-270m-it/" >&2; exit 1; }
for f in train eval; do
  [ -f "training/Train2/data/${f}_rendered.jsonl" ] || { echo "error: training/Train2/data/${f}_rendered.jsonl missing, run training/render_dataset.py" >&2; exit 1; }
done

out=training/Train2/colab.zip
rm -f "$out"
zip -r -q "$out" \
  training/train.py training/evaluate.py training/build_dataset.py \
  training/functiongemma-270m-it training/Train2/data \
  assets/personalization_tools.json \
  -x '*__pycache__*' '*.DS_Store'
echo "wrote $out ($(du -h "$out" | cut -f1))"
