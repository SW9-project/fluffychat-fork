# How to run FluffyChat on Android and iOS

## Requirements (both platforms)

- [Flutter](https://flutter.dev) (stable channel)
- [Rust](https://www.rust-lang.org/tools/install) (used to build the vodozemac encryption library)
- CMake (used to build the `webcrypto` package):
  ```sh
  brew install cmake
  ```

Get the dependencies once, from the project root:

```sh
flutter pub get
```

Check your setup at any time with:

```sh
flutter doctor
```

> **Note:** the commands below use real names and IDs. When you see a placeholder like
> `DEVICE_ID`, replace the whole word. Don't type `<` or `>` around it: zsh treats those
> as redirections and fails with `parse error near '\n'`.

---

## Android

### Quick start: one command

Once everything below is set up, start the app with:

```sh
./scripts/run-android.sh                       # Pixel 10 Pro
./scripts/run-android.sh Pixel_9               # another emulator, by AVD name
./scripts/run-android.sh Pixel_9 --release     # extra arguments go to `flutter run`
```

The script starts the emulator (or reuses it if it's already running), waits for it to boot and runs the app.
It looks for the Android SDK in `$ANDROID_HOME`, then `~/Library/Android/sdk`.

### 1. Add the Rust targets for Android

```sh
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
```

### 2. Start an emulator (or plug in a phone)

List the available emulators and launch one:

```sh
flutter emulators
flutter emulators --launch Pixel_10_Pro
```

To use a physical phone instead, turn on **Developer options → USB debugging** on it and connect it with a cable.

### 3. Run the app

```sh
flutter devices                 # find the emulator/phone ID
flutter run -d DEVICE_ID        # e.g. flutter run -d emulator-5554
```

Debug builds are signed with the default debug key, so you don't need `android/key.properties`.

---

## iOS (macOS only)

### Quick start: one command

Once everything below is set up, start the app with:

```sh
./scripts/run-ios.sh                           # iPhone 17 Pro
./scripts/run-ios.sh "iPhone Air"              # another simulator, by name or UDID
./scripts/run-ios.sh "iPhone Air" --release    # extra arguments go to `flutter run`
```

The script boots the simulator, opens DeviceHub (or the Simulator app on older Xcode) and runs the app.

### 1. Add the Rust targets for iOS

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

### 2. Make sure the iOS Simulator is installed

In Xcode, open **Settings → Components** and install the iOS platform/simulator if it isn't there.
`flutter doctor` warns you if it's missing.

### 3. Start a simulator

```sh
xcrun simctl list devices available | grep iPhone   # list simulators and their IDs
xcrun simctl boot "iPhone 17 Pro"                    # boot one
open -a DeviceHub                                    # show it (Xcode 27+)
open -a Simulator                                    # show it (older Xcode)
```

If `simctl boot` says `Unable to boot device in current state: Booted`, the simulator is already running.

### 4. Run the app

```sh
flutter run -d "iPhone 17 Pro"
```

The simulator doesn't need code signing. The first build takes a while because it compiles the Rust code.

### Running on a physical iPhone

The project is signed with the maintainer's Apple team, so you need to change the signing to your own:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. For each target (**Runner**, **FluffyChat Share**, **Notification Service Extension**), go to
   **Signing & Capabilities**, choose your team and set your own bundle ID
   (e.g. `com.yourname.fluffychat`). The extensions' IDs must start with the app's ID.
3. With a free Apple ID, remove **Push Notifications** and **Associated Domains**, and change the
   App Group (`group.im.fluffychat.app`) to one under your own ID.
4. Connect the iPhone, trust the computer and turn on **Developer Mode** on the phone.
5. Run `flutter run -d DEVICE_ID` (find the ID with `flutter devices`).

Don't commit these signing changes.

---

## Troubleshooting

| Error | Fix |
| --- | --- |
| `Failed to find cmake version: latest` (package `webcrypto`) | `brew install cmake` |
| `zsh: parse error near '\n'` | Remove the `<` `>` around the device ID |
| `Unable to find application named 'Simulator'` | On Xcode 27+, use `open -a DeviceHub` instead |
| Rust / vodozemac build errors | Add the Rust targets for your platform (see above) |
| `Undefined symbols for architecture x86_64: "_fiat_p256_adx_mul"` | Bug in `webcrypto` 0.6.1 for Intel simulators. On Apple Silicon, use `flutter run` on a simulator (it builds arm64 only) instead of `flutter build ios --simulator` |
