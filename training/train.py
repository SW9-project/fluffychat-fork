#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 SW9-project contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Fine-tunes FunctionGemma on Train2/data/train_rendered.jsonl with TRL's SFTTrainer.

    training/.venv/bin/python training/render_dataset.py   # first, step 4
    training/.venv/bin/python training/train.py
    training/.venv/bin/python training/train.py --max-steps 5   # smoke test
    training/.venv/bin/python training/train.py --resume        # after an interruption

The rendered prompt and completion are tokenized here, without adding special
tokens (the render already starts with <bos>), and only the completion (the
final call, ending in <start_function_response>, one of the model's stop
tokens) counts towards the loss. Doing this before the trainer sees the data
keeps TRL from appending <eos> after the stop token or touching the tokenizer.

Evaluates on Train2/data/eval_rendered.jsonl after every epoch, stops when two epochs
in a row do not improve the evaluation loss, and keeps the best epoch in
Train2/output/functiongemma.

Runs on CUDA when there is one, otherwise on the CPU (on an M1 Pro about an
hour per epoch). Apple's GPU (--device mps) is faster but, with PyTorch 2.15,
randomly trips the macOS GPU watchdog ("Caused GPU Hang Error") within a few
dozen steps, and a full fine-tune does not fit in its memory. With mps the
embedding table stays frozen; on CUDA and the CPU every parameter is trained,
as in Google's guide.
"""

import argparse
import json
import os
from pathlib import Path

# Cap PyTorch's MPS memory pool (default: 1.7x the GPU's working set, i.e. no cap). Varying sequence lengths
# make the cache grow until Metal fails the command buffer; with the cap it frees cached blocks first.
os.environ.setdefault("PYTORCH_MPS_HIGH_WATERMARK_RATIO", "0.6")
os.environ.setdefault("PYTORCH_MPS_LOW_WATERMARK_RATIO", "0.5")

import torch  # noqa: E402
from datasets import Dataset  # noqa: E402
from transformers import AutoModelForCausalLM, AutoTokenizer, EarlyStoppingCallback  # noqa: E402
from trl import SFTConfig, SFTTrainer  # noqa: E402

HERE = Path(__file__).resolve().parent
MODEL_DIR = HERE / "functiongemma-270m-it"
RUN = HERE / "Train2"
DATA_DIR = RUN / "data"
OUT_DIR = RUN / "output" / "functiongemma"

MAX_LENGTH = 4096  # the tool declarations alone are several thousand tokens
SEED = 20261107


def load(tokenizer, split):
    rows = [json.loads(line) for line in (DATA_DIR / f"{split}_rendered.jsonl").read_text().splitlines()]
    out = []
    for r in rows:
        prompt = tokenizer(r["prompt"], add_special_tokens=False).input_ids
        completion = tokenizer(r["completion"], add_special_tokens=False).input_ids
        ids = prompt + completion
        if ids != tokenizer(r["text"], add_special_tokens=False).input_ids:
            raise SystemExit(f"error: {r['id']}: prompt and completion do not tokenize like the full text")
        if len(ids) > MAX_LENGTH:
            raise SystemExit(f"error: {r['id']}: {len(ids)} tokens is over {MAX_LENGTH}")
        out.append({"input_ids": ids, "completion_mask": [0] * len(prompt) + [1] * len(completion)})
    return Dataset.from_list(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--max-steps", type=int, default=-1, help="stop early, for a smoke test")
    parser.add_argument("--output", type=Path, default=OUT_DIR)
    parser.add_argument("--device", choices=["cuda", "cpu", "mps"], help="default: cuda if there is one, else cpu")
    parser.add_argument("--train-embeddings", action=argparse.BooleanOptionalAction, default=None,
                        help="also train the embedding table (default: yes, except on mps)")
    parser.add_argument("--resume", action="store_true", help="continue from the last saved epoch")
    a = parser.parse_args()

    device = a.device or ("cuda" if torch.cuda.is_available() else "cpu")
    mps = device == "mps"
    use_bf16 = device == "cuda" and torch.cuda.is_bf16_supported()  # a T4 has no bf16
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_DIR,
        dtype=torch.bfloat16 if use_bf16 else torch.float32,
        # Eager attention, often recommended for Gemma, is only needed for attention soft-capping, which this model
        # does not use (attn_logit_softcapping is null). sdpa computes the same, faster, and hangs mps less often.
        attn_implementation="sdpa",
    )
    # The 262k x 640 embedding table (tied to the output layer) is 168M of the 268M parameters. Its gradients and
    # AdamW state do not fit in a 16 GB Mac's GPU next to the rest, so on mps only the 100M transformer
    # parameters are trained. The tool calls only use tokens the model already knows.
    train_embeddings = not mps if a.train_embeddings is None else a.train_embeddings
    model.get_input_embeddings().weight.requires_grad_(train_embeddings)
    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)

    train, evaluation = load(tokenizer, "train"), load(tokenizer, "eval")
    print(f"device {device}: {len(train)} train, {len(evaluation)} eval examples, "
          f"{trainable / 1e6:.0f}M trainable parameters")

    smoke = a.max_steps > 0
    config = SFTConfig(
        output_dir=str(a.output),
        num_train_epochs=8,
        max_steps=a.max_steps,
        learning_rate=5e-5,
        lr_scheduler_type="constant",
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,  # effective batch 4, as in Google's guide
        per_device_eval_batch_size=1,
        optim="adamw_torch_fused",
        # On mps: recomputes activations in the backward pass, about 1.5 GB less GPU memory per step
        gradient_checkpointing=mps,
        gradient_checkpointing_kwargs={"use_reentrant": False},  # works with frozen embeddings
        max_length=MAX_LENGTH,
        completion_only_loss=True,
        bf16=use_bf16,
        logging_steps=10,
        eval_strategy="no" if smoke else "epoch",
        save_strategy="no" if smoke else "epoch",
        save_total_limit=2,
        load_best_model_at_end=not smoke,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        dataloader_pin_memory=device == "cuda",
        use_cpu=device == "cpu",
        report_to="none",
        seed=SEED,
    )
    trainer = SFTTrainer(
        model=model,
        args=config,
        train_dataset=train,
        eval_dataset=evaluation,
        processing_class=tokenizer,
        # 8 epochs is the ceiling: stop once two epochs in a row fail to lower the eval loss
        callbacks=[] if smoke else [EarlyStoppingCallback(early_stopping_patience=2)],
    )
    trainer.train(resume_from_checkpoint=a.resume or None)
    if not smoke:
        trainer.save_model(str(a.output))
        tokenizer.save_pretrained(str(a.output))
        print(f"saved the best epoch to {a.output}")


if __name__ == "__main__":
    main()
