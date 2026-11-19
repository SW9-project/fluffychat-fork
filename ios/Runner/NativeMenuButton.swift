import Flutter
import UIKit

/// Creates transparent `UIButton`s over Flutter widgets, such as the avatar
/// in the chat list, that open a native pull-down menu.
class NativeMenuButtonFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "fluffychat/menu_button"

  private let messenger: FlutterBinaryMessenger

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      NativeMenuButtonFactory(messenger: registrar.messenger()),
      withId: viewType
    )
  }

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeMenuButton(
      frame: frame,
      viewId: viewId,
      arguments: args as? [String: Any] ?? [:],
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Flutter recreates the view when its arguments change and gets the index
/// of the selected menu item.
class NativeMenuButton: NSObject, FlutterPlatformView {
  private let button = SizedMenuButton(type: .custom)
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: [String: Any],
    messenger: FlutterBinaryMessenger
  ) {
    channel = FlutterMethodChannel(
      name: "\(NativeMenuButtonFactory.viewType)/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    button.frame = frame
    button.backgroundColor = .clear
    button.accessibilityLabel = arguments["label"] as? String
    button.showsMenuAsPrimaryAction = true
    let titles = arguments["titles"] as? [String] ?? []
    let symbols = arguments["symbols"] as? [String] ?? []
    let destructive = Set(arguments["destructive"] as? [Int] ?? [])
    let channel = channel
    button.menu = UIMenu(
      children: zip(titles, symbols).enumerated().map { index, item in
        UIAction(
          title: item.0,
          image: UIImage(systemName: item.1),
          attributes: destructive.contains(index) ? .destructive : []
        ) { _ in
          channel.invokeMethod("selected", arguments: index)
        }
      }
    )
    if let isDark = arguments["isDark"] as? Bool {
      button.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
    if let scale = arguments["textScale"] as? Double {
      button.sizeCategory = Self.sizeCategory(bodySize: 17 * scale)
    }
  }

  func view() -> UIView { button }

  /// The Dynamic Type size whose body text is closest to [bodySize] points.
  static func sizeCategory(bodySize: Double) -> UIContentSizeCategory {
    let sizes: [(Double, UIContentSizeCategory)] = [
      (14, .extraSmall), (15, .small), (16, .medium), (17, .large),
      (19, .extraLarge), (21, .extraExtraLarge), (23, .extraExtraExtraLarge),
      (28, .accessibilityMedium), (33, .accessibilityLarge),
      (40, .accessibilityExtraLarge), (47, .accessibilityExtraExtraLarge),
      (53, .accessibilityExtraExtraExtraLarge),
    ]
    return sizes.min { abs($0.0 - bodySize) < abs($1.0 - bodySize) }!.1
  }
}

/// Shows its menu in [sizeCategory]. The menu is drawn by the window, not
/// the button, so the window's text size changes while the menu is open.
private class SizedMenuButton: UIButton {
  var sizeCategory: UIContentSizeCategory?

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    // shortcut: iOS 15/16 menus keep the system text size, there is no trait
    // override before iOS 17.
    if #available(iOS 17.0, *), let sizeCategory {
      window?.traitOverrides.preferredContentSizeCategory = sizeCategory
    }
    return super.contextMenuInteraction(
      interaction,
      configurationForMenuAtLocation: location
    )
  }

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionAnimating?
  ) {
    super.contextMenuInteraction(
      interaction,
      willEndFor: configuration,
      animator: animator
    )
    if #available(iOS 17.0, *) {
      window?.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
    }
  }
}
