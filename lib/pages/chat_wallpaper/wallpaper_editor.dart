// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_background.dart';
import 'package:fluffychat/pages/chat/events/state_message.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Preview and options for the wallpaper of [room] or, if [room] is null, for
/// the default wallpaper of all chats.
class WallpaperEditor extends StatefulWidget {
  final Room? room;

  const WallpaperEditor({this.room, super.key});

  @override
  State<WallpaperEditor> createState() => _WallpaperEditorState();
}

class _WallpaperEditorState extends State<WallpaperEditor> {
  double? _opacity;
  double? _blur;

  Client get _client => Matrix.of(context).client;

  /// The edited wallpaper or null if the chat uses the default wallpaper.
  ChatWallpaper? get _wallpaper {
    final room = widget.room;
    final wallpaper = room == null
        ? _client.defaultChatWallpaper
        : room.customWallpaper;
    return wallpaper?.copyWith(opacity: _opacity, blur: _blur);
  }

  Future<void> _store(ChatWallpaper? wallpaper) {
    final room = widget.room;
    if (room == null) {
      return _client.setDefaultChatWallpaper(wallpaper ?? ChatWallpaper.none);
    }
    return room.setCustomWallpaper(wallpaper);
  }

  void _select(ChatWallpaper? wallpaper) {
    if (wallpaper?.type == _wallpaper?.type) return;
    setState(() {
      _opacity = _blur = null;
    });
    showFutureLoadingDialog(context: context, future: () => _store(wallpaper));
  }

