// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which version of the feature the participant uses, so the same build can
/// run every study condition.
enum StudyCondition {
  /// The Assist tab with the on-device model. Also the normal app.
  assist('assist'),

  /// Manual settings only: the Assist tab is off and no model is created.
  manualOnly('manual_only');

  final String id;

  const StudyCondition(this.id);

  static StudyCondition fromId(String? id) =>
      values.firstWhere((c) => c.id == id, orElse: () => assist);
}

@immutable
class StudyPreferences {
  final StudyCondition condition;

  /// Whether study events are recorded. Off by default: the researcher turns
  /// it on after the participant agreed.
  final bool logging;

  /// The researcher's code for the participant, such as "P07". It only goes
  /// into the header of an exported log.
  final String participant;

  const StudyPreferences({
    this.condition = StudyCondition.assist,
    this.logging = false,
    this.participant = '',
  });

  StudyPreferences copyWith({
    StudyCondition? condition,
    bool? logging,
    String? participant,
  }) => StudyPreferences(
    condition: condition ?? this.condition,
    logging: logging ?? this.logging,
    participant: participant ?? this.participant,
  );
}

/// The hidden study switches (Phase 5). Stored on this device only.
class StudySettings extends ValueNotifier<StudyPreferences> {
  static const _condition = 'personalization.study.condition';
  static const _logging = 'personalization.study.logging';
  static const _participant = 'personalization.study.participant';

  final SharedPreferences _store;

  StudySettings(this._store)
    : super(
        StudyPreferences(
          condition: StudyCondition.fromId(_store.getString(_condition)),
          logging: _store.getBool(_logging) ?? false,
          participant: _store.getString(_participant) ?? '',
        ),
      );

  static StudySettings? _instance;

  /// The app-wide instance, backed by [AppSettings.store].
  static StudySettings get instance =>
      _instance ??= StudySettings(AppSettings.store);

  @visibleForTesting
  static set instance(StudySettings settings) => _instance = settings;

  Future<void> update(StudyPreferences preferences) async {
    value = preferences;
    await _store.setString(_condition, preferences.condition.id);
    await _store.setBool(_logging, preferences.logging);
    await _store.setString(_participant, preferences.participant);
  }
}
