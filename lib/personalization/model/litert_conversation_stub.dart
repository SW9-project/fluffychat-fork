// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// The model only runs where LiteRT-LM runs natively.
Future<({String raw, SessionMetrics metrics})> runLiteRtConversation(
  InferenceModel model, {
  required String toolsJson,
  required String? messagesJson,
  required String messageJson,
  required int maxOutputTokens,
}) => throw UnsupportedError('LiteRT-LM is not available on this platform');
