# On-device model

This folder holds the FunctionGemma 270M model that the personalization
feature runs on the device (see `docs/ai-personalization-plan.md`, Phase 3).
The model file is about 284 MB, too large for git, so it is not committed.
Fetch it before building a release or study APK:

```sh
./scripts/fetch_personalization_model.sh
```

A build without the file works normally; the "Tell the app what is hard"
feature is then hidden.

The model only runs on Android 11 (API 30) or later, in an arm64 app process.
On an x86_64 emulator, build an arm64-only APK
(`flutter build apk --target-platform android-arm64`): the emulator translates
it.

## License

FunctionGemma is provided under and subject to the Gemma Terms of Use,
https://ai.google.dev/gemma/terms, and the Gemma Prohibited Use Policy,
https://ai.google.dev/gemma/prohibited_use_policy. Anyone who receives an APK
with this file bundled must also receive these terms.

Source of the converted file: https://huggingface.co/sasha-denisov/function-gemma-270M-it
(converted from https://huggingface.co/google/functiongemma-270m-it).
