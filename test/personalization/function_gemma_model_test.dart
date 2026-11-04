// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/model_installer.dart';
import 'package:fluffychat/personalization/model/model_release.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _content = 'the model file';
final _file = ModelRelease(
  url: 'https://example.test/download/pilot1/functiongemma-test.litertlm',
  sha256: sha256.convert(utf8.encode(_content)).toString(),
  sizeBytes: _content.length,
);

/// The plugin, with its files in a real folder.
class FakeFiles implements ModelFiles {
  final Directory folder;

  /// What a download writes.
  String content = _content;

  /// Holds a download until completed.
  Completer<void>? gate;
  Object? failWith;

  /// Set when the file cannot be reached.
  Object? unreachable;

  int installs = 0;
  final Set<String> names = {};
  final List<String> failToRemove = [];
  int leftoverRemovals = 0;
  bool failToRemoveLeftovers = false;

  FakeFiles(this.folder);

  /// Puts a file there as an earlier run would have left it.
  void leave(String name, {String content = _content}) {
    File('${folder.path}/$name').writeAsStringSync(content);
    names.add(name);
  }

  @override
  Future<bool> isInstalled(String fileName) async => names.contains(fileName);

  @override
  Future<void> ensureReachable(ModelRelease file) async {
    final failure = unreachable;
    if (failure != null) throw failure;
  }

  @override
  Future<void> install(
    ModelRelease file,
    void Function(int percent) onProgress,
  ) async {
    installs++;
    onProgress(10);
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
    // As the plugin, which skips a file that is already installed.
    if (!names.contains(file.fileName)) leave(file.fileName, content: content);
    onProgress(100);
  }

  @override
  Future<String> pathOf(String fileName) async => '${folder.path}/$fileName';

  @override
  Future<void> remove(String fileName) async {
    if (failToRemove.contains(fileName)) throw StateError('cannot remove');
    File('${folder.path}/$fileName').deleteSync();
    names.remove(fileName);
  }

  @override
  Future<List<String>> installed() async => names.toList();

