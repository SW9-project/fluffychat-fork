# Training (step 5): decisions and problems

How `train.py` fine-tunes FunctionGemma 270M on the rendered dataset, which values differ
from Google's guide and why, and what went wrong on the way.

```sh
training/.venv/bin/python training/render_dataset.py   # step 4: writes data/*_rendered.jsonl
training/.venv/bin/python training/train.py            # step 5
training/.venv/bin/python training/train.py --resume   # continue after an interruption
training/.venv/bin/python training/train.py --max-steps 5   # smoke test
```

Environment: M1 Pro, 16 GB, macOS (Darwin 27.2), PyTorch 2.15, Transformers 5.22, TRL 1.17.

## Settings compared with Google's guide

| Guide | `train.py` | Why |
|---|---|---|
| learning rate 5e-5, constant scheduler | same | |
| optimizer `adamw_torch_fused` | same | |
| full fine-tune | same on CPU and CUDA (268M parameters) | On `mps` the embedding table is frozen, see below. |
| maximum length 512 | **1536** | The 11 function declarations alone are ~1300 tokens; examples are 1344 to 1442 tokens. At 512 every example would be truncated before the call, so nothing would be learned. |
| batch 4 per device | **batch 1, gradient accumulation 4** | Same effective batch of 4. Batch 2 already exhausted the GPU memory, mostly because of the 262k-token vocabulary. |
| 8 epochs | **at most 8, early stopping (patience 2)** | 1050 examples of a few calls phrased many ways overfit quickly. Evaluation after every epoch; the epoch with the lowest `eval_loss` is kept. Also saves hours on CPU. |
| bf16 | **fp32 on CPU and mps, bf16 on CUDA** | The M1 has no fast bf16; fp16 is unstable with Gemma 3. 270M parameters fit in fp32. |
| eager attention | **sdpa** | Eager is only needed for attention soft-capping, and this model has `attn_logit_softcapping: null`, so sdpa computes the same and is faster. |
| GPU | **CUDA if present, otherwise CPU** | Apple's GPU is unreliable for this run, see below. |

## Loss only on the final call

`train.py` tokenizes the rendered `prompt` and `completion` itself (with
`add_special_tokens=False`, because the render already starts with `<bos>`) and passes TRL a
dataset that is already tokenized: `input_ids` plus a `completion_mask`. Only the final call
counts towards the loss.

Why not let TRL do it: for a prompt/completion text dataset, TRL appends the tokenizer's
`eos_token` (`<eos>`) to every completion. Ours already ends with
`<start_function_response>`, which is one of the model's stop tokens (`eos_token_id`
`[1, 50, 106]`), so the model would learn an extra `<eos>` after it. Setting TRL's
`eos_token` option instead would also change the `eos_token` of the tokenizer that gets
saved with the model.

The script checks that the prompt tokens plus the completion tokens are exactly the
tokens of the full text, and that no example is longer than 1536.

## Problem: Apple's GPU (mps) crashes during training

The first full run on `mps` failed after 6 steps:

```
torch.AcceleratorError: MPS command buffer execution failed: Ignored (for causing prior/excessive GPU errors)
```

The error is asynchronous, so the traceback (`torch.isnan(tr_loss_step)` in the Trainer)
does not show the real cause. Across many test runs the underlying errors were:

- `Insufficient Memory`
- `Caused GPU Hang Error` (the macOS GPU watchdog)
- `Discarded (victim of GPU error/recovery)`

What was found and tried:

| Attempt | Result |
|---|---|
| Measure memory | Real tensors peak at 5.5 GB (4.0 GB with gradient checkpointing). PyTorch's MPS cache grew to ~10 GB because every example has a different length; the GPU limit is 11.8 GB. |
| Gradient checkpointing | Less memory, still crashed. |
| Free the cache every step (`torch_empty_cache_steps=1`) | Still crashed. |
| Cap the cache (`PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.6`) | Turned some failures into a clean `MPS backend out of memory` at 6.7 GB; others became GPU hangs. |
| Suspect TRL's fused LM head, clipping, `attention_mask` | The same crashes happened in a plain PyTorch loop without the Trainer, with and without each of these. Not the cause. |
| Look for another app using the GPU | Idle GPU use was 2 to 6%. The GPU `recoveryCount` (ioreg) went up during our runs: our own work trips the watchdog. |
| eager vs sdpa attention | eager hung within the first step; sdpa with checkpointing passed 8 steps. |
| Freeze the embedding table (168M of the 268M parameters) | Fits easily, but sdpa + checkpointing + frozen embeddings still hung within 40 steps. |
| Full fine-tune on mps with sdpa | Hung. |

Conclusion: with this PyTorch/macOS combination, training on `mps` randomly trips the GPU
watchdog no matter the settings. Short runs sometimes pass, long ones do not.

Decision: train on the CPU. It is slower but has never failed, and it allows the full
fine-tune of the guide.

