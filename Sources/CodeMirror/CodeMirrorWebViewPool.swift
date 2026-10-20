import Foundation

@MainActor
public final class CodeMirrorWebViewPool {
    public static let shared = CodeMirrorWebViewPool()

    public var capacity = 2
    public var preloadConfiguration = EditorConfiguration()
    public var refillDelay: TimeInterval = 1

    private var idleEditors: [EditorWebView] = []
    private var isRefillScheduled = false

    private var isPreloading: Bool {
        idleEditors.contains { !$0.router.isEditorReady }
    }

    public func prewarm() {
        preloadNext()
    }

    func dequeue(configuration: EditorConfiguration) -> EditorWebView {
        defer { scheduleRefill() }

        let index = idleEditors.firstIndex { $0.router.isEditorReady } ?? idleEditors.indices.first
        guard let index else {
            return EditorWebView(configuration: configuration)
        }

        let editor = idleEditors.remove(at: index)
        editor.router.onEditorReady = nil
        editor.router.onProcessTerminated = nil
        return editor
    }

    private func scheduleRefill() {
        guard !isRefillScheduled else { return }
        isRefillScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + refillDelay) {
            self.isRefillScheduled = false
            self.preloadNext()
        }
    }

    private func preloadNext() {
        guard !isPreloading, idleEditors.count < capacity else { return }

        let editor = EditorWebView(configuration: preloadConfiguration)
        editor.router.onEditorReady = { [unowned self] in preloadNext() }
        editor.router.onProcessTerminated = { [unowned self, unowned editor] in
            idleEditors.removeAll { $0 === editor }
            scheduleRefill()
        }
        idleEditors.append(editor)
    }
}
