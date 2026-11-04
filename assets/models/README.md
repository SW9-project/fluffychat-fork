# On-device model

This folder holds the model that the personalization feature runs on the device
(see `docs/ai-personalization-plan.md`, Phase 3). The file is about 285 MB, too
large for git, so it is not committed.

| File | What it is | Bundled |
|---|---|---|
| `functiongemma-270M-sw9-pilot1.litertlm` | The fine-tuned **pilot**, which the app runs | yes |
| `baseline/functiongemma-270M-it.litertlm` | The base model, kept for comparison | no |

## The pilot

`functiongemma-270M-sw9-pilot1.litertlm` is an end-to-end pilot, trained on the
two draft placeholder heuristics in `assets/personalization_heuristics.json`. It
only shows that the path from training to the phone works. It is not for a study.
Its results and limits are in the model card:
`docs/model_cards/functiongemma-270M-sw9-pilot1.md` in the
`functiongemma-heuristics` repository.

The file is not published. Build it in that repository (`eval/convert.sh`) and copy
it here. sha256:

```
834126ed04d2cba810eb2de65da6dc580983afa6d25be3518157d1dfbb27cc74
```

The model is trained on the exact words of the functions the app offers. Changing a
heuristic's `rule` or `id` means training again, which
`test/personalization/heuristic_functions_test.dart` checks.

A build without the file works normally; the "Tell the app what is hard" feature is
then hidden.

The model only runs on Android 11 (API 30) or later, in an arm64 app process on an
arm64 device. The app reports the model as unavailable on x86 devices, including the
x86_64 emulator: there LiteRT crashes under ARM translation
(`function_gemma_model.dart`, `isSupported`). Test the model on a real arm64 phone.

## The baseline

```sh
./scripts/fetch_personalization_model.sh
```

downloads the base model into `baseline/`. Flutter does not bundle subfolders of
`assets/models/`, so it does not reach the APK.

To run it:

- **Next to the pilot:** push it to the app's external files folder and run
  `integration_test/personalization_render_test.dart`, which renders prompts and
  sends real requests on every `.litertlm` there.
- **The whole phrase harness:** check out `feat/ai-personalization`, put the file back
  in `assets/models/`, build, and clear the app's data first. A file that is already
  installed is not installed again, and the plugin restores the model that was active
  last; `integration_test/personalization_model_test.dart` fails rather than reporting
  numbers for the wrong one.

## Licenses

Gemma is provided under and subject to the Gemma Terms of Use found at
ai.google.dev/gemma/terms. The Gemma Prohibited Use Policy also applies:
https://ai.google.dev/gemma/prohibited_use_policy. Anyone who receives an APK with
either file bundled must also receive a copy of these terms and be told the use
restrictions apply.

The pilot is a modified version of FunctionGemma, fine-tuned on data that includes
utterances from MASSIVE 1.1 by Amazon (CC BY 4.0,
https://creativecommons.org/licenses/by/4.0/). `NOTICE.txt` in this folder holds the
notice and attribution, and is bundled with the model. The full attribution and
citations are in `NOTICE` in the `functiongemma-heuristics` repository.

Source of the baseline file: https://huggingface.co/sasha-denisov/function-gemma-270M-it
(converted from https://huggingface.co/google/functiongemma-270m-it).
