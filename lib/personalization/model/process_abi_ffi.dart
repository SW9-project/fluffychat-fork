// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';

/// Whether this app process runs as Android arm64. The process ABI matters,
/// not the device's: an x86_64 build on an emulator that can translate arm64
/// still cannot load arm64 libraries.
bool get isAndroidArm64Process => Abi.current() == Abi.androidArm64;
