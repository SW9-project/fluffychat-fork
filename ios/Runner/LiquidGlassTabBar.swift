import Flutter
import UIKit

/// Creates native `UITabBar`s for the Flutter navigation bar. Built with the
/// iOS 26 SDK, they float above the content and are rendered with Liquid Glass.
class LiquidGlassTabBarFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "fluffychat/liquid_glass_tab_bar"

  private let messenger: FlutterBinaryMessenger

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      LiquidGlassTabBarFactory(messenger: registrar.messenger()),
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
    LiquidGlassTabBar(
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

/// Flutter sends the whole state of the tab bar with every `update` call and
/// gets notified about selected tabs and about the height the bar needs.
class LiquidGlassTabBar: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: LayoutObservingView
  private let tabBar = UITabBar()
  private let channel: FlutterMethodChannel
  private var labels: [String] = []
  private var symbols: [String] = []
  private var reportedHeight: CGFloat = 0

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: [String: Any],
    messenger: FlutterBinaryMessenger
  ) {
    container = LayoutObservingView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(LiquidGlassTabBarFactory.viewType)/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    container.backgroundColor = .clear
    // The bar is never wider than a phone, also not on iPads, where the
    // regular width would put the titles next to the icons.
    if #available(iOS 17.0, *) {
      container.traitOverrides.horizontalSizeClass = .compact
    }
    tabBar.delegate = self
    tabBar.frame = container.bounds
    tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(tabBar)
    container.onLayout = { [weak self] in self?.reportHeight() }

    update(arguments)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let arguments = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(arguments)
      result(nil)
    }
  }

  func view() -> UIView { container }

  private func update(_ arguments: [String: Any]) {
    let labels = arguments["labels"] as? [String] ?? labels
    let symbols = arguments["symbols"] as? [String] ?? symbols
    if labels != self.labels || symbols != self.symbols {
      self.labels = labels
      self.symbols = symbols
      tabBar.items = zip(labels, symbols).enumerated().map { index, item in
        UITabBarItem(title: item.0, image: UIImage(systemName: item.1), tag: index)
      }
    }
    let items = tabBar.items ?? []
    if let badges = arguments["badges"] as? [Any] {
      for (item, badge) in zip(items, badges) {
        item.badgeValue = badge as? String
      }
    }
    if let selectedIndex = arguments["selectedIndex"] as? Int,
      items.indices.contains(selectedIndex),
      tabBar.selectedItem !== items[selectedIndex]
    {
      tabBar.selectedItem = items[selectedIndex]
    }
    if let tintColor = arguments["tintColor"] as? Int {
      tabBar.tintColor = UIColor(argb: tintColor)
    }
    if let isDark = arguments["isDark"] as? Bool {
      container.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
  }

  /// The height includes the space between the floating bar and the bottom
  /// of the screen, if the bar is placed there.
  private func reportHeight() {
    // Flutter removes the view from the window while the bar is hidden. The
    // safe area and so the height are only known inside of the window.
    guard container.window != nil else { return }
    let height = tabBar.sizeThatFits(
      CGSize(width: container.bounds.width, height: .greatestFiniteMagnitude)
    ).height
    guard height > 0, height != reportedHeight else { return }
    reportedHeight = height
    channel.invokeMethod("heightChanged", arguments: Double(height))
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("tabSelected", arguments: item.tag)
  }
}

private class LayoutObservingView: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

extension UIColor {
  fileprivate convenience init(argb: Int) {
    self.init(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
