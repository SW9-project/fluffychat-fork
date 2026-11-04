// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// One published model file: where it is and what it must be.
class ModelRelease {
  /// Where the file is published. The plugin names the installed file after
  /// the last part of this URL, so [fileName] comes from it too.
  final String url;

  /// SHA-256 of the file, in lowercase hex. Checked before the file is used.
  final String sha256;

  final int sizeBytes;

  const ModelRelease({
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  String get fileName => Uri.parse(url).pathSegments.last;

  /// Where a study build holds the file. See `scripts/build_study_apk.sh`.
  String get assetPath => 'assets/models/$fileName';

  /// The size to tell the user before downloading.
  int get megabytes => (sizeBytes / 1000000).round();
}

/// The model this app runs. A new model means changing this one constant, and
/// `scripts/build_study_apk.sh` reads its URL and checksum from here.
const currentModel = ModelRelease(
  url:
      'https://github.com/SW9-project/sw9-models/releases/download/pilot1/functiongemma-270M-sw9-pilot1.litertlm',
  sha256: '834126ed04d2cba810eb2de65da6dc580983afa6d25be3518157d1dfbb27cc74',
  sizeBytes: 284675616,
);

/// True in a study build (`--dart-define=SW9_BUNDLED_MODEL=true`): the file is
/// inside the APK, so a session does not depend on Wi-Fi. Other builds download
/// it when the user taps Set up.
const bundledModel = bool.fromEnvironment('SW9_BUNDLED_MODEL');
