import SwiftUI

@MainActor
public class CodeMirrorViewModel: ObservableObject {
    public var onLoadSuccess: (() -> Void)?
    public var onLoadFailed: ((Error) -> Void)?
    public var onContentChange: (() -> Void)?

    var executeJS: ((JavascriptFunction, JavascriptCallback?) -> Void)? {
        didSet { flushPendingFunctions() }
    }

    private var pendingFunctions = [(JavascriptFunction, JavascriptCallback?)]()

    @Published public var darkMode = false
    @Published public var lineWrapping = false
    @Published public var readOnly = false
    @Published public var language: Language = .json

    var configuration: EditorConfiguration {
        EditorConfiguration(
            darkMode: darkMode,
            lineWrapping: lineWrapping,
            readOnly: readOnly,
            language: language
        )
    }

    private func execute(_ function: JavascriptFunction, callback: JavascriptCallback? = nil) {
        if let executeJS {
            executeJS(function, callback)
        } else {
            pendingFunctions.append((function, callback))
        }
    }

    private func flushPendingFunctions() {
        guard let executeJS else { return }
        let functions = pendingFunctions
        pendingFunctions.removeAll()
        for (function, callback) in functions {
            executeJS(function, callback)
        }
    }

    private func executeJSAsync<T>(f: JavascriptFunction) async throws -> T? {
        try await withCheckedThrowingContinuation { continuation in
            execute(f) { result in
                continuation.resume(with: result.map { $0 as? T })
            }
        }
    }

    public func toggleSearchPanel() async throws -> Void? {
        try await executeJSAsync(
            f: JavascriptFunction(
                functionString: "CodeMirror.toggleSearchPanel()"
            )
        )
    }

    public func getContent() async throws -> String? {
        try await executeJSAsync(
            f: JavascriptFunction(
                functionString: "CodeMirror.getContent()"
            )
        )
    }

    public func setContent(_ value: String) {
        execute(
            JavascriptFunction(
                functionString: "CodeMirror.setContent(value)",
                args: ["value": value]
            )
        )
    }

    public init(
        onLoadSuccess: (() -> Void)? = nil,
        onLoadFailed: ((Error) -> Void)? = nil,
        onContentChange: (() -> Void)? = nil
    ) {
        self.onLoadSuccess = onLoadSuccess
        self.onLoadFailed = onLoadFailed
        self.onContentChange = onContentChange
    }
}
