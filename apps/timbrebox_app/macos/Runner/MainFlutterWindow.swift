import Cocoa
import CoreAudio
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private let initialContentSize = NSSize(width: 974, height: 614)
  // Strong reference so the CoreAudio route listener stays alive.
  private var audioRouteHandler: AudioRouteStreamHandler?
  private var guestSearchBridge: GuestSearchBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(initialContentSize)
    self.minSize = NSSize(width: 840, height: 540)
    self.center()
    self.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Bluetooth / headphone connect + disconnect → pause/resume in Dart.
    let handler = AudioRouteStreamHandler()
    let registrar = flutterViewController.registrar(forPlugin: "AudioRoute")
    let channel = FlutterEventChannel(
      name: AudioRouteStreamHandler.channelName,
      binaryMessenger: registrar.messenger)
    channel.setStreamHandler(handler)
    self.audioRouteHandler = handler

    let guestSearch = GuestSearchBridge()
    guestSearch.register(registrar.messenger)
    guestSearchBridge = guestSearch

    super.awakeFromNib()
  }

  // Closing the window hides it instead of tearing down the app, so playback
  // and the loopback control API keep running in the background. The window is
  // restored on reopen (see AppDelegate.applicationShouldHandleReopen).
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    self.orderOut(nil)
    return false
  }
}

/// Emits `"connected"` / `"disconnected"` over a Flutter EventChannel when the
/// system's default audio **output** switches to or from an external device
/// (Bluetooth headset / wired headphones), so Dart pauses on disconnect and
/// resumes on reconnect. Heuristic: default output being non–built-in means an
/// external device is active; built-in → external is "connected", the reverse is
/// "disconnected".
class AudioRouteStreamHandler: NSObject, FlutterStreamHandler {
  static let channelName = "timbrebox/audio_route"

  private var sink: FlutterEventSink?
  private var listenerBlock: AudioObjectPropertyListenerBlock?
  private var wasExternal = false

  private var defaultOutputAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)

  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    wasExternal = isExternal(defaultOutputDevice())
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.handleChange()
    }
    listenerBlock = block
    AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress,
      DispatchQueue.main, block)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let block = listenerBlock {
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress,
        DispatchQueue.main, block)
    }
    listenerBlock = nil
    sink = nil
    return nil
  }

  private func handleChange() {
    let nowExternal = isExternal(defaultOutputDevice())
    if nowExternal == wasExternal { return }
    wasExternal = nowExternal
    sink?(nowExternal ? "connected" : "disconnected")
  }

  private func defaultOutputDevice() -> AudioDeviceID {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, 0, nil,
      &size, &deviceID)
    return deviceID
  }

  private func isExternal(_ device: AudioDeviceID) -> Bool {
    if device == 0 { return false }
    var transport = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(
      device, &address, 0, nil, &size, &transport)
    if status != noErr { return false }
    return transport != kAudioDeviceTransportTypeBuiltIn
  }
}
