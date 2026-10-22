import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Held for the app's lifetime to opt out of App Nap, so the Dart isolate, the
  // loopback control API, and playback keep running at full speed while the app
  // sits in the background with no visible window — a "play" command from the
  // agent then takes effect immediately instead of waiting for the app to be
  // brought to the foreground. Idle system sleep is still allowed.
  private var backgroundActivity: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    backgroundActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep, .automaticTerminationDisabled],
      reason: "Background playback and agent control")
    super.applicationDidFinishLaunching(notification)
  }

  // Keep the app — and its loopback control API — running in the background
  // when the window is closed, so a local agent / CLI can drive playback
  // without the GUI having to stay in the foreground. Quit is still Cmd+Q.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Re-show the window when the user reopens the app (Dock click or relaunch).
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
