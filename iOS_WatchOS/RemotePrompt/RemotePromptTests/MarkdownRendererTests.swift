@testable import RemotePrompt
import Foundation
import XCTest

final class MarkdownRendererTests: XCTestCase {

    func testRendersMarkdownContent() throws {
        let attributed = MarkdownRenderer.render("**Bold** text")
        let renderedText = String(attributed.characters)

        XCTAssertEqual(renderedText, "Bold text")
        let intents = attributed.runs.compactMap { $0.inlinePresentationIntent }
        XCTAssertTrue(intents.contains(.stronglyEmphasized))
    }

    func testFallsBackWhenParserThrows() throws {
        enum SampleError: Error { case forced }
        let failingParser: MarkdownRenderer.Parser = { _ in throw SampleError.forced }

        let fallback = MarkdownRenderer.render("**Bold**", parser: failingParser)

        XCTAssertEqual(String(fallback.characters), "**Bold**")
    }

    func testHandlesEmptyInput() throws {
        let empty = MarkdownRenderer.render("")

        XCTAssertTrue(empty.characters.isEmpty)
    }
}
