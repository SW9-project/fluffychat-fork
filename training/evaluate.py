#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Evaluates FunctionGemma models on data/eval_rendered.jsonl (step 6).

    training/.venv/bin/python training/evaluate.py                 # base and pilot
    training/.venv/bin/python training/evaluate.py --models pilot

Every model generates greedily from each prompt, and its call is parsed and
compared with the label. Reported:

    function accuracy   the right function was called
    exact arguments     the right function with exactly the labelled arguments, as
                        written (raw) and after dropping defaults and sorting
                        options (normalized), the way build_dataset.py labels them
    field accuracy      of the argument fields in the label or the prediction, the
                        share with the same value, over calls to the right function
    schema validity     the output is one parseable call to a declared function,
                        with declared parameters of the right types, enum values
                        and ranges, and every required parameter
    abstention          on requests labelled ask_clarification or no_action, the
                        share where the model called one of the two (and the exact
                        one); on all other requests, the share where it wrongly did

Writes every prediction to output/eval_<model>.jsonl.
"""

import argparse
import json
import time
from collections import Counter, defaultdict
from pathlib import Path

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

from build_dataset import NEGATIVE, BuildError, load_tools, normalize_call

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
OUT_DIR = HERE / "output"
MODELS = {"base": HERE / "functiongemma-270m-it", "pilot": OUT_DIR / "functiongemma-pilot"}

CALL_START, CALL_END, ESC = "<start_function_call>", "<end_function_call>", "<escape>"


class ParseError(Exception):
    pass


def parse_value(s, i):
    """Parses one value in FunctionGemma's call syntax starting at s[i]; returns (value, next index)."""
    if s.startswith(ESC, i):
        end = s.find(ESC, i + len(ESC))
        if end < 0:
            raise ParseError("unterminated string")
        return s[i + len(ESC):end], end + len(ESC)
    if s.startswith("[", i):
        items, i = [], i + 1
        if s.startswith("]", i):
            return items, i + 1
        while True:
            value, i = parse_value(s, i)
            items.append(value)
            if s.startswith(",", i):
                i += 1
            elif s.startswith("]", i):
                return items, i + 1
            else:
                raise ParseError(f"expected , or ] at {i}")
    if s.startswith("{", i):
        return parse_object(s, i)
    j = i
    while j < len(s) and s[j] not in ",}]":
        j += 1
    word = s[i:j]
    if word == "true":
        return True, j
    if word == "false":
        return False, j
    try:
        return int(word), j
    except ValueError:
        pass
    try:
        return float(word), j
    except ValueError:
        raise ParseError(f"bad value {word!r}") from None


def parse_object(s, i):
    if not s.startswith("{", i):
        raise ParseError(f"expected {{ at {i}")
    out, i = {}, i + 1
    if s.startswith("}", i):
        return out, i + 1
    while True:
        if s.startswith(ESC, i):
            key, i = parse_value(s, i)
        else:
            colon = s.find(":", i)
            if colon < 0:
                raise ParseError("expected key:")
            key, i = s[i:colon], colon
        if not s.startswith(":", i):
            raise ParseError(f"expected : at {i}")
        if key in out:
            raise ParseError(f"repeated key {key!r}")
        out[key], i = parse_value(s, i + 1)
        if s.startswith(",", i):
            i += 1
        elif s.startswith("}", i):
            return out, i + 1
        else:
            raise ParseError(f"expected , or }} at {i}")


def parse_output(text):
    """Returns (name, args) of the single call in a generation, or raises ParseError."""
    if text.count(CALL_START) != 1:
        raise ParseError(f"{text.count(CALL_START)} calls")
    body = text.split(CALL_START, 1)[1]
    if CALL_END not in body:
        raise ParseError("no <end_function_call>")
    body = body.split(CALL_END, 1)[0]
    if not body.startswith("call:") or "{" not in body:
        raise ParseError("not call:name{...}")
    name = body[len("call:"):body.index("{")]
    args, end = parse_object(body, body.index("{"))
    if end != len(body):
        raise ParseError("text after the arguments")
    return name, args


