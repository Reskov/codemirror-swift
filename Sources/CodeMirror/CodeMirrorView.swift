import SwiftUI
import WebKit

#if canImport(AppKit)
    public typealias NativeView = NSViewRepresentable
#elseif canImport(UIKit)
    public typealias NativeView = UIViewRepresentable
#endif

@MainActor
public struct CodeMirrorView: NativeView {
    @ObservedObject public var viewModel: CodeMirrorViewModel

    public init(_ viewModel: CodeMirrorViewModel) {
        self.viewModel = viewModel
    }

    #if canImport(AppKit)
        public func makeNSView(context: Context) -> WKWebView {
            createWebView(context: context)
        }

        public func updateNSView(_: WKWebView, context: Context) {
            updateWebView(context: context)
        }

    #elseif canImport(UIKit)
        public func makeUIView(context: Context) -> WKWebView {
            createWebView(context: context)
        }

        public func updateUIView(_: WKWebView, context: Context) {
            updateWebView(context: context)
        }
    #endif

    private func createWebView(context: Context) -> WKWebView {
        let preferences = WKPreferences()
        let userController = WKUserContentController()
        userController.add(context.coordinator, name: ScriptMessageName.codeMirrorDidReady)
        userController.add(context.coordinator, name: ScriptMessageName.codeMirrorContentDidChange)

        let configuration = WKWebViewConfiguration()
        configuration.preferences = preferences
        configuration.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        #if os(OSX)
            webView.setValue(false, forKey: "drawsBackground") // prevent white flicks
            webView.allowsMagnification = false
        #elseif os(iOS)
            webView.isOpaque = false
        #endif

        let indexURL = Bundle.module.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "build"
        )

        let baseURL = Bundle.module.url(forResource: "build", withExtension: nil)
        var htmlString = try! String(contentsOf: indexURL!, encoding: .utf8)
        
        // Inject configuration
        let config = """
            <script>
                window.initialEditorConfig = {
                    darkMode: \(viewModel.darkMode),
                    lineWrapping: \(viewModel.lineWrapping),
                    readOnly: \(viewModel.readOnly),
                    language: "\(viewModel.language.rawValue)"
                };
            </script>
        """
        
        htmlString = htmlString.replacingOccurrences(of: "</head>", with: "\(config)</head>")
        webView.loadHTMLString(htmlString, baseURL: baseURL!)

        
        context.coordinator.webView = webView
        return webView
    }

    private func updateWebView(context: Context) {
        context.coordinator.queueJavascriptFunction(
            JavascriptFunction(
                functionString: "CodeMirror.setDarkMode(value)",
                args: ["value": viewModel.darkMode]
            )
        )
        context.coordinator.queueJavascriptFunction(
            JavascriptFunction(
                functionString: "CodeMirror.setLineWrapping(value)",
                args: ["value": viewModel.lineWrapping]
            )
        )
        context.coordinator.queueJavascriptFunction(
            JavascriptFunction(
                functionString: "CodeMirror.setReadOnly(value)",
                args: ["value": viewModel.readOnly]
            )
        )
        context.coordinator.queueJavascriptFunction(
            JavascriptFunction(
                functionString: "CodeMirror.setLanguage(value)",
                args: ["value": viewModel.language.rawValue]
            )
        )
    }

    public func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(parent: self, viewModel: viewModel)

        viewModel.executeJS = { fn, cb in
            coordinator.queueJavascriptFunction(fn, callback: cb)
        }
        return coordinator
    }
}

@MainActor
public class Coordinator: NSObject {
    var parent: CodeMirrorView
    var viewModel: CodeMirrorViewModel
    weak var webView: WKWebView?

    private var pageLoaded = false
    private var pendingFunctions = [(JavascriptFunction, JavascriptCallback?)]()

    init(parent: CodeMirrorView, viewModel: CodeMirrorViewModel) {
        self.parent = parent
        self.viewModel = viewModel
    }

    func queueJavascriptFunction(
        _ function: JavascriptFunction,
        callback: JavascriptCallback? = nil
    ) {
        if pageLoaded {
            evaluateJavascript(function: function, callback: callback)
        } else {
            pendingFunctions.append((function, callback))
        }
    }

    private func callPendingFunctions() {
        for (function, callback) in pendingFunctions {
            evaluateJavascript(function: function, callback: callback)
        }
        pendingFunctions.removeAll()
    }

    private func evaluateJavascript(
        function: JavascriptFunction,
        callback: JavascriptCallback? = nil
    ) {
        // not sure why but callAsyncJavaScript always callback with result of nil
        if let callback {
            webView?.evaluateJavaScript(function.functionString) { response, error in
                if let error {
                    callback(.failure(error))
                } else {
                    callback(.success(response))
                }
            }
        } else {
            webView?.callAsyncJavaScript(
                function.functionString,
                arguments: function.args,
                in: nil,
                in: .page
            ) { result in
                switch result {
                case let .failure(error):
                    callback?(.failure(error))
                case let .success(data):
                    callback?(.success(data))
                }
            }
        }
    }
}

extension Coordinator: WKScriptMessageHandler {
    public func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case ScriptMessageName.codeMirrorDidReady:
            pageLoaded = true
            callPendingFunctions()
        case ScriptMessageName.codeMirrorContentDidChange:
            parent.viewModel.onContentChange?()
        default:
            print("CodeMirrorWebView receive \(message.name) \(message.body)")
        }
    }
}

extension Coordinator: WKNavigationDelegate {
    public func webView(_: WKWebView, didFinish _: WKNavigation!) {
        parent.viewModel.onLoadSuccess?()
    }

    public func webView(
        _: WKWebView,
        didFail _: WKNavigation!,
        withError error: Error
    ) {
        parent.viewModel.onLoadFailed?(error)
    }

    public func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        parent.viewModel.onLoadFailed?(error)
    }
}
