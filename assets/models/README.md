# Modelo SW9 v2

This folder holds the model that the personalization feature runs on the device
(see `docs/ai-personalization-plan.md`, Phase 3). The file is about 284 MB, too
large for git, so it is not committed.

| File | What it is | Bundled |
|---|---|---|
| `functiongemma-270M-sw9-tools1.litertlm` | FunctionGemma fine-tuned on the eleven functions in `assets/personalization_tools.json`, which the app runs | yes |
| `baseline/functiongemma-270M-it.litertlm` | The base model: kept for comparison, and the converter copies its metadata | no |
| `baseline/functiongemma-270M-sw9-pilot1.litertlm` | The earlier pilot, trained on two placeholder heuristics | no |

## The fine-tuned model

`functiongemma-270M-sw9-tools1.litertlm` is built in this repository from the
training run in `training/` (see `training/TRAINING.md`, steps 5 to 7):

```sh
bash scripts/fetch_personalization_model.sh --baseline   # the converter needs it
training/.convert-venv/bin/python training/convert.py
```

`convert.py` writes the file here. It is not attached to any release yet, so a fresh
clone has to build it, or copy it from someone who has. sha256 of the file built from
`checkpoint-1561` (epoch 7) on 2026-11-11:

```
37e92741110b1a7bff2607905a3598186d42de36beabe9091400879ef7d1383b
```

The model is trained on the exact words of the functions, so changing
`assets/personalization_tools.json` means training again.
`test/personalization/personalization_tools_test.dart` holds the app to the file.

The file has a 2048-token context (the base file has 1024): the eleven declarations
alone are about 1300 tokens.

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

## The baseline and the pilot

```sh
bash scripts/fetch_personalization_model.sh --baseline
bash scripts/fetch_personalization_model.sh --pilot
```

download the base model and the pilot into `baseline/`. Flutter does not bundle
subfolders of `assets/models/`, so they do not reach the APK. The pilot comes from
the `pilot1` release of the private `functiongemma-heuristics` repository and needs
the GitHub CLI and access to it.

## Licenses

Gemma is provided under and subject to the Gemma Terms of Use found at
ai.google.dev/gemma/terms. The Gemma Prohibited Use Policy also applies:
https://ai.google.dev/gemma/prohibited_use_policy. Anyone who receives an APK with
the model bundled must also receive a copy of these terms and be told the use
restrictions apply.

The bundled model is a modified version of FunctionGemma. `NOTICE.txt` in this
folder holds the notice and is bundled with the model. The pilot was fine-tuned on
data that includes utterances from MASSIVE 1.1 by Amazon (CC BY 4.0); its
attribution is in `NOTICE` in the `functiongemma-heuristics` repository.

Source of the baseline file: https://huggingface.co/sasha-denisov/function-gemma-270M-it
(converted from https://huggingface.co/google/functiongemma-270m-it).
