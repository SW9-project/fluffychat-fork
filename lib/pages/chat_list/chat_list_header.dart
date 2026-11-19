// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/appearance_l10n.dart';
import 'package:fluffychat/personalization/simplified_interface.dart';
import 'package:fluffychat/personalization/simplified_interface_l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:fluffychat/widgets/liquid_glass.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';

class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final isColumnMode = FluffyThemes.isColumnMode(context);
    if (theme.cupertinoStyle) return _CupertinoSearchBar(controller);

    return SliverAppBar(
      floating: true,
      toolbarHeight: 72,
      pinned: isColumnMode,
      scrolledUnderElevation: 0,
      shape: isColumnMode
          ? Border(bottom: BorderSide(color: theme.dividerColor, width: 1))
          : null,
      backgroundColor: isColumnMode
          ? theme.colorScheme.surface.withAlpha(240)
          : Colors.transparent,
      automaticallyImplyLeading: false,
      title: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, snapshot) {
          final status =
              client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final hide =
              client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;
          return TextField(
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: (text) =>
                controller.onSearchEnter(text, globalSearch: globalSearch),
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(99),
              ),
              hintText: hide
                  ? (SimplifiedInterfaceScope.enabledOf(context)
                        ? SimplifiedInterfaceL10n.of(context).search
                        : L10n.of(context).searchChatsRooms)
                  : status.calcLocalizedString(context),
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),

              prefixIcon: hide
                  ? controller.isSearchMode
                        ? IconButton(
                            tooltip: L10n.of(context).cancel,
                            icon: const Icon(Icons.close_outlined),
                            onPressed: controller.cancelSearch,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : isColumnMode ||
                              (controller.spaces.isEmpty &&
                                  !AppSettings.displayNavigationRail.value)
                        ? AccessibilityIconButtons(
                            button: AccessibleButton.search,
                            child: IconButton(
                              tooltip: L10n.of(context).search,
                              onPressed: controller.startSearch,
                              icon: Icon(
                                Icons.search_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : AccessibilityIconButtons(
                            button: AccessibleButton.menu,
                            child: IconButton(
                              tooltip: L10n.of(context).displayNavigationRail,
                              onPressed: controller.openNavrail,
                              color: theme.colorScheme.onSurfaceVariant,
                              icon: LabeledIcon(
                                icon: const Icon(Icons.menu),
                                label: AppearanceL10n.of(context).labelMenu,
                              ),
                            ),
                          )
                  : SizedBox(
                      width: 8,
                      height: 8,
                      child: Center(
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          value: status.progress,
                        ),
                      ),
                    ),
              suffixIcon: controller.isSearchMode && globalSearch
                  ? controller.isSearching
                        ? const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 10.0,
                              horizontal: 12,
                            ),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: controller.setServer,
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(99),
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(
                              controller.searchServer ??
                                  Matrix.of(context).client.homeserver!.host,
                              maxLines: 2,
                            ),
                          )
                  : SizedBox(width: 0, child: ClientChooserButton(controller)),
            ),
          );
        },
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

/// The search field of iOS with the Cancel button of UISearchController.
class _CupertinoSearchBar extends StatelessWidget {
  final ChatListController controller;

