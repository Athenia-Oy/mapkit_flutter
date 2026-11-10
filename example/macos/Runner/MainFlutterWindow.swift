import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var activity: NSObjectProtocol?

  override var occlusionState: NSWindow.OcclusionState {
    [.visible]
  }

  override func awakeFromNib() {
    if ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil {
      self.orderOut(nil)
      super.awakeFromNib()
      return
    }
    activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical],
      reason: "Keep Flutter engine vsync active when window is behind other apps"
    )
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
