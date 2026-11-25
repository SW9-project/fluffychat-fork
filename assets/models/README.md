# On-device model

This folder holds the model that the personalization feature runs on the device
(see `docs/ai-personalization-plan.md`, Phase 3). The file is about 284 MB, too
large for git, so it is not committed.

| File | What it is | Bundled |
|---|---|---|
| `functiongemma-270M-sw9-tools2.litertlm` | Train2: FunctionGemma fine-tuned on the 19 functions in `assets/personalization_tools.json`, which the app runs | yes |
| `train1/functiongemma-270M-sw9-tools1.litertlm` | Train1: the first model (11 functions), kept for comparison | no |
| `baseline/functiongemma-270M-it.litertlm` | The base model: kept for comparison, and the converter copies its metadata | no |

## The fine-tuned model

`functiongemma-270M-sw9-tools2.litertlm` is built in this repository from the
Train2 training run in `training/` (see `training/TRAINING.md`, steps 5 to 7):

```sh
bash scripts/fetch_personalization_model.sh --baseline   # the converter needs it
training/.convert-venv/bin/python training/convert.py
```

`convert.py` writes the file here. It is not attached to any release yet, so a fresh
clone has to build it, or copy it from someone who has. sha256 of the file built from
Train2 on 2026-11-22 (also in `model.json`):

```
2f44a436c8020544b96c67051f19e8c4d5dc835d90ebdea2854b13ed5120fd84
```

The model is trained on the exact words of the functions, so changing
`assets/personalization_tools.json` means training again.
`test/personalization/personalization_tools_test.dart` holds the app to the file.

The file has a 4096-token context (the base file has 1024): the nineteen declarations
alone are about 2600 tokens.

A build without the file works normally; the Assist tab then says the assistant
cannot run on this phone.

The model only runs on Android 11 (API 30) or later, in an arm64 app process on an
arm64 device. The app reports the model as unavailable on x86 devices, including the
x86_64 emulator: there LiteRT crashes under ARM translation
(`function_gemma_model.dart`, `isSupported`). The arm64 emulator on an Apple silicon
Mac runs it.

## Checking it on a device

```sh
flutter test integration_test/personalization_model_test.dart -d <device>
```

sends the 158 held-out examples through the app's own path and compares the calls
with the labels, as `training/evaluate.py` does on the Mac. It also renders each
prompt with LiteRT-LM and compares it with the prompt the model was trained on.
Clear the app's data first when the device had another model file: a file that is
already installed is not installed again, and the plugin restores the model that was
active last. The test fails rather than reporting numbers for the wrong one.

## The baseline

```sh
bash scripts/fetch_personalization_model.sh --baseline
```

downloads the base model into `baseline/`. Flutter does not bundle subfolders of
`assets/models/`, so it does not reach the APK.

## Licenses

Gemma is provided under and subject to the Gemma Terms of Use found at
ai.google.dev/gemma/terms. The Gemma Prohibited Use Policy also applies:
https://ai.google.dev/gemma/prohibited_use_policy. Anyone who receives an APK with
the model bundled must also receive a copy of these terms and be told the use
restrictions apply.

The bundled model is a modified version of FunctionGemma. `NOTICE.txt` in this
folder holds the notice and is bundled with the model.

Source of the baseline file: https://huggingface.co/sasha-denisov/function-gemma-270M-it
(converted from https://huggingface.co/google/functiongemma-270m-it).
