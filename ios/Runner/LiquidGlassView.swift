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
    // Already scaled by the app's text size in Flutter.
    let fontSize = CGFloat(arguments["fontSize"] as? Double ?? 14)
    for (index, view) in stack.arrangedSubviews.enumerated() {
      guard let button = view as? UIButton else { continue }
      var config: UIButton.Configuration = index == selectedIndex ? .prominentGlass() : .glass()
      config.title = labels[index]
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var attributes = $0
        attributes.font = .systemFont(ofSize: fontSize, weight: .semibold)
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

/// A native `UISlider`, which since iOS 26 has a Liquid Glass thumb and tick
/// marks. Flutter sends its state with `update` and is told about drags with
/// `changeStart`, `changed` and `changeEnd`.
@available(iOS 26.0, *)
class GlassSliderFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "fluffychat/glass_slider"

  private let messenger: FlutterBinaryMessenger

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(GlassSliderFactory(messenger: registrar.messenger()), withId: viewType)
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
    GlassSlider(
      frame: frame,
      channel: FlutterMethodChannel(
        name: "\(GlassSliderFactory.viewType)/\(viewId)",
        binaryMessenger: messenger
      ),
      arguments: args as? [String: Any] ?? [:]
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

@available(iOS 26.0, *)
class GlassSlider: NSObject, FlutterPlatformView {
  private let slider = UISlider()
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, arguments: [String: Any]) {
    self.channel = channel
    super.init()
    slider.frame = frame
    slider.addAction(
      UIAction { [weak self] _ in self?.channel.invokeMethod("changeStart", arguments: nil) },
      for: .touchDown
    )
    slider.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        self.channel.invokeMethod("changed", arguments: Double(self.slider.value))
      },
      for: .valueChanged
    )
    slider.addAction(
      UIAction { [weak self] _ in self?.channel.invokeMethod("changeEnd", arguments: nil) },
      for: [.touchUpInside, .touchUpOutside, .touchCancel]
    )
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

  func view() -> UIView { slider }

  private func update(_ arguments: [String: Any]) {
    let min = Float(arguments["min"] as? Double ?? 0)
    let max = Float(arguments["max"] as? Double ?? 1)
    if slider.minimumValue != min || slider.maximumValue != max {
      slider.minimumValue = min
      slider.maximumValue = max
    }
    let ticks = arguments["ticks"] as? Int ?? 0
    if (slider.trackConfiguration?.ticks.count ?? 0) != ticks {
      slider.trackConfiguration =
        ticks > 1 ? UISlider.TrackConfiguration(numberOfTicks: ticks) : nil
    }
    let value = Float(arguments["value"] as? Double ?? Double(min))
    if slider.value != value { slider.value = value }
    slider.isEnabled = arguments["enabled"] as? Bool ?? true
    slider.accessibilityLabel = arguments["label"] as? String
    slider.accessibilityValue = arguments["valueLabel"] as? String
    if let argb = arguments["tintColor"] as? Int {
      slider.minimumTrackTintColor = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255
      )
    }
    if let isDark = arguments["isDark"] as? Bool {
      slider.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
  }
}

/// A native labelled `UIButton`: plain, glass or prominent glass. Flutter
/// sends its state with `update`, which answers with the intrinsic size, and
/// is told about taps with `pressed`.
@available(iOS 26.0, *)
class NativeButtonFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "fluffychat/native_button"

  private let messenger: FlutterBinaryMessenger

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(NativeButtonFactory(messenger: registrar.messenger()), withId: viewType)
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
    NativeButton(
      frame: frame,
      channel: FlutterMethodChannel(
        name: "\(NativeButtonFactory.viewType)/\(viewId)",
        binaryMessenger: messenger
      ),
      arguments: args as? [String: Any] ?? [:]
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

@available(iOS 26.0, *)
class NativeButton: NSObject, FlutterPlatformView {
  private let button = UIButton(type: .system)
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, arguments: [String: Any]) {
    self.channel = channel
    super.init()
    button.frame = frame
    button.addAction(
      UIAction { [weak self] _ in self?.channel.invokeMethod("pressed", arguments: nil) },
      for: .primaryActionTriggered
    )
    update(arguments)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "update", let arguments = call.arguments as? [String: Any]
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.update(arguments)
      let size = self.button.intrinsicContentSize
      result([Double(ceil(size.width)), Double(ceil(size.height))])
    }
  }

  func view() -> UIView { button }

  private func update(_ arguments: [String: Any]) {
    let style = arguments["style"] as? String
    var config: UIButton.Configuration =
      switch style {
      case "prominent": .prominentGlass()
      case "glass": .glass()
      default: .plain()
      }
    config.title = arguments["label"] as? String
    config.titleLineBreakMode = .byTruncatingTail
    // Already scaled by the app's text size in Flutter.
    let fontSize = CGFloat(arguments["fontSize"] as? Double ?? 17)
    let weight: UIFont.Weight = style == "prominent" ? .semibold : .regular
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = .systemFont(ofSize: fontSize, weight: weight)
      return attributes
    }
    if let symbol = arguments["symbol"] as? String {
      config.image = UIImage(systemName: symbol)
      config.imagePadding = 6
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: fontSize * 0.9,
        weight: style == "prominent" ? .semibold : .regular
      )
    }
    button.configuration = config
    button.isEnabled = arguments["enabled"] as? Bool ?? true
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
  }
}
