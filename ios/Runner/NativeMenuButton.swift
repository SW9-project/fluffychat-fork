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
  private let button = UIButton(type: .custom)
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
    let channel = channel
    button.menu = UIMenu(
      children: zip(titles, symbols).enumerated().map { index, item in
        UIAction(title: item.0, image: UIImage(systemName: item.1)) { _ in
          channel.invokeMethod("selected", arguments: index)
        }
      }
    )
    if let isDark = arguments["isDark"] as? Bool {
      button.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
  }

  func view() -> UIView { button }
}
