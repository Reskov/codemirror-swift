import SwiftUI

@MainActor
public class CodeMirrorViewModel: ObservableObject {
    public var onLoadSuccess: (() -> Void)?
    public var onLoadFailed: ((Error) -> Void)?
    public var onContentChange: (() -> Void)?

    var executeJS: ((JavascriptFunction, JavascriptCallback?) -> Void)!

    @Published public var darkMode = false
    @Published public var lineWrapping = false
    @Published public var readOnly = false
    @Published public var language: Language = .json

    private func executeJSAsync<T>(f: JavascriptFunction) async throws -> T? {
        try await withCheckedThrowingContinuation { continuation in
            executeJS(f) { result in
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
        guard let executeJS else {
            print("executeJS is not initialized")
            return
        }

        executeJS(
            JavascriptFunction(
                functionString: "CodeMirror.setContent(value)",
                args: ["value": value]
            ),
            nil
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
