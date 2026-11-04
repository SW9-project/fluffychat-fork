# On-device model

The personalization feature runs its model on the device (see
`docs/ai-personalization-plan.md`, Phase 3). The file is about 285 MB, so neither git
nor a normal build holds it. It is a release of the public repository
[SW9-project/sw9-models](https://github.com/SW9-project/sw9-models/releases).

Which file the app runs, where it comes from and its SHA-256 are one constant:
`currentModel` in `lib/personalization/model/model_release.dart`.

## Normal builds: nothing to set up

Build and run the app. The first time the Assist tab's **Set up** is tapped, the app
downloads the file with `flutter_edge_ai` and shows the progress. It then checks the
file's SHA-256, and nothing opens the file before that check passes. A file that fails
it is deleted, and the tab offers to try again.

The tab can be left during the download. The download goes on, and the tab shows it
again on return. The check runs once per install, not each time the tab opens.

A download shows GitHub the phone's IP address. No user data is sent, and inference
stays on the device.

## Study builds: no Wi-Fi needed

```sh
./scripts/build_study_apk.sh
```

This builds an APK with the model inside, with `--dart-define=SW9_BUNDLED_MODEL=true`,
for arm64. Tapping **Set up** then copies the file from the APK, about 40 s on the S22
Ultra, and runs the same check. Arguments go to `flutter build apk`, instead of the
default `--release`.

Flutter bundles whatever is in this folder, and a dart-define cannot change that. So
the script puts the file here only for that build and removes it after. Leave no
`.litertlm` here yourself: the APK would grow by 285 MB and the app would ignore the file,
which `test/personalization/model_release_test.dart` checks.

## Publishing a new model

1. Convert it with `eval/convert.sh` in the training repository.
2. Create a release in `sw9-models`, tagged like `pilot1` or `v1`, with the file,
   `NOTICE.txt`, `GEMMA_TERMS.txt` and the model card. Mark pilots as test models.
3. Change `currentModel`, and update `NOTICE.txt` here. The file name must be new, and it
   must contain the tag.
4. If the functions changed, export them to `assets/personalization_heuristics.json`.
   The model is trained on their exact words, which
   `test/personalization/heuristic_functions_test.dart` checks.

Phones then offer Set up again, and remove the earlier file once the new one has passed
its check.

## The current model

`functiongemma-270M-sw9-pilot1.litertlm` is an end-to-end pilot, trained on the two draft
placeholder heuristics in `assets/personalization_heuristics.json`. It only shows that
the path from training to the phone works. It is not for a study. Its results and limits
are in its [model card](https://github.com/SW9-project/sw9-models/releases/tag/pilot1).

The model only runs on Android 11 (API 30) or later, in an arm64 app process on an arm64
device. The app reports the model as unavailable on x86 devices, including the x86_64
emulator: there LiteRT crashes under ARM translation (`function_gemma_model.dart`,
`isSupported`). Test the model on a real arm64 phone.

## The baseline

The base model is kept for comparison. To get it:

```sh
mkdir -p assets/models/baseline
curl --fail --location --output assets/models/baseline/functiongemma-270M-it.litertlm \
  https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm
```

Its sha256 is `680fead1cca41a23220c904500a515d06e41f5c66d130aa4a9cc5905ec529a8e`. Flutter
does not bundle subfolders of `assets/models/`, so it does not reach the APK. To run it,
push it to the app's external files folder and run
`integration_test/personalization_render_test.dart`, which renders prompts and sends real
requests on every `.litertlm` there. That leaves it the active model, so clear the app's
data afterwards.

Source of the baseline file:
https://huggingface.co/sasha-denisov/function-gemma-270M-it (converted from
https://huggingface.co/google/functiongemma-270m-it).

## Licenses

Gemma is provided under and subject to the Gemma Terms of Use found at
ai.google.dev/gemma/terms. The Gemma Prohibited Use Policy also applies:
https://ai.google.dev/gemma/prohibited_use_policy.

Anyone who gets the model must get a copy of those terms and this notice, and be told the
use restrictions apply. So:

- `NOTICE.txt` and `GEMMA_TERMS.txt` are on the app's licenses screen (Settings, About,
  View licenses), and attached to the release.
- The Set up screen says the terms apply and links to them.

`GEMMA_TERMS.txt` was saved unchanged from the official page, last modified April 1, 2026.
Check that page when publishing a new model.

The pilot is a modified version of FunctionGemma, fine-tuned on data that includes
utterances from MASSIVE 1.1 by Amazon (CC BY 4.0,
https://creativecommons.org/licenses/by/4.0/). `NOTICE.txt` holds the attribution.
