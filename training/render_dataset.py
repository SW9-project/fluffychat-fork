#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Renders data/train.jsonl and data/eval.jsonl with FunctionGemma's chat
template, through tokenizer.apply_chat_template, and prints one example.

    training/.venv/bin/python training/render_dataset.py
    training/.venv/bin/python training/render_dataset.py --show multi-answer-001

Writes data/train_rendered.jsonl and data/eval_rendered.jsonl, one object per
line with:

    text        the whole rendered conversation
    prompt      everything before the final call, ending where the model starts
    completion  the final call the model has to learn (text = prompt + completion)

Stops when a render lacks the expected special tokens or does not end in a call.
"""

import argparse
import json
import sys
from pathlib import Path

from transformers import AutoTokenizer

HERE = Path(__file__).resolve().parent
TOOLS_PATH = HERE.parent / "assets" / "personalization_tools.json"
MODEL_DIR = HERE / "functiongemma-270m-it"
DATA_DIR = HERE / "data"

REQUIRED = ["<start_function_declaration>", "<start_function_call>", "<escape>"]


def load_tools():
    functions = json.loads(TOOLS_PATH.read_text())["functions"]
    return [{"type": "function", "function": f} for f in functions]


def render(tokenizer, tools, messages, **kwargs):
    return tokenizer.apply_chat_template(messages, tools=tools, tokenize=False, **kwargs)


def convert(tokenizer, tools, example):
    messages = example["messages"]
    text = render(tokenizer, tools, messages)
    prompt = render(tokenizer, tools, messages[:-1], add_generation_prompt=True)
    where = example["id"]
    for token in REQUIRED:
        if token not in text:
            sys.exit(f"error: {where}: {token} missing from the render")
    if not text.endswith("<end_function_call><start_function_response>"):
        sys.exit(f"error: {where}: the render does not end in a call")
    if not text.startswith(prompt):
        sys.exit(f"error: {where}: the prompt is not a prefix of the full render")
    return {
        "id": where,
        "function": example["function"],
        "kind": example["kind"],
        "text": text,
        "prompt": prompt,
        "completion": text[len(prompt):],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--show", default="change_text_size-160",
                        help="id of the example to print (default: %(default)s)")
    a = parser.parse_args()

    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    tools = load_tools()
    shown = None
    lengths = []
    for split in ("train", "eval"):
        rows = [json.loads(line) for line in (DATA_DIR / f"{split}.jsonl").read_text().splitlines()]
        out = [convert(tokenizer, tools, e) for e in rows]
        with (DATA_DIR / f"{split}_rendered.jsonl").open("w") as f:
            for row in out:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
        lengths += [len(tokenizer(r["text"], add_special_tokens=False).input_ids) for r in out]
        shown = shown or next((r for r in out if r["id"] == a.show), None)
        print(f"{split}: {len(out)} examples -> data/{split}_rendered.jsonl")

    lengths.sort()
    print(f"tokens per example: min {lengths[0]}, median {lengths[len(lengths) // 2]}, max {lengths[-1]}")
    if shown is None:
        sys.exit(f"error: no example {a.show!r}")
    print(f"\n===== {shown['id']} : prompt =====\n{shown['prompt']}")
    print(f"===== {shown['id']} : completion =====\n{shown['completion']}")


if __name__ == "__main__":
    main()