| Device | Seconds per step (4 examples) |
|---|---|
| mps, batch 1 × 4 (when it did not crash) | 9 to 11 |
| CPU, frozen embeddings | ~15 |
| CPU, full fine-tune, sdpa | ~20 |

With 223 steps per epoch, the CPU needs about 1¼ hours per epoch, at most ~10 hours for 8
epochs, probably 4 to 6 with early stopping. Run it under `caffeinate -i` so the Mac does
not sleep; every epoch is saved, so `--resume` continues after an interruption.

`--device mps` is still available. It then uses the settings that got furthest: sdpa,
gradient checkpointing (non-reentrant), frozen embeddings and the capped MPS cache (set at
the top of `train.py`). Expect it to crash.

On a CUDA GPU (Colab, for example) the same script trains every parameter in bf16, in well
under an hour.

## Result of the first run (2026-11-10)

All 8 epochs on the CPU, 7.8 hours, with no crash. Early stopping never triggered, because
no two epochs in a row failed to improve.

| Epoch | eval_loss | eval token accuracy |
|---|---|---|
| 1 | 0.158 | 95.9% |
| 2 | 0.106 | 97.0% |
| 3 | 0.091 | 97.6% |
| 4 | 0.091 | 98.0% |
| 5 | 0.079 | 98.4% |
| 6 | 0.095 | 98.3% |
| **7** | **0.063** | **98.4%** |
| 8 | 0.129 | 97.7% |

The saved model is epoch 7 (`checkpoint-1561`). The jump at epoch 8, while the training loss
kept falling (~0.02), is the start of overfitting, so 8 epochs is the right ceiling.

Token accuracy counts single tokens, not whole calls: one wrong argument in a correct-looking
call barely moves it. Whether the model picks the right function and arguments has to be
measured by generating calls for `data/eval.jsonl` and comparing them exactly.

## Output

- `output/functiongemma-pilot/`: the best epoch (model and tokenizer), plus up to two
  epoch checkpoints (`checkpoint-*`: the best and the latest), which `--resume` uses.
- `output/train.log`: the log. `eval_loss` after every epoch is the number to watch.

`training/functiongemma-270m-it/` and `training/output/` are in `.gitignore`.

# Evaluation (step 6)

```sh
training/.venv/bin/python training/evaluate.py                 # base and pilot
training/.venv/bin/python training/evaluate.py --models pilot
```

