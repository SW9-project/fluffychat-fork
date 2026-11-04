// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _package = ['FunctionGemma (SW9 model)'];

/// Puts the model's notice and a copy of the Gemma Terms of Use on the app's
/// licenses screen: anyone who gets the model must get both. The files are read
/// only when someone opens that screen.
void registerModelLicenses() => LicenseRegistry.addLicense(() async* {
  for (final asset in const [
    'assets/models/NOTICE.txt',
    'assets/models/GEMMA_TERMS.txt',
  ]) {
    yield LicenseEntryWithLineBreaks(
      _package,
      await rootBundle.loadString(asset),
    );
  }
});
