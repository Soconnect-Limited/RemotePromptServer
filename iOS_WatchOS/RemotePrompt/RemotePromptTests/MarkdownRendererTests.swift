@testable import RemotePrompt
import Foundation
import Testing

struct MarkdownRendererTests {
    @Test func rendersMarkdownContent() throws {
        let attributed = MarkdownRenderer.render("**Bold** text")
        let renderedText = String(attributed.characters)

        #expect(renderedText == "Bold text")
        let intents = attributed.runs.compactMap { $0.inlinePresentationIntent }
        #expect(intents.contains(.stronglyEmphasized))
    }

    @Test func fallsBackWhenParserThrows() throws {
        enum SampleError: Error { case forced }
        let failingParser: MarkdownRenderer.Parser = { _ in throw SampleError.forced }

        let fallback = MarkdownRenderer.render("**Bold**", parser: failingParser)

        #expect(String(fallback.characters) == "**Bold**")
    }

    @Test func handlesEmptyInput() throws {
        let empty = MarkdownRenderer.render("")

        #expect(empty.characters.isEmpty)
    }
}
