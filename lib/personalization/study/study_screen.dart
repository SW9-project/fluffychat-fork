// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../personalization_l10n.dart';
import 'study_events.dart';
import 'study_log.dart';
import 'study_settings.dart';

/// Holding [child] for three seconds opens the hidden study screen. The
/// Accessibility page wraps its title in it. A normal long press is too easy
/// to trigger by accident.
class StudyEntry extends StatelessWidget {
  static const holdDuration = Duration(seconds: 3);

  final Widget child;

  const StudyEntry({required this.child, super.key});

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: holdDuration),
            (recognizer) => recognizer.onLongPress = () =>
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const StudyScreen()),
                ),
          ),
    },
    child: child,
  );
}

/// Saves [bytes] as a file named [name] and returns where, or null when the
/// researcher cancelled.
typedef SaveStudyLog = Future<String?> Function(String name, Uint8List bytes);

/// The hidden study screen (Phase 5), opened by holding the title of the
/// Accessibility page. The researcher sets the condition and the participant
/// code, turns logging on after the participant agreed, and saves the log as
/// a file with the participant present. Nothing is uploaded.
class StudyScreen extends StatefulWidget {
  /// By default the system save dialog.
  final SaveStudyLog? save;

  /// Only for tests. By default the app-wide instances.
  final StudySettings? settings;
  final StudyLog? log;

  const StudyScreen({this.save, this.settings, this.log, super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  static const _shownEvents = 20;

  late final StudySettings _settings =
      widget.settings ?? StudySettings.instance;
  late final StudyLog _log = widget.log ?? StudyLog.instance;
  late final TextEditingController _participant = TextEditingController(
    text: _settings.value.participant,
  );
  List<String> _lines = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _participant.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final lines = await _log.lines();
    if (mounted) setState(() => _lines = lines);
  }

  Future<bool> _confirm(String title, String info, String action) async {
    final l10n = PersonalizationL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(info),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('study_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _setCondition(StudyCondition condition) async {
    final current = _settings.value.condition;
    if (condition == current) return;
    final l10n = PersonalizationL10n.of(context);
    if (!await _confirm(
      l10n.studyChangeCondition,
      l10n.studyChangeConditionInfo,
      l10n.studyChange,
    )) {
      return;
    }
    _log.record(ConditionChanged(current, condition));
    await _settings.update(_settings.value.copyWith(condition: condition));
    await _reload();
  }

  Future<void> _setLogging(bool logging) async {
    final preferences = _settings.value;
    if (!logging) _log.record(const LoggingStopped());
    await _settings.update(preferences.copyWith(logging: logging));
    if (logging) _log.record(LoggingStarted(preferences.condition));
    await _reload();
  }

  /// Saves the log as a file. With [clear], the log is cleared once the file
  /// is saved, for the next participant.
  Future<void> _export({bool clear = false}) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (clear) {
      final personalization = PersonalizationL10n.of(context);
      if (!await _confirm(
        personalization.studySaveAndClearConfirm,
        personalization.studySaveAndClearInfo,
        personalization.studySaveAndClear,
      )) {
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final preferences = _settings.value;
      final bytes = await _log.export({
        'exported_at': now.toUtc().toIso8601String(),
        'participant': preferences.participant,
        'condition': preferences.condition.id,
        'logging': preferences.logging,
        ...await _deviceInfo(),
      });
      final save =
          widget.save ??
          (name, bytes) async => (await FilePicker.saveFile(
            fileName: name,
            bytes: bytes,
          ))?.toString();
      final path = await save(_fileName(preferences.participant, now), bytes);
      if (path == null) return;
      final events = _lines.length;
      if (clear) {
        await _log.clear();
        _log.record(LogCleared(events, saved: true));
      } else {
        _log.record(LogExported(events));
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.fileHasBeenSavedAt(path)),
          showCloseIcon: true,
        ),
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// For a participant who withdraws: deletes the log without saving it.
  Future<void> _delete() async {
    final l10n = PersonalizationL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm(
      l10n.studyDeleteConfirm,
      l10n.studyDeleteInfo,
      l10n.studyDeleteAction,
    )) {
      return;
    }
    final events = _lines.length;
    await _log.clear();
    _log.record(LogCleared(events, saved: false));
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.studyCleared), showCloseIcon: true),
    );
    await _reload();
  }

  static String _fileName(String participant, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final code = participant.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
    return 'study-log-${code.isEmpty ? 'participant' : code}-$stamp.jsonl';
  }

  /// The app version and device, so latency in the log can be read against
  /// the hardware.
  static Future<Map<String, Object?>> _deviceInfo() async {
    final info = <String, Object?>{};
    try {
      final package = await PackageInfo.fromPlatform();
      info['app_version'] = '${package.version}+${package.buildNumber}';
      if (PlatformInfos.isAndroid) {
        final android = await DeviceInfoPlugin().androidInfo;
        info['device'] = '${android.manufacturer} ${android.model}';
        info['android'] = android.version.release;
        info['sdk'] = android.version.sdkInt;
      }
    } catch (e, s) {
      Logs().w('Unable to read the device info for the study log', e, s);
    }
    return info;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final sectionStyle = TextStyle(
      color: theme.colorScheme.secondary,
      fontWeight: FontWeight.bold,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.studyTitle)),
      backgroundColor: theme.colorScheme.surface,
      body: ValueListenableBuilder<StudyPreferences>(
        valueListenable: _settings,
        builder: (context, preferences, _) => MaxWidthBody(
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              ListTile(title: Text(l10n.studyCondition, style: sectionStyle)),
              RadioGroup<StudyCondition>(
                groupValue: preferences.condition,
                onChanged: (condition) {
                  if (condition != null) _setCondition(condition);
                },
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    for (final condition in StudyCondition.values)
                      RadioListTile<StudyCondition>.adaptive(
                        key: Key('study_condition_${condition.id}'),
                        value: condition,
                        title: Text(l10n.conditionTitles[condition]!),
                        subtitle: Text(l10n.conditionDescriptions[condition]!),
                      ),
                  ],
                ),
              ),
              const Divider(),
              SwitchListTile.adaptive(
                key: const Key('study_logging'),
                value: preferences.logging,
                onChanged: _setLogging,
                title: Text(l10n.studyLogging),
                subtitle: Text(l10n.studyLoggingDescription),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  key: const Key('study_participant'),
                  controller: _participant,
                  decoration: InputDecoration(
                    labelText: l10n.studyParticipant,
                    hintText: 'P07',
                  ),
                  onChanged: (participant) => _settings.update(
                    _settings.value.copyWith(participant: participant.trim()),
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Text(
                      l10n.studyEvents(_lines.length),
                      style: theme.textTheme.titleMedium,
                    ),
                    FilledButton.icon(
                      key: const Key('study_save'),
                      onPressed: _saving || _lines.isEmpty ? null : _export,
                      icon: const Icon(Icons.save_alt),
                      label: Text(l10n.studySave),
                    ),
                    OutlinedButton.icon(
                      key: const Key('study_save_and_clear'),
                      onPressed: _saving || _lines.isEmpty
                          ? null
                          : () => _export(clear: true),
                      icon: const Icon(Icons.save_as_outlined),
                      label: Text(l10n.studySaveAndClear),
                    ),
                    TextButton.icon(
                      key: const Key('study_delete'),
                      onPressed: _saving || _lines.isEmpty ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.studyDelete),
                    ),
                  ],
                ),
              ),
              ListTile(title: Text(l10n.studyLatest, style: sectionStyle)),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(l10n.studyNoEvents),
                ),
              for (final line in _lines.reversed.take(_shownEvents))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: SelectableText(
                    line,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
