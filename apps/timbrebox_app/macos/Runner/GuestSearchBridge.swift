import Cocoa
import FlutterMacOS
import WebKit

/// Opt-in fixed official search only. No arbitrary URL, script or credential API.
final class GuestSearchBridge: NSObject {
  static let channelName = "timbrebox/guest_search"
  private var channel: FlutterMethodChannel?
  private var jobs: [String: GuestSearchSession] = [:]
  private var platforms: [String: String] = [:]
  private var diagnostics: [String: Any] = [:]

  func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "state" {
        result(["active": !self.jobs.isEmpty, "activeCount": self.jobs.count, "hasView": self.jobs.values.contains { $0.hasView },
          "hasWindow": self.jobs.values.contains { $0.hasWindow }, "diagnostics": self.diagnostics])
      } else if call.method == "search" {
        guard let args = call.arguments as? [String: Any], let id = args["jobId"] as? String,
              let platform = args["platform"] as? String, ["tiktok", "douyin"].contains(platform) else {
          result(FlutterError(code: "invalid_media_request", message: "Invalid guest search request.", details: nil)); return
        }
        guard self.jobs[id] == nil, !self.platforms.values.contains(platform), self.jobs.count < 2 else {
          result(FlutterError(code: "guest_search_busy", message: "Official guest search is busy.", details: nil)); return
        }
        let session = GuestSearchSession()
        self.jobs[id] = session; self.platforms[id] = platform
        session.start(args) { [weak self, weak session] value in
          self?.diagnostics = session?.diagnostics ?? [:]
          self?.jobs.removeValue(forKey: id); self?.platforms.removeValue(forKey: id)
          result(value)
        }
      } else if call.method == "cancel" {
        if let args = call.arguments as? [String: Any], let id = args["jobId"] as? String { self.jobs[id]?.cancel() }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }
}