  const _CupertinoSearchBar(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return SliverAppBar(
      // The large title above it is the primary bar.
      primary: false,
      floating: true,
      pinned: isColumnMode,
      // Room for the grown profile button and search text.
      toolbarHeight: max(
        60,
        max(
          40 * AccessibilityScope.of(context).touchTargetScale + 16,
          MediaQuery.textScalerOf(context).scale(17) + 40,
        ),
      ),
      titleSpacing: 16,
      scrolledUnderElevation: 0,
      backgroundColor: isColumnMode
          ? theme.colorScheme.surface.withAlpha(240)
          : Colors.transparent,
      automaticallyImplyLeading: false,
      title: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, _) {
          final status =
              client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final synced =
              client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;
          return ListenableBuilder(
            listenable: controller.searchFocusNode,
            builder: (context, _) => Row(
              children: [
                Expanded(
                  child: CupertinoSearchTextField(
                    controller: controller.searchController,
                    focusNode: controller.searchFocusNode,
                    onChanged: controller.onSearchEnter,
                    onTap: controller.isSearchMode
                        ? null
                        : controller.startSearch,
                    // The 44 pt capsule of the search field since iOS 26.
                    borderRadius: const BorderRadius.all(Radius.circular(22)),
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 12),
                    prefixInsets: const EdgeInsetsDirectional.fromSTEB(
                      14,
                      0,
                      0,
                      2,
                    ),
                    suffixInsets: const EdgeInsetsDirectional.fromSTEB(
                      0,
                      0,
                      12,
                      2,
                    ),
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    placeholder: synced
                        ? (SimplifiedInterfaceScope.enabledOf(context)
                              ? SimplifiedInterfaceL10n.of(context).search
                              : L10n.of(context).searchChatsRooms)
                        : status.calcLocalizedString(context),
                    prefixIcon: !synced || controller.isSearching
                        ? const CupertinoActivityIndicator(radius: 8)
                        : const Icon(CupertinoIcons.search),
                  ),
                ),
                AnimatedSize(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  child:
                      controller.isSearchMode ||
                          controller.searchFocusNode.hasFocus
                      ? _CancelSearchButton(controller.cancelSearch)
                      : Padding(
                          padding: const EdgeInsetsDirectional.only(start: 8),
                          child: ClientChooserButton(controller),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Since iOS 26 an xmark on a glass circle, before the Cancel text button.
class _CancelSearchButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _CancelSearchButton(this.onPressed);

  @override
  Widget build(BuildContext context) {
    final cancel = L10n.of(context).cancel;
    if (!PlatformInfos.supportsLiquidGlass) {
      return CupertinoButton(
        padding: const EdgeInsetsDirectional.only(start: 12),
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: Text(cancel),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Semantics(
        button: true,
        label: cancel,
        excludeSemantics: true,
        child: LiquidGlass(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(44),
            onPressed: onPressed,
            child: Icon(
              CupertinoIcons.xmark,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// The large title of iOS in one row with the button to start a chat.
class ChatListLargeTitle extends StatelessWidget {
  final ChatListController controller;

  const ChatListLargeTitle(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final settings = AccessibilityScope.of(context);
    final showMenu =
        controller.spaces.isNotEmpty || AppSettings.displayNavigationRail.value;
    // The tallest button: the compose button or, if shown, the menu button.
    final buttonHeight = max(
      40 * settings.touchTargetScale,
      showMenu ? settings.icon(24, AccessibleButton.menu) + 16 : 0.0,
    );
    return SliverAppBar(
      pinned: true,
      // Room for the buttons and the labels under them.
      toolbarHeight:
          buttonHeight + 12 + AccessibilityButtonLabel.heightOf(context),
      titleSpacing: 16,
      centerTitle: false,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      backgroundColor: theme.colorScheme.surface.withAlpha(240),
      title: Text(
        L10n.of(context).chats,
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
      // In columns the navigation rail has these buttons.
      actions: isColumnMode
          ? null
          : [
              if (showMenu)
                AccessibilityIconButtons(
                  button: AccessibleButton.menu,
                  child: IconButton(
                    tooltip: L10n.of(context).displayNavigationRail,
                    color: theme.colorScheme.primary,
                    icon: LabeledIcon(
                      icon: const Icon(CupertinoIcons.sidebar_left),
                      label: AppearanceL10n.of(context).labelMenu,
                    ),
                    onPressed: controller.openNavrail,
                  ),
                ),
              AccessibilityIconButtons(
                child: PlatformInfos.supportsLiquidGlass
                    // Centered: the app bar stretches its actions to its height.
                    ? Center(
                        child: AccessibilityButtonLabel(
                          label: L10n.of(context).newChat,
                          color: theme.colorScheme.primary,
                          child: NativeGlassButton(
                            symbol: 'square.and.pencil',
                            label: L10n.of(context).newChat,
                            size: 40 * settings.touchTargetScale,
                            onPressed: () =>
                                context.go('/rooms/newprivatechat'),
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: L10n.of(context).newChat,
                        color: theme.colorScheme.primary,
                        icon: LabeledIcon(
                          icon: const Icon(CupertinoIcons.square_pencil),
                          label: L10n.of(context).newChat,
                        ),
                        onPressed: () => context.go('/rooms/newprivatechat'),
                      ),
              ),
              const SizedBox(width: 8),
            ],
    );
  }
}