def generate(model_dir, prompts, device):
    tokenizer = AutoTokenizer.from_pretrained(model_dir)
    model = AutoModelForCausalLM.from_pretrained(model_dir, dtype=torch.float32, attn_implementation="sdpa")
    model.to(device).eval()
    stop = model.generation_config.eos_token_id
    outputs = []
    start = time.time()
    with torch.inference_mode():
        for n, prompt in enumerate(prompts, 1):
            ids = tokenizer(prompt, add_special_tokens=False, return_tensors="pt").input_ids.to(device)
            out = model.generate(ids, max_new_tokens=128, do_sample=False, top_p=None, top_k=None,
                                 eos_token_id=stop, pad_token_id=tokenizer.pad_token_id)
            outputs.append(tokenizer.decode(out[0, ids.shape[1]:], skip_special_tokens=False))
            if n % 20 == 0:
                print(f"  {n}/{len(prompts)} ({(time.time() - start) / n:.1f} s each)", flush=True)
    return outputs


def score(tools, example, output):
    name, args = example["call"]
    r = {"id": example["id"], "kind": example["kind"], "expected": {"name": name, "arguments": args},
         "output": output, "predicted": None, "valid": False, "error": None}
    try:
        p_name, p_args = parse_output(output)
    except ParseError as e:
        r["error"] = f"parse: {e}"
        return r
    r["predicted"] = {"name": p_name, "arguments": p_args}
    try:
        _, p_norm = normalize_call(tools, p_name, p_args, "prediction")
        r["valid"] = True
    except BuildError as e:
        r["error"] = f"schema: {e.args[0].removeprefix('prediction: ')}"
        p_norm = p_args
    r["function_ok"] = p_name == name
    r["raw_exact"] = r["function_ok"] and p_args == args
    r["exact"] = r["function_ok"] and p_norm == args
    r["wrote_defaults"] = r["valid"] and p_norm != p_args and sorted(p_norm) != sorted(p_args)
    if r["function_ok"]:
        keys = set(args) | set(p_norm)
        r["fields"] = (sum(args.get(k) == p_norm.get(k) for k in keys), len(keys))
    return r


def pct(a, b):
    return f"{a / b:6.1%}" if b else "     -"


def report(label, results, order):
    n = len(results)
    func = sum(r.get("function_ok", False) for r in results)
    exact = sum(r.get("exact", False) for r in results)
    raw = sum(r.get("raw_exact", False) for r in results)
    fields = [r["fields"] for r in results if "fields" in r]
    f_ok, f_all = sum(a for a, _ in fields), sum(b for _, b in fields)
    valid = sum(r["valid"] for r in results)
    defaults = sum(r.get("wrote_defaults", False) for r in results)
    neg = [r for r in results if r["expected"]["name"] in NEGATIVE]
    pos = [r for r in results if r["expected"]["name"] not in NEGATIVE]
    pred = lambda r: (r["predicted"] or {}).get("name")  # noqa: E731
    abstained = sum(pred(r) in NEGATIVE for r in neg)
    abstained_exact = sum(pred(r) == r["expected"]["name"] for r in neg)
    false_abstain = sum(pred(r) in NEGATIVE for r in pos)

    print(f"\n=== {label}: {n} examples ===")
    print(f"function accuracy         {pct(func, n)}  ({func}/{n})")
    print(f"exact arguments           {pct(exact, n)}  ({exact}/{n}) normalized, {pct(raw, n)} as written")
    print(f"field accuracy            {pct(f_ok, f_all)}  ({f_ok}/{f_all} fields, on {len(fields)} right-function calls)")
    print(f"schema validity           {pct(valid, n)}  ({valid}/{n}), {defaults} with a default written out")
    print(f"correct abstention        {pct(abstained, len(neg))}  ({abstained}/{len(neg)} ambiguous or out of scope),"
          f" {pct(abstained_exact, len(neg)).strip()} the exact one")
    print(f"false abstention          {pct(false_abstain, len(pos))}  ({false_abstain}/{len(pos)} real requests)")
    print(f"\n{'expected function':<20}{'n':>4}{'function':>10}{'exact':>8}")
    by_fn = defaultdict(list)
    for r in results:
        by_fn[r["expected"]["name"]].append(r)
    for name in order:
        rs = by_fn.get(name, [])
        if rs:
            print(f"{name:<20}{len(rs):>4}{pct(sum(r.get('function_ok', False) for r in rs), len(rs)):>10}"
                  f"{pct(sum(r.get('exact', False) for r in rs), len(rs)):>8}")
    print(f"\n{'kind':<20}{'n':>4}{'function':>10}{'exact':>8}")
    by_kind = defaultdict(list)
    for r in results:
        by_kind[r["kind"]].append(r)
    for kind in ("single", "answer", "adjust", "correct"):
        rs = by_kind.get(kind, [])
        if rs:
            print(f"{kind:<20}{len(rs):>4}{pct(sum(r.get('function_ok', False) for r in rs), len(rs)):>10}"
                  f"{pct(sum(r.get('exact', False) for r in rs), len(rs)):>8}")
    errors = Counter(r["error"].split(":")[0] for r in results if r["error"])
    if errors:
        print(f"\ninvalid outputs: {dict(errors)}")
    return {"function": func / n, "exact": exact / n, "valid": valid / n,
            "abstention": abstained / len(neg) if neg else None,
            "false_abstention": false_abstain / len(pos) if pos else None}


