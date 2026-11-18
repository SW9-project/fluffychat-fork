import Flutter
import UIKit

/// Creates native Liquid Glass surfaces for Flutter widgets drawn on top of
/// them, such as the message field. Flutter keeps all touches.
@available(iOS 26.0, *)
class LiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "fluffychat/liquid_glass_view"

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(LiquidGlassViewFactory(), withId: viewType)
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LiquidGlassView(frame: frame, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Flutter recreates the view when its arguments change.
@available(iOS 26.0, *)
class LiquidGlassView: NSObject, FlutterPlatformView {
  private let effectView: UIVisualEffectView

  init(frame: CGRect, arguments: [String: Any]) {
    let glass = UIGlassEffect()
    if let argb = arguments["tintColor"] as? Int {
      glass.tintColor = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255
      )
    }
    effectView = UIVisualEffectView(effect: glass)
    effectView.frame = frame
    effectView.isUserInteractionEnabled = false
    if arguments["capsule"] as? Bool == true {
      effectView.cornerConfiguration = .capsule()
    } else {
      let radius = arguments["cornerRadius"] as? Double ?? 0
      effectView.cornerConfiguration = .corners(radius: .fixed(radius))
    }
    if let isDark = arguments["isDark"] as? Bool {
      effectView.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
    super.init()
  }

  func view() -> UIView { effectView }
}

/// The chat list filters as one native row of glass buttons, so that many
/// filters still cost a single platform view. The selected one is tinted.
@available(iOS 26.0, *)
class GlassFilterBarFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "fluffychat/glass_filter_bar"

  private let messenger: FlutterBinaryMessenger

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(GlassFilterBarFactory(messenger: registrar.messenger()), withId: viewType)
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
    GlassFilterBar(
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

/// Flutter sends the whole state with every `update` call and is told about
/// tapped filters with `selected`.
@available(iOS 26.0, *)
class GlassFilterBar: NSObject, FlutterPlatformView {
  private let scrollView = UIScrollView()
  private let stack = UIStackView()
  private let channel: FlutterMethodChannel
  private var labels: [String] = []

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: [String: Any],
    messenger: FlutterBinaryMessenger
  ) {
    channel = FlutterMethodChannel(
      name: "\(GlassFilterBarFactory.viewType)/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()
    scrollView.frame = frame
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.alwaysBounceHorizontal = true
    // Room for the glass shadows, like the 12pt list padding before.
    scrollView.contentInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    stack.axis = .horizontal
    stack.spacing = 6
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
    ])
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

  func view() -> UIView { scrollView }

  private func update(_ arguments: [String: Any]) {
    let labels = arguments["labels"] as? [String] ?? labels
    if labels != self.labels {
      self.labels = labels
      stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
      for (index, label) in labels.enumerated() {
        let button = UIButton(
          primaryAction: UIAction(title: label) { [weak self] _ in
            self?.channel.invokeMethod("selected", arguments: index)
          }
        )
        stack.addArrangedSubview(button)
      }
    }
    if let isDark = arguments["isDark"] as? Bool {
      scrollView.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
    if let argb = arguments["tintColor"] as? Int {
      scrollView.tintColor = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255
      )
    }
    let selectedIndex = arguments["selectedIndex"] as? Int
    for (index, view) in stack.arrangedSubviews.enumerated() {
      guard let button = view as? UIButton else { continue }
      var config: UIButton.Configuration = index == selectedIndex ? .prominentGlass() : .glass()
      config.title = labels[index]
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var attributes = $0
        attributes.font = .systemFont(ofSize: 14, weight: .semibold)
        return attributes
      }
      button.configuration = config
      button.accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
    }
  }
}

/// A native glass `UIButton` with an SF Symbol, such as the compose button.
/// Flutter recreates the view when its arguments change and is told about
/// taps with `pressed`.
@available(iOS 26.0, *)
class GlassButtonFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "fluffychat/glass_button"

  private let messenger: FlutterBinaryMessenger

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(GlassButtonFactory(messenger: registrar.messenger()), withId: viewType)
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
    let arguments = args as? [String: Any] ?? [:]
    let channel = FlutterMethodChannel(
      name: "\(GlassButtonFactory.viewType)/\(viewId)",
      binaryMessenger: messenger
    )
    var config: UIButton.Configuration = .prominentGlass()
    config.image = UIImage(systemName: arguments["symbol"] as? String ?? "")
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: arguments["symbolSize"] as? Double ?? 17,
      weight: .medium
    )
    config.cornerStyle = .capsule
    let button = UIButton(
      configuration: config,
      primaryAction: UIAction { _ in channel.invokeMethod("pressed", arguments: nil) }
    )
    button.frame = frame
    button.accessibilityLabel = arguments["label"] as? String
    if let argb = arguments["tintColor"] as? Int {
      button.tintColor = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255
      )
    }
    if let isDark = arguments["isDark"] as? Bool {
      button.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
    return GlassButton(button: button, channel: channel)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

@available(iOS 26.0, *)
class GlassButton: NSObject, FlutterPlatformView {
  private let button: UIButton
  // Kept alive for the lifetime of the view.
  private let channel: FlutterMethodChannel

  init(button: UIButton, channel: FlutterMethodChannel) {
    self.button = button
    self.channel = channel
    super.init()
  }

  func view() -> UIView { button }
}
