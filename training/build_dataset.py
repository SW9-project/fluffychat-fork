#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Builds the FunctionGemma training and evaluation sets from the hand-written
examples in training/source/.

    python3 training/build_dataset.py
    python3 training/build_dataset.py --tokenizer tokenizer.json \
        --template chat_template.jinja

Every call is checked against assets/personalization_tools.json. Arguments that
only repeat a default are dropped, so the model learns to leave them out.
Duplicate or conflicting prompts stop the build. 15% of every function goes to
the evaluation set, separately for single requests and conversations.

With --tokenizer and --template (FunctionGemma's tokenizer.json and
chat_template.jinja, which need the `tokenizers` and `jinja2` packages), every
example is also rendered with the real chat template and its length reported.
"""

import argparse
import json
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS_PATH = HERE.parent / "assets" / "personalization_tools.json"
SOURCE_DIR = HERE / "source"
RUN = HERE / "Train2"
OUT_DIR = RUN / "data"

SEED = 20261107
EVAL_SHARE = 0.15
MIN_PER_FUNCTION = 50
SIZE_WORDS = ["small", "medium", "big", "very_big"]
SIZE_NUMBER = re.compile(r"^\d+([.,]\d+)?\s*%?$")
NEGATIVE = {"ask_clarification", "no_action"}

# After a change the app answers the call with its status, then closes the
# model's turn with one of these fixed replies, so the user can speak again.
REPLIES = {"applied": "Done.", "declined": "Okay, nothing changed."}


class BuildError(Exception):
    pass


def load_tools():
    tools = json.loads(TOOLS_PATH.read_text())["functions"]
    return {t["name"]: t for t in tools}, [t["name"] for t in tools]


def normalize_call(tools, name, args, where):
    """Checks a call against its declaration and returns it with defaults
    dropped and `options` in declaration order."""
    tool = tools.get(name)
    if tool is None:
        raise BuildError(f"{where}: unknown function {name!r}")
    if not isinstance(args, dict):
        raise BuildError(f"{where}: arguments of {name} must be an object")
    props = tool["parameters"]["properties"]
    out = {}
    for key, value in args.items():
        schema = props.get(key)
        if schema is None:
            raise BuildError(f"{where}: {name} has no parameter {key!r}")
        kind = schema["type"]
        if kind == "string":
            if not isinstance(value, str) or not value.strip():
                raise BuildError(f"{where}: {name}.{key} must be a non-empty string")
            if key == "size" and value not in SIZE_WORDS and not SIZE_NUMBER.match(value):
                raise BuildError(f"{where}: {name}.size={value!r} is not a size word or a number")
            if "enum" in schema and value not in schema["enum"]:
                raise BuildError(f"{where}: {name}.{key}={value!r} is not in {schema['enum']}")
        elif kind == "integer":
            if not isinstance(value, int) or isinstance(value, bool):
                raise BuildError(f"{where}: {name}.{key} must be an integer")
            if not schema.get("minimum", value) <= value <= schema.get("maximum", value):
                raise BuildError(f"{where}: {name}.{key}={value} is out of range")
        elif kind == "boolean":
            if not isinstance(value, bool):
                raise BuildError(f"{where}: {name}.{key} must be true or false")
        elif kind == "array":
            allowed = schema["items"]["enum"]
            if not isinstance(value, list) or not value or len(set(value)) != len(value):
                raise BuildError(f"{where}: {name}.{key} must be a non-empty list without repeats")
            for item in value:
                if item not in allowed:
                    raise BuildError(f"{where}: {name}.{key} has unknown item {item!r}")
            value = sorted(value, key=allowed.index)
        else:
            raise BuildError(f"{where}: unsupported type {kind}")
        if "default" in schema and value == schema["default"]:
            continue
        out[key] = value
    for key in tool["parameters"].get("required", []):
        if key not in out:
            raise BuildError(f"{where}: {name} needs {key!r}")
    if "size" in props and ("direction" in out) == ("size" in out):
        raise BuildError(f"{where}: {name} needs direction or size, never both")
    if "chat" in out and "scope" in props and out.get("scope") != "one_chat":
        raise BuildError(f"{where}: a chat name needs scope one_chat")
    return name, out


def tool_call(name, args):
    return {"type": "function", "function": {"name": name, "arguments": args}}


def norm_text(text):
    return re.sub(r"\s+", " ", text.strip().lower()).rstrip(".!? ")


def load_examples(tools):
    examples = []
    seen = {}

    def claim(key, call, where):
        if key in seen:
            first_where, first_call = seen[key]
            what = "conflicts with" if first_call != call else "repeats"
            raise BuildError(f"{where} {what} {first_where}")
        seen[key] = (where, call)

    files = sorted(SOURCE_DIR.glob("*.json"))
    if not files:
        raise BuildError(f"no source files in {SOURCE_DIR}")
    for path in files:
        data = json.loads(path.read_text())
        if "conversations" in data:
            examples += load_conversations(tools, data["conversations"], path.name, claim)
            continue
        function = data["function"]
        n = 0
        for g, group in enumerate(data["groups"]):
            name, args = normalize_call(tools, function, group["args"], f"{path.name} group {g + 1}")
            for prompt in group["prompts"]:
                n += 1
                where = f"{path.name} {prompt!r}"
                claim(("single", norm_text(prompt)), (name, args), where)
                examples.append({
                    "id": f"{function}-{n:03d}",
                    "function": name,
                    "kind": "single",
                    "messages": [
                        {"role": "user", "content": prompt},
                        {"role": "assistant", "tool_calls": [tool_call(name, args)]},
                    ],
                })
    return examples


def load_conversations(tools, conversations, file_name, claim):
    examples = []
    counts = Counter()
    for c in conversations:
        kind = c["kind"]
        counts[kind] += 1
        where = f"{file_name} {kind} {counts[kind]} ({c['user']!r})"
        first = normalize_call(tools, *c["first"], where)
        call = normalize_call(tools, *c["call"], where)
        messages = [
            {"role": "user", "content": c["user"]},
            {"role": "assistant", "tool_calls": [tool_call(*first)]},
        ]
        if kind == "answer":
            if first[0] != "ask_clarification":
                raise BuildError(f"{where}: an answer follows ask_clarification")
            reply = c["answer"]
            messages.append({"role": "tool", "name": first[0], "content": {"answer": reply}})
        elif kind in ("adjust", "correct"):
            if first[0] in NEGATIVE:
                raise BuildError(f"{where}: {kind} follows a change")
            status = c["status"]
            if status not in REPLIES:
                raise BuildError(f"{where}: status must be one of {list(REPLIES)}")
            reply = c["then"]
            messages += [
                {"role": "tool", "name": first[0], "content": {"status": status}},
                {"role": "assistant", "content": REPLIES[status]},
                {"role": "user", "content": reply},
            ]
        else:
            raise BuildError(f"{where}: unknown kind {kind!r}")
        messages.append({"role": "assistant", "tool_calls": [tool_call(*call)]})
        claim(("multi", norm_text(c["user"]), json.dumps(first), norm_text(reply)), call, where)
        examples.append({
            "id": f"multi-{kind}-{counts[kind]:03d}",
            "function": call[0],
            "kind": kind,
            "messages": messages,
        })
    return examples


def split(examples):
    strata = defaultdict(list)
    for e in examples:
        strata[(e["function"], "single" if e["kind"] == "single" else "multi")].append(e)
    eval_ids = set()
    for key in sorted(strata):
        group = sorted(strata[key], key=lambda e: e["id"])
        random.Random(f"{SEED}:{key}").shuffle(group)
        n = round(len(group) * EVAL_SHARE)
        if n == 0 and len(group) >= 4:
            n = 1
        eval_ids.update(e["id"] for e in group[:n])
    train = [e for e in examples if e["id"] not in eval_ids]
    evaluation = [e for e in examples if e["id"] in eval_ids]
    return train, evaluation


def write_jsonl(path, rows):
    with path.open("w") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


def report(order, train, evaluation):
    rows = []
    for name in order:
        t = [e for e in train if e["function"] == name]
        v = [e for e in evaluation if e["function"] == name]
        single = sum(e["kind"] == "single" for e in t + v)
        rows.append((name, single, len(t) + len(v) - single, len(t), len(v)))
    print(f"{'function':<20}{'single':>8}{'multi':>7}{'train':>7}{'eval':>6}")
    for name, single, multi, t, v in rows:
        flag = "  < minimum" if single + multi < MIN_PER_FUNCTION else ""
        print(f"{name:<20}{single:>8}{multi:>7}{t:>7}{v:>6}{flag}")
    total = len(train) + len(evaluation)
    neg = sum(e["function"] in NEGATIVE for e in train + evaluation)
    multi = sum(e["kind"] != "single" for e in train + evaluation)
    print(f"{'total':<20}{total - multi:>8}{multi:>7}{len(train):>7}{len(evaluation):>6}")
    print(f"negatives (ask_clarification, no_action): {neg} = {neg / total:.1%}")
    print(f"conversations: {multi} = {multi / total:.1%}, evaluation share: {len(evaluation) / total:.1%}")


def token_report(tools_by_name, order, examples, tokenizer_path, template_path):
    import jinja2
    from tokenizers import Tokenizer

    def raise_exception(message):
        raise BuildError(f"chat template: {message}")

    env = jinja2.Environment(trim_blocks=False, lstrip_blocks=False)
    template = env.from_string(Path(template_path).read_text())
    tok = Tokenizer.from_file(tokenizer_path)
    hf_tools = [{"type": "function", "function": tools_by_name[n]} for n in order]
    lengths = []
    for e in examples:
        text = template.render(
            messages=e["messages"], tools=hf_tools, bos_token="<bos>",
            raise_exception=raise_exception, add_generation_prompt=False,
        )
        if not text.endswith("<end_function_call><start_function_response>"):
            raise BuildError(f"{e['id']}: the render does not end in a call")
        lengths.append((len(tok.encode(text, add_special_tokens=False).ids), e["id"]))
    lengths.sort()
    values = [n for n, _ in lengths]
    print(f"tokens per example: min {values[0]}, median {values[len(values) // 2]}, "
          f"max {values[-1]} ({lengths[-1][1]})")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--tokenizer", help="FunctionGemma tokenizer.json, for token counts")
    parser.add_argument("--template", help="FunctionGemma chat_template.jinja, for token counts")
    a = parser.parse_args()
    tools, order = load_tools()
    try:
        examples = load_examples(tools)
        train, evaluation = split(examples)
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        write_jsonl(OUT_DIR / "train.jsonl", train)
        write_jsonl(OUT_DIR / "eval.jsonl", evaluation)
        report(order, train, evaluation)
        if a.tokenizer and a.template:
            token_report(tools, order, examples, a.tokenizer, a.template)
    except BuildError as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
