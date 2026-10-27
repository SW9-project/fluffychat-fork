// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Whether this app process runs as Android arm64. Always false where
/// `dart:ffi` is missing, such as on the web.
bool get isArm64Process => false;