private final class GuestSearchSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
  private var web: WKWebView?
  private var completion: FlutterResult?
  private var deadline: DispatchWorkItem?
  private var jobID: String?
  private var host: String?
  private(set) var diagnostics: [String: Any] = [:]
  var hasView: Bool { web != nil }
  var hasWindow: Bool { web?.window != nil }
  func cancel() { finish(error: "guest_search_cancelled") }

  private func asset(_ name: String) -> String? {
    guard let frameworks = Bundle.main.privateFrameworksURL else { return nil }
    let url = frameworks.appendingPathComponent("App.framework/Resources/flutter_assets/assets/plugin_runtime/" + name)
    guard let bytes = try? Data(contentsOf: url), bytes.count <= 64 * 1024 else { return nil }
    return String(data: bytes, encoding: .utf8)
  }

  func start(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard completion == nil else {
      result(FlutterError(code: "guest_search_busy", message: "Official guest search is busy.", details: nil)); return
    }
    guard let args = arguments as? [String: Any],
          let id = args["jobId"] as? String, id.range(of: "^[a-f0-9]{16,64}$", options: .regularExpression) != nil,
          let platform = args["platform"] as? String, ["tiktok", "douyin"].contains(platform),
          let query = args["query"] as? String, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          query.count <= 200, query.utf8.count <= 800, query.rangeOfCharacter(from: .controlCharacters) == nil,
          let wanted = args["wanted"] as? Int, (1...50).contains(wanted),
          let seen = args["seenIds"] as? [String], seen.count <= 50,
          seen.allSatisfy({ $0.range(of: "^[0-9]{10,25}$", options: .regularExpression) != nil }) else {
      result(FlutterError(code: "invalid_media_request", message: "Invalid guest search request.", details: nil)); return
    }
    guard let parser = asset("guest_search_parser.js"), let capture = asset("guest_search_capture.js"),
          let diagnostic = asset("guest_search_diagnostic.js"),
          let bytes = try? JSONSerialization.data(withJSONObject: ["jobId": id, "platform": platform,
            "query": query, "wanted": wanted, "seenIds": seen]),
          let encoded = String(data: bytes, encoding: .utf8) else {
      result(FlutterError(code: "guest_search_unavailable", message: "Guest search assets are unavailable.", details: nil)); return
    }
    completion = result; jobID = id; diagnostics = [:]
    let hostname = platform == "tiktok" ? "www.tiktok.com" : "www.douyin.com"
    host = hostname
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.mediaTypesRequiringUserActionForPlayback = .all
    config.preferences.javaScriptCanOpenWindowsAutomatically = false
    config.userContentController.add(self, name: "timbreboxGuestSearch")
    let setup = "Object.defineProperty(window,'TimbreBoxGuestSearchConfig',{value:Object.freeze(" + encoded + ")});\n"
    config.userContentController.addUserScript(WKUserScript(source: setup + parser + "\n" + capture,
      injectionTime: .atDocumentStart, forMainFrameOnly: true))
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1050, height: 850), configuration: config)
    view.navigationDelegate = self; view.uiDelegate = self
    web = view
    // Search must never create or show a window. If the official site requires
    // visibility or interaction, return the existing bounded error instead.
    var address = URLComponents()
    address.scheme = "https"; address.host = hostname
    address.path = platform == "tiktok" ? "/search" : "/search/" + query
    address.queryItems = [URLQueryItem(name: platform == "tiktok" ? "q" : "type", value: platform == "tiktok" ? query : "video")]
    guard let url = address.url else { finish(error: "invalid_media_request"); return }
    view.load(URLRequest(url: url))
    let timeout = DispatchWorkItem { [weak self] in
      guard let self = self, self.jobID == id else { return }
      self.web?.evaluateJavaScript(diagnostic) { [weak self] value, _ in
        guard let self = self, self.jobID == id else { return }
        self.diagnostics.merge(value as? [String: Any] ?? [:]) { _, latest in latest }
        // The fixed script has posted verified partial metadata. Its message
        // handler completes the job; the existing 0.5s fallback bounds delivery.
        if self.diagnostics["flushed"] as? Bool == true { return }
        let capture = self.diagnostics["capture"] as? [String: Any]
        let failure = capture?["lastError"] as? String
        if failure == "invalid_search_response" { self.finish(error: "invalid_search_response"); return }
        self.finish(error: failure == "search_access_required" ? "search_access_required" :
          self.diagnostics["needsAction"] as? Bool == true ? "guest_search_access_required" : "guest_search_timeout")
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self, self.jobID == id else { return }
        self.finish(error: "guest_search_timeout")
      }
    }
    deadline = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
  }

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.`protocol` == "https",
          message.frameInfo.securityOrigin.host == host,
          let body = message.body as? [String: Any], body["jobId"] as? String == jobID else { return }
    if let code = body["errorCode"] as? String {
      if let raw = body["diagnostic"] as? [String: Any] {
        for key in ["sourceStatus", "rows", "cursor", "hasMore", "bytes"] {
          if let number = raw[key] as? NSNumber { diagnostics[key] = number }
        }
        if let phase = raw["phase"] as? String, ["waiting", "protocol", "oversize", "json"].contains(phase) { diagnostics["phase"] = phase }
      }
      let allowed = ["search_access_required", "search_request_mismatch", "invalid_search_response", "search_limit_reached"]
      finish(error: allowed.contains(code) ? code : "invalid_search_response"); return
    }
    guard let data = body["data"] as? [[String: Any]], data.count <= 50,
          body["isEnd"] is Bool, let pages = body["pageCount"] as? Int, (1...5).contains(pages),
          let bytes = try? JSONSerialization.data(withJSONObject: body), bytes.count <= 256 * 1024 else {
      finish(error: "invalid_search_response"); return
    }
    let result: [String: Any] = ["data": data, "isEnd": body["isEnd"]!,
      "pageCount": pages, "excludedCount": body["excludedCount"] ?? 0]
    complete(result)
  }

  private func finish(error: String) {
    complete(FlutterError(code: error, message: "Official guest search did not complete. Verification may be required.", details: nil))
  }

  private func complete(_ value: Any?) {
    guard let result = completion else { return }
    #if DEBUG
    if let error = value as? FlutterError {
      NSLog("TimbreBox guest search failed: platform=%@ code=%@", host ?? "closed", error.code)
    } else if let data = value as? [String: Any] {
      NSLog("TimbreBox guest search completed: platform=%@ rows=%d pages=%d", host ?? "closed",
        (data["data"] as? [Any])?.count ?? 0, data["pageCount"] as? Int ?? 0)
    }
    #endif
    completion = nil; jobID = nil; host = nil
    deadline?.cancel(); deadline = nil
    web?.stopLoading(); web?.navigationDelegate = nil; web?.uiDelegate = nil
    web?.configuration.userContentController.removeScriptMessageHandler(forName: "timbreboxGuestSearch")
    web?.configuration.userContentController.removeAllUserScripts()
    web = nil
    result(value)
  }

  func webView(_ view: WKWebView, decidePolicyFor response: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
      diagnostics["documentStatus"] = http.statusCode
      if [401, 403, 429].contains(http.statusCode) {
        decisionHandler(.cancel); finish(error: "search_access_required"); return
      }
    }
    decisionHandler(.allow)
  }

  func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if action.targetFrame?.isMainFrame == true {
      guard let url = action.request.url, url.scheme == "https", url.host == host, url.user == nil, url.password == nil,
            url.port == nil || url.port == 443 else { decisionHandler(.cancel); return }
    }
    decisionHandler(.allow)
  }

  func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if view === web && (error as NSError).code != NSURLErrorCancelled { finish(error: "guest_search_network_error") }
  }

  func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

  @available(macOS 12.0, *)
  func webView(_ view: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
               initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
               decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}
