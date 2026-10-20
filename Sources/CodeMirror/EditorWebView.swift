import WebKit

@MainActor
final class EditorWebView {
    let webView: WKWebView
    let router = ScriptMessageRouter()
    let configuration: EditorConfiguration

    init(configuration: EditorConfiguration) {
        self.configuration = configuration

        let userController = WKUserContentController()
        userController.add(router, name: ScriptMessageName.codeMirrorDidReady)
        userController.add(router, name: ScriptMessageName.codeMirrorContentDidChange)
        userController.addUserScript(
            WKUserScript(
                source: Self.initialConfigurationScript(configuration),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController = userController

        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = router

        #if os(OSX)
            webView.setValue(false, forKey: "drawsBackground")  // prevent white flicks
            webView.allowsMagnification = false
        #elseif os(iOS)
            webView.isOpaque = false
        #endif

        webView.loadFileURL(Self.indexURL, allowingReadAccessTo: Self.buildURL)
    }

    private static let buildURL = Bundle.module.url(forResource: "build", withExtension: nil)!
    private static let indexURL = buildURL.appendingPathComponent("index.html")

    private static func initialConfigurationScript(_ configuration: EditorConfiguration) -> String {
        let json = try! JSONEncoder().encode(configuration)
        return "window.initialEditorConfig = \(String(decoding: json, as: UTF8.self));"
    }
}

@MainActor
final class ScriptMessageRouter: NSObject {
    weak var coordinator: Coordinator?
    var onEditorReady: (() -> Void)?
    var onProcessTerminated: (() -> Void)?

    private(set) var isEditorReady = false
    private(set) var didFinishNavigation = false
}

extension ScriptMessageRouter: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == ScriptMessageName.codeMirrorDidReady {
            isEditorReady = true
            onEditorReady?()
        }
        coordinator?.userContentController(userContentController, didReceive: message)
    }
}

extension ScriptMessageRouter: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishNavigation = true
        coordinator?.webView(webView, didFinish: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        coordinator?.webView(webView, didFail: navigation, withError: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        coordinator?.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        onProcessTerminated?()
    }
}
