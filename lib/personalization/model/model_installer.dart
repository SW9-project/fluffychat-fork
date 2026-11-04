// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_release.dart';
import 'settings_intent_model.dart';

/// What installing needs from the plugin, so the steps around it can be tested.
abstract class ModelFiles {
  /// Whether the plugin has a record of [fileName]. It says nothing about the
  /// file's checksum.
  Future<bool> isInstalled(String fileName);

  /// Downloads [file], or copies it from the assets in a study build. A file
  /// that is already installed from the same source is kept.
  Future<void> install(
    ModelRelease file,
    void Function(int percent) onProgress,
  );

  Future<String> pathOf(String fileName);

  /// Deletes the file and the plugin's record of it.
  Future<void> remove(String fileName);

  /// The names of everything the plugin has installed.
  Future<List<String>> installed();
}

class ModelChecksumException implements Exception {
  final String fileName;
  final String expected;
  final String actual;

  const ModelChecksumException(this.fileName, this.expected, this.actual);

  @override
  String toString() =>
      'ModelChecksumException: $fileName has sha256 $actual, expected $expected';
}

/// The SHA-256 of the file at [path], in lowercase hex. Runs apart from the UI:
/// the model file is hundreds of megabytes.
Future<String> sha256OfFile(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);

/// Gets one model file onto the phone, and only reports it ready once its
/// checksum matched. Nothing opens the file before that, because the model is
/// only loaded when the status is ready.
///
/// The plugin has no checksum check of its own. A match is remembered, so the
/// file is hashed once per install and not each time the Assist tab opens. An
/// app killed before the check gets no match, and the next Set up checks it.
///
/// One installer lives as long as the app, unlike the model object, which goes
/// when the Assist tab closes: a download takes minutes, and leaving the tab
/// must neither lose its progress nor start a second one.
class ModelInstaller {
  static const verifiedKey = 'personalization.model_verified_sha256';

  final ModelRelease file;
  final ModelFiles files;

  final ValueNotifier<ModelStatus> status = ValueNotifier(
    const ModelStatus(ModelState.notPrepared),
  );
  Future<void>? _running;

  ModelInstaller({required this.file, required this.files});

  /// Reads the state from the phone, unless an install is running, which
  /// reports its own.
  Future<void> refresh() async {
    if (_running != null) return;
    final verified = await _isVerified();
    if (_running != null) return;
    status.value = ModelStatus(
      verified ? ModelState.ready : ModelState.notPrepared,
    );
  }

  /// Downloads and checks the file. Joins an install that is already running.
  /// The outcome is in [status]: this does not throw.
  Future<void> install() {
    if (status.value.state == ModelState.ready) return Future.value();
    return _running ??= _install().whenComplete(() => _running = null);
  }

  Future<bool> _isVerified() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(verifiedKey) != file.sha256) return false;
    if (!await files.isInstalled(file.fileName)) return false;
    final installed = File(await files.pathOf(file.fileName));
    return await installed.exists() &&
        await installed.length() == file.sizeBytes;
  }

  Future<void> _install() async {
    status.value = const ModelStatus(ModelState.preparing, progress: 0);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(verifiedKey);
      await files.install(
        file,
        (percent) =>
            status.value = ModelStatus(ModelState.preparing, progress: percent),
      );
      status.value = const ModelStatus(ModelState.verifying);
      final actual = await sha256OfFile(await files.pathOf(file.fileName));
      if (actual != file.sha256) {
        await files.remove(file.fileName);
        throw ModelChecksumException(file.fileName, file.sha256, actual);
      }
      await preferences.setString(verifiedKey, file.sha256);
      await _removeEarlierFiles();
      status.value = const ModelStatus(ModelState.ready);
    } catch (e, s) {
      Logs().e('Unable to install the on-device model', e, s);
      status.value = ModelStatus(ModelState.failed, error: e);
    }
  }

  /// A new model has a new file name, so the plugin would keep the old file
  /// next to it, hundreds of megabytes that nothing reads any more. Failing here
  /// never fails the install.
  Future<void> _removeEarlierFiles() async {
    try {
      for (final name in await files.installed()) {
        if (name != file.fileName &&
            name.startsWith('functiongemma-') &&
            name.endsWith('.litertlm')) {
          await files.remove(name);
        }
      }
    } catch (e, s) {
      Logs().w('Unable to remove an earlier model file', e, s);
    }
  }
}
