// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import 'study_events.dart';
import 'study_settings.dart';

/// Keeps the lines of the study log. The app uses [FileStudyLogStorage].
abstract interface class StudyLogStorage {
  /// Adds [line] at the end. Lines are never changed or removed.
  Future<void> append(String line);

  /// All lines, oldest first.
  Future<List<String>> readLines();
}

/// A file in the app's private support directory.
class FileStudyLogStorage implements StudyLogStorage {
  static const fileName = 'study_log.jsonl';

  final Future<File> Function() _file;

  FileStudyLogStorage([Future<File> Function()? file])
    : _file = file ?? _defaultFile;

  static Future<File> _defaultFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/personalization/$fileName');
  }

  @override
  Future<void> append(String line) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  @override
  Future<List<String>> readLines() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    return [
      for (final line in await file.readAsLines())
        if (line.isNotEmpty) line,
    ];
  }
}

/// The local study event log (Phase 5): one JSON object per line.
///
/// Nothing is recorded while logging is off in [StudySettings], which is the
/// default: the researcher turns it on after the participant agreed. The app
/// only appends to the log and never uploads it. The researcher saves it as
/// a file from the study screen, with the participant present.
class StudyLog {
  /// Null for the log that records nothing.
  final StudySettings? settings;
  final StudyLogStorage? _storage;
  final DateTime Function() _clock;

  /// Writes run one after another, so lines keep the order of [record].
  Future<void> _writes = Future.value();

  StudyLog({
    required StudySettings this.settings,
    required StudyLogStorage storage,
    DateTime Function() clock = DateTime.now,
  }) : _storage = storage,
       _clock = clock;

  StudyLog._disabled()
    : settings = null,
      _storage = null,
      _clock = DateTime.now;

  static final _off = StudyLog._disabled();
  static StudyLog? _instance;

  /// The app-wide log. It records nothing until [start] ran.
  static StudyLog get instance => _instance ?? _off;

  @visibleForTesting
  static set instance(StudyLog? log) => _instance = log;

  /// Starts the app-wide log, backed by [StudySettings.instance] and a file.
  /// Safe to call again.
  static void start() => _instance ??= StudyLog(
    settings: StudySettings.instance,
    storage: FileStudyLogStorage(),
  );

  bool get isRecording => !kIsWeb && (settings?.value.logging ?? false);

  /// Appends [event] when logging is on.
  void record(StudyEvent event) {
    final storage = _storage;
    if (storage == null || !isRecording) return;
    final line = jsonEncode({
      't': _clock().toUtc().toIso8601String(),
      'type': event.type,
      ...event.data,
    });
    _writes = _writes.then((_) async {
      try {
        await storage.append(line);
      } catch (e, s) {
        Logs().w('Unable to write the study log', e, s);
      }
    });
  }

  /// Completes when everything recorded so far is written.
  Future<void> get flushed => _writes;

  /// The recorded lines, oldest first.
  Future<List<String>> lines() async {
    final storage = _storage;
    if (storage == null) return const [];
    await _writes;
    return storage.readLines();
  }

  /// The log as a file: a [header] line about the study setup and the
  /// device, then every recorded event.
  Future<Uint8List> export(Map<String, Object?> header) async {
    final buffer = StringBuffer()
      ..writeln(jsonEncode({'type': 'header', ...header}));
    for (final line in await lines()) {
      buffer.writeln(line);
    }
    return utf8.encode(buffer.toString());
  }
}