`evaluate.py` generates greedily (no sampling, at most 128 new tokens, stopping at the
model's stop tokens) from every prompt in `data/eval_rendered.jsonl`, parses the call
and compares it with the label in `data/eval.jsonl`. It runs on the CPU, about 1.6 s per
example, so ~4 minutes per model. Every prediction is written to
`output/eval_<model>.jsonl`, and the report ends with every mistake of the last model.

## Metrics

- **Function accuracy**: the right function was called.
- **Exact arguments**: the right function with exactly the labelled arguments. Reported
  normalized (defaults dropped and `options` sorted, as `build_dataset.py` labels) and as
  written. Here both numbers were equal for both models.
- **Field accuracy**: over calls to the right function, the share of argument fields
  (in the label or the prediction) that have the same value.
- **Schema validity**: exactly one parseable call to a declared function, with declared
  parameters of the right types, enum values and ranges, and every required parameter.
  It uses `normalize_call` from `build_dataset.py`, which also counts calls that write
  out a default.
- **Correct abstention**: of the requests labelled `ask_clarification` or `no_action`,
  the share where the model called one of the two, and the share where it called the
  exact one. **False abstention**: of all other requests, the share where it wrongly did.

A self-check is to score the labelled completions themselves: all 158 parse, pass the
schema and match exactly.

## Results (2026-11-10)

158 evaluation examples: 143 single requests, 15 conversations, 23 abstentions.

| Metric | Base | Fine-tuned (epoch 7) |
|---|---|---|
| Function accuracy | 41.1% (65) | **87.3%** (138) |
| Exact arguments | 13.9% (22) | **78.5%** (124) |
| Field accuracy | 33.9% | **91.6%** |
| Schema validity | 48.1% (76) | **98.7%** (156) |
| Defaults written out | 7 | **0** |
| Correct abstention (of 23) | 0% | **82.6%** (69.6% the exact one) |
| False abstention (of 135) | 5.2% | **0.7%** |

The base model never abstains and half of its outputs do not parse (40) or break the
schema (42). With 158 examples one example is 0.6 points, and a percentage is uncertain
by about ±6 points.

By expected function (fine-tuned):

| Function | n | Function acc. | Exact |
|---|---|---|---|
| change_text_size | 33 | 93.9% | 81.8% |
| change_button_size | 22 | 90.9% | 81.8% |
| change_spacing | 12 | **58.3%** | **50.0%** |
| set_simple_mode | 12 | 91.7% | 83.3% |
| set_button_labels | 11 | 90.9% | 81.8% |
| set_high_contrast | 11 | 100% | 90.9% |
| change_avatar_size | 11 | 100% | 100% |
| set_theme | 12 | 91.7% | 66.7% |
| reset_settings | 11 | 90.9% | 90.9% |
| ask_clarification | 10 | 60.0% | 50.0% |
| no_action | 13 | 76.9% | 76.9% |

Conversations: all 6 `answer` and all 6 `adjust` exact, 1 of 3 `correct`.

## What the fine-tuned model gets wrong (34 mistakes)

1. **Spacing taken for button size (5).** "the buttons are crammed", "too tight", "my
   finger touches two buttons at once", "it's too crowded, I hit the wrong icons", "give
   the buttons some breathing room" all gave `change_button_size`. The rule that wrong
   taps because buttons are close together mean `change_spacing` is not learned.
2. **Direction or on/off reversed (7).** "the brightness is blinding me" and "the white is
   too bright" gave `light`, "it's all black" gave `dark`, "remove the labels" and "basic
   mode" got the wrong `enabled`, "the colors are too harsh" turned high contrast on,
   "bring the buttons closer together" gave `more`. The model leans to `true`, `bigger`,
   `more`.
3. **Names and values copied badly (3).** "Dr. Hansen" became `Dr`, "Neighbours" became
   ` Neigh` (with a leading space), "magnifying glass" became ` magnifying` instead of
   `search` (invalid). Names of several tokens or with punctuation are fragile.
4. **Too few clarifications (4 of 10 missed).** "it's all too large" and "I can't read
   anything" went straight to `change_text_size`, "the text size" guessed `bigger`, "I'm
   lost" gave `no_action`.
5. **Out of scope acted on (3 of 13).** "block this person" turned on simple mode, the
   worst kind of mistake because the app changes something. "change the language to
   Spanish" and "asdfgh" asked for clarification.
6. **Other single confusions.** For example "the button to add photos is too small" gave
   `change_avatar_size`, "normal spacing again" gave `change_spacing` instead of
   `reset_settings`, "same colors as my phone" gave high contrast instead of `system`,
   and one invented function, `set_text__button`.

## Next

More examples aimed at the first three groups should help most: contrasting pairs for
spacing and button size, more phrasings for turning things off, smaller, less and dark,
and chat names with dots, spaces and longer words. Then build, render, train and run
`evaluate.py` again to compare.

# Conversion (step 7)

```sh
uv venv training/.convert-venv --python 3.12
VIRTUAL_ENV=training/.convert-venv uv pip install litert-torch
bash scripts/fetch_personalization_model.sh --baseline
training/.convert-venv/bin/python training/convert.py
```

`convert.py` turns `output/functiongemma-pilot/` (epoch 7) into
`assets/models/functiongemma-270M-sw9-tools1.litertlm`, the file the app runs. It
takes about 3 minutes on the M1 Pro. Environment: litert-torch 0.10.0 (PyTorch 2.14.1),
litert-lm-builder 0.19.1, in its own venv because litert-torch pins an older PyTorch
than `train.py` uses.

## Same as the base file, except the context

The base file (`baseline/functiongemma-270M-it.litertlm`) is the reference, because
the app already ran it through the plugin:

| | Base file | `tools1` |
|---|---|---|
| LLM metadata | start `<bos>`, stop `<end_of_turn>` and `<start_function_response>`, model type `function_gemma` (LiteRT-LM's own FunctionGemma formatter, no Jinja template) | copied from the base file |
| Tokenizer | SentencePiece | copied from the base file (identical to `functiongemma-270m-it/tokenizer.model`) |
| Signatures | `prefill_256`, `decode` | same |
| KV cache, `max_num_tokens` | 1024 | **2048** |
| KV layout, mask | transposed, mask as input | same |
| Quantization | dynamic int8 | same |

The context is the one change: the eleven declarations are ~1300 tokens, so a 1024
cache cannot hold a single request.

## Problems on the way

| Problem | Fix |
|---|---|
| `litert_torch` imports `tensorflow.lite.python.schema_py_generated` in its LoRA layer | Installing TensorFlow next to `litert-converter` crashes on import (`Option 'info-output-file' registered more than once`, both ship LLVM). `convert.py` points that one import at `ai_edge_litert`'s copy of the same schema instead. |
| `convert_to_litert(output_format="litertlm")` calls `litertlm_builder.TfLiteModelType`, which litert-lm-builder 0.19 no longer has | `convert.py` exports only the `.tflite` (kept in `output/convert/`, so packing again does not convert again) and packs it with the base file's own `model.toml`, swapping in the new model. |

## Check on the Mac

The converted `.tflite` was run with the LiteRT interpreter on 8 prompts from
`data/eval_rendered.jsonl` (greedy, prefill in chunks of 256): its output was the same
as the PyTorch model's in `output/eval_pilot.jsonl`, token for token, for all 8,
including the 3 the model gets wrong. So the conversion does not change the answers.
For the same check on a device, see `integration_test/personalization_model_test.dart`
(`assets/models/README.md`).