  Future<void> _pickImage() async {
    final picked = await selectFiles(context, type: FileType.image);
    final pickedFile = picked.firstOrNull;
    if (pickedFile == null) return;
    if (!mounted) return;

    final current = _wallpaper;
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final url = await _client.uploadContent(
          await pickedFile.readAsBytes(),
          filename: pickedFile.name,
        );
        await _store(
          current?.type == ChatWallpaperType.image
              ? ChatWallpaper(
                  type: ChatWallpaperType.image,
                  url: url,
                  opacity: current!.opacity,
                  blur: current.blur,
                )
              : ChatWallpaper(type: ChatWallpaperType.image, url: url),
        );
      },
    );
  }

  Future<void> _saveOpacity(double opacity) async {
    final wallpaper = _wallpaper;
    if (wallpaper == null) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _store(wallpaper.copyWith(opacity: opacity)),
    );
    if (result.isValue || !mounted) return;
    setState(() {
      _opacity = null;
    });
  }

  Future<void> _saveBlur(double blur) async {
    final wallpaper = _wallpaper;
    if (wallpaper == null) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _store(wallpaper.copyWith(blur: blur)),
    );
    if (result.isValue || !mounted) return;
    setState(() {
      _blur = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return StreamBuilder(
      stream: _client.onChatWallpaperChanged,
      builder: (context, _) {
        final wallpaper = _wallpaper;
        final isImage = wallpaper?.type == ChatWallpaperType.image;
        final defaultWallpaper = _client.defaultChatWallpaper;
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            ChatStylePreview(wallpaper: wallpaper ?? defaultWallpaper),
            if (room == null)
              ListTile(
                title: Text(L10n.of(context).wallpaper),
                subtitle: Text(L10n.of(context).defaultWallpaperDescription),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: .center,
                crossAxisAlignment: .start,
                spacing: 12,
                children: [
                  if (room != null)
                    _WallpaperOption(
                      label: L10n.of(context).defaultWallpaper,
                      wallpaper: defaultWallpaper,
                      selected: wallpaper == null,
                      onTap: () => _select(null),
                    ),
                  _WallpaperOption(
                    label: L10n.of(context).blankWallpaper,
                    wallpaper: ChatWallpaper.none,
                    selected: wallpaper?.type == ChatWallpaperType.none,
                    onTap: () => _select(ChatWallpaper.none),
                  ),
                  _WallpaperOption(
                    label: L10n.of(context).patternWallpaper,
                    wallpaper: ChatWallpaper.pattern,
                    selected: wallpaper?.type == ChatWallpaperType.pattern,
                    onTap: () => _select(ChatWallpaper.pattern),
                  ),
                  _WallpaperOption(
                    label: L10n.of(context).imageWallpaper,
                    wallpaper: isImage ? wallpaper : null,
                    icon: isImage
                        ? Icons.edit_outlined
                        : Icons.add_photo_alternate_outlined,
                    selected: isImage,
                    onTap: _pickImage,
                  ),
                ],
              ),
            ),
            if (wallpaper != null && isImage) ...[
              ListTile(title: Text(L10n.of(context).opacity)),
              Slider.adaptive(
                min: 0.1,
                max: 1.0,
                divisions: 9,
                semanticFormatterCallback: (d) => d.toString(),
                value: wallpaper.opacity.clamp(0.1, 1.0),
                onChanged: (opacity) => setState(() {
                  _opacity = opacity;
                }),
                onChangeEnd: _saveOpacity,
              ),
              ListTile(title: Text(L10n.of(context).blur)),
              Slider.adaptive(
                min: 0.0,
                max: 10.0,
                divisions: 10,
                semanticFormatterCallback: (d) => d.toString(),
                value: wallpaper.blur.clamp(0.0, 10.0),
                onChanged: (blur) => setState(() {
                  _blur = blur;
                }),
                onChangeEnd: _saveBlur,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _WallpaperOption extends StatelessWidget {
  final String label;
  final ChatWallpaper? wallpaper;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _WallpaperOption({
    required this.label,
    this.wallpaper,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallpaper = this.wallpaper;
    final icon = this.icon;
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius / 1.5);
    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 88),
        child: Semantics(
          button: true,
          selected: selected,
          child: Column(
            mainAxisSize: .min,
            spacing: 8,
            children: [
              AspectRatio(
                aspectRatio: 0.6,
                child: Material(
                  color: theme.scaffoldBackgroundColor,
                  clipBehavior: Clip.hardEdge,
                  shape: RoundedRectangleBorder(
                    borderRadius: borderRadius,
                    side: selected
                        ? BorderSide(color: theme.colorScheme.primary, width: 3)
                        : BorderSide(color: theme.dividerColor),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (wallpaper != null)
                        ChatWallpaperBackground(
                          wallpaper: wallpaper,
                          isThumbnail: true,
                        ),
                      if (icon != null)
                        Center(
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.surface
                                .withAlpha(wallpaper == null ? 0 : 200),
                            foregroundColor: theme.colorScheme.primary,
                            child: Icon(icon, size: 20),
                          ),
                        ),
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(onTap: onTap),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: .ellipsis,
                textAlign: .center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? theme.colorScheme.primary : null,
                  fontWeight: selected ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A few example messages on top of [wallpaper].
class ChatStylePreview extends StatelessWidget {
  final ChatWallpaper wallpaper;

  const ChatStylePreview({required this.wallpaper, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final bubbleShadows = theme.brightness == Brightness.dark
        ? null
        : const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 1,
              offset: Offset(0, 1),
            ),
          ];
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(AppSettings.fontSizeFactor.value),
      ),
      child: ClipRect(
        child: ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: Stack(
            children: [
              Positioned.fill(
                child: ChatWallpaperBackground(
                  wallpaper: wallpaper,
                  isThumbnail: true,
                ),
              ),
              Column(
                mainAxisSize: .min,
                children: [
                  const SizedBox(height: 16),
                  StateMessage(
                    Event(
                      eventId: 'style_dummy',
                      room: Room(id: '!style_dummy', client: client),
                      content: {'membership': 'join'},
                      type: EventTypes.RoomMember,
                      senderId: client.userID!,
                      originServerTs: DateTime.now(),
                      stateKey: client.userID,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 12 + 12 + Avatar.defaultSize,
                      right: 12,
                      top: 12,
                      bottom: 12,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.bubbleColor,
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius,
                        ),
                        boxShadow: bubbleShadows,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor',
                          style: TextStyle(
                            color: theme.onBubbleColor,
                            fontSize: AppConfig.messageFontSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.otherBubbleColor,
                          borderRadius: BorderRadius.circular(
                            AppConfig.borderRadius,
                          ),
                          boxShadow: bubbleShadows,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            'Lorem ipsum dolor sit amet',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: AppConfig.messageFontSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
