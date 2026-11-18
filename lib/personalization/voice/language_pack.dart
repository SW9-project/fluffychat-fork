// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

enum LanguagePackState {
  /// The on-device recogniser can recognise the language now.
  installed,

  /// The system is downloading the pack.
  downloading,

  /// The language is supported on the device, but its pack is missing.
  needsDownload,

  /// The on-device recogniser cannot recognise this language.
  unsupported,

  /// The device cannot tell, for example below Android 13. The first
  /// recording finds out.
  unknown,
}

/// The language pack of the phone's on-device speech recogniser.
abstract class LanguagePackService {
  Future<LanguagePackState> check(String localeId);

  /// Asks the system to download the pack. True when a download was started,
  /// scheduled or the pack is already there.
  Future<bool> download(String localeId);
}

/// [LanguagePackService] through `SpeechLanguagePack.kt` in the Android
/// runner. A download is fetched by the system's recognition service; the
/// app sends no audio or text.
class AndroidLanguagePack implements LanguagePackService {
  static const _channel = MethodChannel(
    'chat.fluffy.fluffychat/speech_language_pack',
  );

  const AndroidLanguagePack();

  @override
  Future<LanguagePackState> check(String localeId) async {
    final answer = await _channel.invokeMethod<String>('check', {
      'locale': localeId,
    });
    Logs().i('Voice input: $localeId language pack is $answer');
    return LanguagePackState.values.asNameMap()[answer] ??
        LanguagePackState.unknown;
  }

  @override
  Future<bool> download(String localeId) async {
    final answer = await _channel.invokeMethod<String>('download', {
      'locale': localeId,
    });
    Logs().i('Voice input: $localeId language pack download: $answer');
    return const {
      'installed',
      'downloading',
      'scheduled',
      'requested',
    }.contains(answer);
  }
}
