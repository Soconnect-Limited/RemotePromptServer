import Foundation

struct MarkdownRenderer {
    typealias Parser = (String) throws -> AttributedString

    static func render(_ content: String, parser: Parser = liveParser) -> AttributedString {
        guard !content.isEmpty else {
            return AttributedString()
        }

        do {
            return try parser(content)
        } catch {
#if DEBUG
            print("[MarkdownRenderer] Falling back to plain text: \(error)")
#endif
            return AttributedString(content)
        }
    }

    private static func liveParser(_ content: String) throws -> AttributedString {
        try AttributedString(markdown: content)
    }
}
