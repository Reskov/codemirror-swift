public struct EditorConfiguration: Equatable, Encodable {
    public var darkMode: Bool
    public var lineWrapping: Bool
    public var readOnly: Bool
    public var language: Language

    public init(
        darkMode: Bool = false,
        lineWrapping: Bool = false,
        readOnly: Bool = false,
        language: Language = .txt
    ) {
        self.darkMode = darkMode
        self.lineWrapping = lineWrapping
        self.readOnly = readOnly
        self.language = language
    }
}
