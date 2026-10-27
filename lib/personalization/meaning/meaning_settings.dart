// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../study/study_events.dart';
import '../study/study_log.dart';

@immutable
class MeaningPreferences {
  /// Sender side: propose meaning for my messages.
  final bool annotateOutgoing;

  /// Receiver side: how incoming meaning is shown.
  final bool showIntent;
  final bool showUrgency;
  final bool highlightTimes;

  const MeaningPreferences({
    this.annotateOutgoing = true,
    this.showIntent = true,
    this.showUrgency = true,
    this.highlightTimes = true,
  });

  MeaningPreferences copyWith({
    bool? annotateOutgoing,
    bool? showIntent,
    bool? showUrgency,
    bool? highlightTimes,
  }) => MeaningPreferences(
    annotateOutgoing: annotateOutgoing ?? this.annotateOutgoing,
    showIntent: showIntent ?? this.showIntent,
    showUrgency: showUrgency ?? this.showUrgency,
    highlightTimes: highlightTimes ?? this.highlightTimes,
  );
}

/// The user's message meaning preferences. Stored on this device only, like
/// the accessibility settings.
class MeaningSettings extends ValueNotifier<MeaningPreferences> {
  static const _annotate = 'personalization.meaning.annotate_outgoing';
  static const _intent = 'personalization.meaning.show_intent';
  static const _urgency = 'personalization.meaning.show_urgency';
  static const _times = 'personalization.meaning.highlight_times';

  final SharedPreferences _store;

  MeaningSettings(this._store)
    : super(
        MeaningPreferences(
          annotateOutgoing: _store.getBool(_annotate) ?? true,
          showIntent: _store.getBool(_intent) ?? true,
          showUrgency: _store.getBool(_urgency) ?? true,
          highlightTimes: _store.getBool(_times) ?? true,
        ),
      );

  static MeaningSettings? _instance;

  /// The app-wide instance, backed by [AppSettings.store].
  static MeaningSettings get instance =>
      _instance ??= MeaningSettings(AppSettings.store);

  @visibleForTesting
  static set instance(MeaningSettings settings) => _instance = settings;

  Future<void> update(MeaningPreferences preferences) async {
    value = preferences;
    StudyLog.instance.record(MeaningSettingsChanged(preferences));
    await _store.setBool(_annotate, preferences.annotateOutgoing);
    await _store.setBool(_intent, preferences.showIntent);
    await _store.setBool(_urgency, preferences.showUrgency);
    await _store.setBool(_times, preferences.highlightTimes);
  }
}