  @override
  Future<void> removeLeftovers() async {
    leftoverRemovals++;
    if (failToRemoveLeftovers) throw StateError('cannot remove');
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  late Directory folder;
  late FakeFiles files;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FunctionGemmaModel.forgetInstallers();
    folder = Directory.systemTemp.createTempSync('model_test');
    files = FakeFiles(folder);
  });

  tearDown(() => folder.deleteSync(recursive: true));

  FunctionGemmaModel create({bool supported = true}) => FunctionGemmaModel(
    file: _file,
    files: files,
    supported: () async => supported,
  );

  /// A model that is past its first check.
  Future<FunctionGemmaModel> opened() async {
    final model = create();
    await _until(() => model.status.value.state != ModelState.unavailable);
    return model;
  }

  Future<String?> verified() async => (await SharedPreferences.getInstance())
      .getString(ModelInstaller.verifiedKey);

  test('sha256OfFile hashes the whole file', () async {
    final file = File('${folder.path}/abc')..writeAsStringSync('abc');
    expect(
      await sha256OfFile(file.path),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  group('without a tap on Set up', () {
    test('nothing downloads when the tab opens', () async {
      final model = await opened();
      expect(model.status.value.state, ModelState.notPrepared);
      expect(files.installs, 0);
      model.dispose();
    });

    test('a request fails rather than starting a download', () async {
      final model = await opened();
      await expectLater(model.propose('hello', const []), throwsStateError);
      expect(files.installs, 0);
      model.dispose();
    });
  });

  test('a phone that cannot run the model stays unavailable', () async {
    final model = create(supported: false);
    await model.prepare();
    expect(model.status.value.state, ModelState.unavailable);
    expect(files.installs, 0);
    model.dispose();
  });

  test('Set up: progress, then the check, then ready', () async {
    final model = await opened();
    final seen = <ModelState>[];
    final progress = <int?>[];
    model.status.addListener(() {
      seen.add(model.status.value.state);
      progress.add(model.status.value.progress);
    });

    await model.prepare();

    expect(seen, [
      ModelState.preparing,
      ModelState.preparing,
      ModelState.preparing,
      ModelState.verifying,
      ModelState.ready,
    ]);
    expect(progress.take(3), [0, 10, 100]);
    expect(await verified(), _file.sha256);
    model.dispose();
  });

  group('a file with the wrong checksum', () {
    setUp(() => files.content = 'the wrong file');

    test('is removed, and the model is not ready', () async {
      final model = await opened();
      await model.prepare();

      expect(model.status.value.state, ModelState.failed);
      expect(model.status.value.error, isA<ModelChecksumException>());
      expect(files.names, isEmpty);
      expect(File(await files.pathOf(_file.fileName)).existsSync(), isFalse);
      expect(await verified(), isNull);
      await expectLater(model.propose('hello', const []), throwsStateError);
      model.dispose();
    });

    test('can be downloaded again', () async {
      final model = await opened();
      await model.prepare();
      files.content = _content;
      await model.prepare();

      expect(files.installs, 2);
      expect(model.status.value.state, ModelState.ready);
      model.dispose();
    });

    test('that cannot be removed is still not ready', () async {
      files.failToRemove.add(_file.fileName);
      final model = await opened();
      await model.prepare();
      expect(model.status.value.state, ModelState.failed);
      expect(await verified(), isNull);
      model.dispose();

      FunctionGemmaModel.forgetInstallers();
      final reopened = await opened();
      expect(reopened.status.value.state, ModelState.notPrepared);
      reopened.dispose();
    });
  });

  test('offline, Set up fails at once and starts no download', () async {
    files.unreachable = const SocketException('no network');
    final model = await opened();
    await model.prepare();

    expect(model.status.value.state, ModelState.failed);
    expect(model.status.value.error, isA<SocketException>());
    expect(files.installs, 0);

    files.unreachable = null;
    await model.prepare();
    expect(files.installs, 1);
    expect(model.status.value.state, ModelState.ready);
    model.dispose();
  });

  group('dropped downloads', () {
    test('their files go before each attempt and after a good one', () async {
      files.failWith = const SocketException('no network');
      final model = await opened();
      await model.prepare();
      expect(files.leftoverRemovals, 1);

      files.failWith = null;
      await model.prepare();
      expect(files.leftoverRemovals, 3);
      expect(model.status.value.state, ModelState.ready);
      model.dispose();
    });

    test('files that cannot be removed do not fail the install', () async {
      files.failToRemoveLeftovers = true;
      final model = await opened();
      await model.prepare();
      expect(model.status.value.state, ModelState.ready);
      model.dispose();
    });
  });

  test('a failed download can be tried again', () async {
    files.failWith = const SocketException('no network');
    final model = await opened();
    await model.prepare();
    expect(model.status.value.state, ModelState.failed);
    expect(model.status.value.error, isA<SocketException>());

    files.failWith = null;
    await model.prepare();
    expect(model.status.value.state, ModelState.ready);
    model.dispose();
  });

  test(
    'leaving the tab keeps the download, and coming back joins it',
    () async {
      files.gate = Completer();
      final first = await opened();
      final firstDone = first.prepare();
      await _until(() => first.status.value.progress == 10);

      first.dispose();
      final second = await opened();
      expect(second.status.value.state, ModelState.preparing);
      expect(second.status.value.progress, 10);

      final secondDone = second.prepare();
      expect(files.installs, 1);

      files.gate!.complete();
      await Future.wait([firstDone, secondDone]);
      expect(files.installs, 1);
      expect(second.status.value.state, ModelState.ready);
      second.dispose();
    },
  );

  test('a tab that closes before its first check does no harm', () async {
    final model = create();
    model.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(files.installs, 0);
  });

  group('after an app restart', () {
    Future<void> setUpOnce() async {
      final model = await opened();
      await model.prepare();
      expect(model.status.value.state, ModelState.ready);
      model.dispose();
      FunctionGemmaModel.forgetInstallers();
    }

    test('a checked file is ready, with no new install', () async {
      await setUpOnce();
      final model = await opened();
      expect(model.status.value.state, ModelState.ready);
      expect(files.installs, 1);
      model.dispose();
    });

    test('a file installed but never checked is not ready', () async {
      // The app was killed between the download and the check.
      files.leave(_file.fileName);
      final model = await opened();
      expect(model.status.value.state, ModelState.notPrepared);

      await model.prepare();
      expect(model.status.value.state, ModelState.ready);
      model.dispose();
    });

    test('a bad file left by a killed app does not pass the check', () async {
      files.leave(_file.fileName, content: 'cut sho');
      final model = await opened();
      await model.prepare();
      expect(model.status.value.state, ModelState.failed);
      expect(files.names, isEmpty);
      model.dispose();
    });

    test('a file of the wrong size is not ready', () async {
      await setUpOnce();
      File(await files.pathOf(_file.fileName)).writeAsStringSync('cut');
      final model = await opened();
      expect(model.status.value.state, ModelState.notPrepared);
      model.dispose();
    });

    test('a file that is gone is not ready', () async {
      await setUpOnce();
      File(await files.pathOf(_file.fileName)).deleteSync();
      final model = await opened();
      expect(model.status.value.state, ModelState.notPrepared);
      model.dispose();
    });

    test('a match for an earlier model does not count', () async {
      await setUpOnce();
      SharedPreferences.setMockInitialValues({
        ModelInstaller.verifiedKey: 'an earlier checksum',
      });
      final model = await opened();
      expect(model.status.value.state, ModelState.notPrepared);
      model.dispose();
    });
  });

  group('earlier model files', () {
    test('go once the new one has passed its check', () async {
      files.leave('functiongemma-270M-it.litertlm');
      files.leave('other-model.litertlm');
      files.leave('functiongemma-notes.txt');

      final model = await opened();
      await model.prepare();

      expect(files.names, {
        _file.fileName,
        'other-model.litertlm',
        'functiongemma-notes.txt',
      });
      model.dispose();
    });

    test('stay when the new one fails its check', () async {
      files
        ..leave('functiongemma-270M-it.litertlm')
        ..content = 'the wrong file';
      final model = await opened();
      await model.prepare();
      expect(files.names, {'functiongemma-270M-it.litertlm'});
      model.dispose();
    });

    test('that cannot be removed do not fail the install', () async {
      files
        ..leave('functiongemma-270M-it.litertlm')
        ..failToRemove.add('functiongemma-270M-it.litertlm');
      final model = await opened();
      await model.prepare();
      expect(model.status.value.state, ModelState.ready);
      model.dispose();
    });
  });
}
