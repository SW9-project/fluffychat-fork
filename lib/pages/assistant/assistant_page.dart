// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:material_ui/material_ui.dart';

class AssistantPage extends StatelessWidget {
  const AssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MainNavigationBarInsets(
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).assistant),
          automaticallyImplyLeading: false,
        ),
        body: const SizedBox.expand(),
      ),
    );
  }
}
