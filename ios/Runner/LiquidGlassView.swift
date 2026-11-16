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
    effectView = UIVisualEffectView(effect: UIGlassEffect())
    effectView.frame = frame
    effectView.isUserInteractionEnabled = false
    let radius = arguments["cornerRadius"] as? Double ?? 0
    effectView.cornerConfiguration = .corners(radius: .fixed(radius))
    if let isDark = arguments["isDark"] as? Bool {
      effectView.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
    super.init()
  }

  func view() -> UIView { effectView }
}
