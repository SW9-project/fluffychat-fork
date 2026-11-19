// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:matrix/matrix.dart';

/// Reads text aloud with the device's own speech engine.
///
/// Nothing leaves the device: on Android only voices that are installed and
/// work offline are used, and iOS speech synthesis always runs on the device.
/// When no such voice exists for [AppConfig.textToSpeechLanguage], nothing is
/// spoken.
///
/// Only one text is spoken at a time. Starting new speech stops the old one.
class TextToSpeech {
  TextToSpeech._();

  static final TextToSpeech instance = TextToSpeech._();

  /// Android and iOS only for now.
  static bool get isSupported => PlatformInfos.isMobile;

  FlutterTts? _tts;
  Future<bool>? _setUp;

  /// Goes up on every call to [speak] and [stop], so a call that was waiting
  /// on the engine can tell that a newer one came in.
  int _generation = 0;

  /// Stops any current speech, then speaks [text]. Returns whether speech
  /// started.
  Future<bool> speak(String text) async {
    if (!isSupported) return false;
    text = text.trim();
    if (text.isEmpty) return false;

    final generation = ++_generation;
    final tts = _tts ??= FlutterTts();
    try {
      await tts.stop();
      final ready = await (_setUp ??= _setUpEngine(tts));
      // Try again next time, a voice may have been installed meanwhile.
      if (!ready) _setUp = null;
      if (!ready || generation != _generation) return false;
      return await tts.speak(text) == 1;
    } catch (e, s) {
      _setUp = null;
      Logs().w('Text to speech failed', e, s);
      return false;
    }
  }

  /// Stops any current speech.
  Future<void> stop() async {
    _generation++;
    final tts = _tts;
    if (tts == null) return;
    try {
      await tts.stop();
    } catch (e, s) {
      Logs().w('Text to speech: stop failed', e, s);
    }
  }

  static Future<bool> _setUpEngine(FlutterTts tts) async {
    const language = AppConfig.textToSpeechLanguage;
    if (!PlatformInfos.isAndroid) {
      return await tts.setLanguage(language) == 1;
    }
    final voice = _pickOfflineVoice(await tts.getVoices, language);
    if (voice == null) {
      Logs().w('Text to speech: no offline voice for $language');
      return false;
    }
    return await tts.setVoice(voice) == 1;
  }

  /// Picks an installed voice that needs no network, preferring the exact
  /// locale over another region of the same language.
  static Map<String, String>? _pickOfflineVoice(
    Object? voices,
    String language,
  ) {
    if (voices is! List) return null;
    final wanted = _normalizeTag(language);
    final wantedLanguage = wanted.split('-').first;
    Map<String, String>? sameLanguage;
    for (final voice in voices) {
      if (voice is! Map) continue;
      final name = voice['name'];
      final locale = voice['locale'];
      if (name is! String || locale is! String) continue;
      if (voice['network_required'] != '0') continue;
      final features = voice['features'];
      // Speaking with a voice that is not installed would download it.
      if (features is String && features.split('\t').contains('notInstalled')) {
        continue;
      }
      final tag = _normalizeTag(locale);
      final picked = {'name': name, 'locale': locale};
      if (tag == wanted) return picked;
      if (sameLanguage == null && tag.split('-').first == wantedLanguage) {
        sameLanguage = picked;
      }
    }
    return sameLanguage;
  }

  static String _normalizeTag(String tag) =>
      tag.replaceAll('_', '-').toLowerCase();
}
