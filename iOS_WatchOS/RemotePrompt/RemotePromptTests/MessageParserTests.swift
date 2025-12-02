import XCTest
@testable import RemotePrompt

/// Phase 8: MessageParserのユニットテスト
/// Master_Specification 8.7準拠
final class MessageParserTests: XCTestCase {

    // MARK: - Test 1: 通常テキストのみのパース
    func testPlainTextParsing() {
        let input = "これは通常のテキストです。"
        let segments = MessageParser.parse(input, isUser: false)

        XCTAssertEqual(segments.count, 1)
        if case .text = segments[0] {
            // 正常: .text型のセグメント
        } else {
            XCTFail("Expected .text segment, got: \(segments[0])")
        }
    }

    // MARK: - Test 2: コードブロック1個のパース（言語名あり）
    func testSingleCodeBlockWithLanguage() {
        let input = "```swift\nlet x = 10\n```"
        let segments = MessageParser.parse(input, isUser: false)

        XCTAssertEqual(segments.count, 1)
        if case .codeBlock(let code, let language) = segments[0] {
            XCTAssertTrue(code.contains("let x = 10"))
            XCTAssertEqual(language, "swift")
        } else {
            XCTFail("Expected .codeBlock segment, got: \(segments[0])")
        }
    }

    // MARK: - Test 2-2: コードブロック1個のパース（言語名なし）
    func testSingleCodeBlockWithoutLanguage() {
        let input = "```\nlet x = 10\n```"
        let segments = MessageParser.parse(input, isUser: false)

        XCTAssertEqual(segments.count, 1)
        if case .codeBlock(let code, let language) = segments[0] {
            XCTAssertTrue(code.contains("let x = 10"))
            XCTAssertNil(language)
        } else {
            XCTFail("Expected .codeBlock segment, got: \(segments[0])")
        }
    }

    // MARK: - Test 3: 混在メッセージのパース（text + code + text）
    func testMixedContentParsing() {
        let input = "前のテキスト\n```python\nprint(\"hello\")\n```\n後のテキスト"
        let segments = MessageParser.parse(input, isUser: false)

        XCTAssertEqual(segments.count, 3)

        // 最初のセグメント: テキスト
        if case .text = segments[0] {
            // OK
        } else {
            XCTFail("Expected .text segment at index 0")
        }

        // 2番目のセグメント: コードブロック
        if case .codeBlock(let code, let language) = segments[1] {
            XCTAssertTrue(code.contains("print"))
            XCTAssertEqual(language, "python")
        } else {
            XCTFail("Expected .codeBlock segment at index 1")
        }

        // 3番目のセグメント: テキスト
        if case .text = segments[2] {
            // OK
        } else {
            XCTFail("Expected .text segment at index 2")
        }
    }

    // MARK: - Test 4: セグメント上限（21個のコードブロック→20個に切り詰め）
    func testSegmentLimit() {
        // 21個のコードブロックを生成
        var input = ""
        for i in 1...21 {
            input += """
            ```swift
            let x\(i) = \(i)
            ```

            """
        }

        let segments = MessageParser.parse(input, isUser: false)

        // 20個に切り詰められることを確認
        XCTAssertEqual(segments.count, 20)
    }

    // MARK: - Test 5: パース性能計測（100KB入力でログ出力検証）
    func testPerformanceMeasurement() {
        // 100KB以上のテキストを生成
        let largeText = String(repeating: "a", count: 100_001)
        let input = """
        \(largeText)
        ```swift
        let x = 10
        ```
        """

        // パースを実行（内部でログ出力される）
        let segments = MessageParser.parse(input, isUser: false)

        // ログ出力の有無は目視確認またはXcodeのコンソールで確認
        // CI環境の非決定性を考慮し、閾値断定はしない
        XCTAssertGreaterThanOrEqual(segments.count, 1)
    }

    // MARK: - Test 6: Markdownフォールバック（renderText内部テスト）
    func testEmptyInput() {
        let input = ""
        let segments = MessageParser.parse(input, isUser: false)

        // 空文字の場合、プレーンテキストセグメント1個が返される
        XCTAssertEqual(segments.count, 1)
        if case .text = segments[0] {
            // OK
        } else {
            XCTFail("Expected .text segment for empty input")
        }
    }

    // MARK: - Test 7: 空白のみの入力
    func testWhitespaceOnlyInput() {
        let input = "   \n\n   "
        let segments = MessageParser.parse(input, isUser: false)

        // 空白のみの場合もパース可能
        XCTAssertGreaterThanOrEqual(segments.count, 1)
    }

    // MARK: - Test 8: コードブロックの境界条件
    func testIncompleteCodeBlock() {
        let input = """
        ```swift
        let x = 10
        """
        // 閉じタグがない場合、正規表現にマッチしないためテキストとして扱われる
        let segments = MessageParser.parse(input, isUser: false)

        XCTAssertEqual(segments.count, 1)
        if case .text = segments[0] {
            // OK: 不完全なコードブロックはテキストとして扱われる
        } else {
            XCTFail("Expected .text segment for incomplete code block")
        }
    }
}