def show_mistakes(results, prompts_by_id):
    wrong = [r for r in results if not r.get("exact", False)]
    print(f"\nmistakes ({len(wrong)}):")
    for r in wrong:
        user = prompts_by_id[r["id"]]
        got = r["predicted"] or {"raw": r["output"][:120]}
        print(f"- {r['id']} [{r['kind']}] {user!r}\n    expected {json.dumps(r['expected'])}\n"
              f"    got      {json.dumps(got)}" + (f"\n    {r['error']}" if r["error"] else ""))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--models", default="base,pilot", help="comma-separated: base, pilot or a model folder")
    parser.add_argument("--device", default="cpu", choices=["cpu", "mps", "cuda"])
    a = parser.parse_args()

    tools, order = load_tools()
    rendered = {}
    for line in (DATA_DIR / "eval_rendered.jsonl").read_text().splitlines():
        r = json.loads(line)
        rendered[r["id"]] = r
    examples, last_user = [], {}
    for line in (DATA_DIR / "eval.jsonl").read_text().splitlines():
        e = json.loads(line)
        call = e["messages"][-1]["tool_calls"][0]["function"]
        examples.append({"id": e["id"], "kind": e["kind"], "call": (call["name"], call["arguments"]),
                         "prompt": rendered[e["id"]]["prompt"]})
        last_user[e["id"]] = [m["content"] for m in e["messages"] if m["role"] == "user"][-1]

    summaries = {}
    for label in a.models.split(","):
        model_dir = MODELS.get(label, Path(label))
        print(f"generating with {label} ({model_dir})")
        outputs = generate(model_dir, [e["prompt"] for e in examples], a.device)
        results = [score(tools, e, o) for e, o in zip(examples, outputs)]
        out_path = OUT_DIR / f"eval_{Path(label).name}.jsonl"
        with out_path.open("w") as f:
            for r in results:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        summaries[label] = (report(label, results, order), results)
        print(f"predictions written to {out_path}")

    if len(summaries) > 1:
        print(f"\n=== comparison ===\n{'':<20}" + "".join(f"{k:>10}" for k in summaries))
        for metric in ("function", "exact", "valid", "abstention", "false_abstention"):
            print(f"{metric:<20}" + "".join(f"{pct(s[metric], 1):>10}" if s[metric] is not None else f"{'-':>10}"
                                             for s, _ in summaries.values()))
    last = list(summaries.values())[-1][1]
    show_mistakes(last, last_user)


if __name__ == "__main__":
    main()
