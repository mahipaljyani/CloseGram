import SwiftUI
import WebKit

/// Owns the web view that shows instagram.com and keeps the injected script in sync with settings.
final class WebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let origin = "https://www.instagram.com"

    /// Hosts that stay inside the app. Anything else opens in Safari.
    private static let internalHosts = ["instagram.com", "facebook.com", "meta.com", "fbcdn.net", "cdninstagram.com", "fbsbx.com"]

    /// A normal iPhone Safari user agent, so Instagram serves its full mobile site.
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Instagram's own top-level screens, which have their own navigation, so no back button is shown on them.
    private static let rootPaths: Set<String> = ["/", "/direct/inbox/", "/explore/", "/accounts/login/"]

    let webView: WKWebView
    @Published private(set) var path = "/"
    @Published private(set) var canGoBack = false
    private var installed: ScriptConfig?
    var onRoute: ((String) -> Void)?
    var onStat: ((String) -> Void)?
    private var backObservation: NSKeyValueObservation?

    /// True on pages deeper than a top-level screen, where a native back button helps.
    var showsBackButton: Bool { canGoBack && !Self.rootPaths.contains(path) }

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default() // persistent: keeps the Instagram session cookie on the device
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.add(WeakMessageHandler(self), name: "qg")
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false // long-press should not pop up a Safari link preview
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulledToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
        }

        let current = installScript()
        navigate(current.startPath)
        #if DEBUG
        startDebugEval()
        #endif
    }

    #if DEBUG
    /// Debug builds only: runs JavaScript dropped into Documents/eval.js and writes the result to
    /// Documents/eval.out, so the page can be inspected from the Mac while testing in the simulator.
    private func startDebugEval() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = docs.appendingPathComponent("eval.js")
        let output = docs.appendingPathComponent("eval.out")
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let js = try? String(contentsOf: input, encoding: .utf8) else { return }
            try? FileManager.default.removeItem(at: input)
            self.webView.evaluateJavaScript(js) { result, error in
                let text = result.map { String(describing: $0) } ?? "error: \(String(describing: error))"
                try? text.write(to: output, atomically: true, encoding: .utf8)
            }
        }
    }
    #endif

    /// Rebuilds the injected script from the current settings. Reloads the page,
    /// or goes to the new start page when the settings change where the app opens.
    func applySettings() {
        let previous = installed
        let current = installScript()
        if previous?.startPath != current.startPath || previous?.messagesOnly != current.messagesOnly {
            navigate(current.startPath)
        } else {
            webView.reload()
        }
    }

    /// Called every few seconds: quiet hours start and end with the clock, not with a settings change.
    func refreshTimeBasedMode() {
        if ScriptConfig.current() != installed { applySettings() }
    }

    func goHome() {
        navigate((installed ?? ScriptConfig.current()).startPath)
    }

    func navigate(_ path: String) {
        guard let url = URL(string: Self.origin + path) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    /// Signs out of everything by deleting all cookies and site data.
    func clearAllData() {
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            self?.goHome()
        }
    }

    @discardableResult
    private func installScript() -> ScriptConfig {
        let config = ScriptConfig.current()
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: InjectedScript.source(config), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        installed = config
        return config
    }

    @objc private func pulledToRefresh(_ sender: UIRefreshControl) {
        webView.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sender.endRefreshing() }
    }

    private static func isInternal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true } // about:blank, blob:, data:
        return internalHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "route":
            if let path = body["path"] as? String {
                self.path = path
                onRoute?(path)
            }
        case "stat":
            if let kind = body["kind"] as? String { onStat?(kind) }
        case "log":
            NSLog("[QG] %@", (body["text"] as? String) ?? "")
        default:
            break
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame ?? true else {
            decisionHandler(.allow)
            return
        }
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            // Blocks instagram:// and other app links, so nothing bounces you into the native app.
            decisionHandler(["about", "blob", "data"].contains(scheme) ? .allow : .cancel)
            return
        }
        if !Self.isInternal(url) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let path = webView.url?.path { self.path = path.hasSuffix("/") ? path : path + "/" }
    }

    // MARK: WKUIDelegate

    /// Links that ask for a new window load in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if Self.isInternal(url) {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    /// The system still shows its own camera and microphone prompt the first time.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.hasSuffix("instagram.com") ? .grant : .deny)
    }
}

/// Breaks the retain cycle between the web view's content controller and WebModel.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

struct WebView: UIViewRepresentable {
    let model: WebModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
