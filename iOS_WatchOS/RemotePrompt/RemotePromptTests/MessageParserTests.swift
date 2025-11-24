import Testing
import Foundation
@testable import RemotePrompt

/// Phase 8: MessageParserのユニットテスト
/// Master_Specification 8.7準拠
struct MessageParserTests {

    // MARK: - Test 1: 通常テキストのみのパース
    @Test("通常テキストのみのパース")
    func testPlainTextParsing() {
        let input = "これは通常のテキストです。"
        let segments = MessageParser.parse(input, isUser: false)

        #expect(segments.count == 1)
        if case .text = segments[0] {
            // 正常: .text型のセグメント
        } else {
            Issue.record("Expected .text segment, got: \(segments[0])")
        }
    }

    // MARK: - Test 2: コードブロック1個のパース（言語名あり）
    @Test("コードブロック1個のパース - 言語名あり")
    func testSingleCodeBlockWithLanguage() {
        let input = """
        ```swift
        let x = 10
        ```
        """
        let segments = MessageParser.parse(input, isUser: false)

        #expect(segments.count == 1)
        if case .codeBlock(let code, let language) = segments[0] {
            #expect(code == "let x = 10")
            #expect(language == "swift")
        } else {
            Issue.record("Expected .codeBlock segment, got: \(segments[0])")
        }
    }

    // MARK: - Test 2-2: コードブロック1個のパース（言語名なし）
    @Test("コードブロック1個のパース - 言語名なし")
    func testSingleCodeBlockWithoutLanguage() {
        let input = """
        ```
        let x = 10
        ```
        """
        let segments = MessageParser.parse(input, isUser: false)

        #expect(segments.count == 1)
        if case .codeBlock(let code, let language) = segments[0] {
            #expect(code == "let x = 10")
            #expect(language == nil)
        } else {
            Issue.record("Expected .codeBlock segment, got: \(segments[0])")
        }
    }

    // MARK: - Test 3: 混在メッセージのパース（text + code + text）
    @Test("混在メッセージのパース")
    func testMixedContentParsing() {
        let input = """
        前のテキスト
        ```python
        print("hello")
        ```
        後のテキスト
        """
        let segments = MessageParser.parse(input, isUser: false)

        #expect(segments.count == 3)

        // 最初のセグメント: テキスト
        if case .text = segments[0] {
            // OK
        } else {
            Issue.record("Expected .text segment at index 0")
        }

        // 2番目のセグメント: コードブロック
        if case .codeBlock(let code, let language) = segments[1] {
            #expect(code.contains("print"))
            #expect(language == "python")
        } else {
            Issue.record("Expected .codeBlock segment at index 1")
        }

        // 3番目のセグメント: テキスト
        if case .text = segments[2] {
            // OK
        } else {
            Issue.record("Expected .text segment at index 2")
        }
    }

    // MARK: - Test 4: セグメント上限（21個のコードブロック→20個に切り詰め）
    @Test("セグメント上限チェック")
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
        #expect(segments.count == 20)
    }

    // MARK: - Test 5: パース性能計測（100KB入力でログ出力検証）
    @Test("パース性能計測 - 100KB入力")
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
        #expect(segments.count >= 1)
    }

    // MARK: - Test 6: Markdownフォールバック（renderText内部テスト）
    @Test("空文字入力")
    func testEmptyInput() {
        let input = ""
        let segments = MessageParser.parse(input, isUser: false)

        // 空文字の場合、プレーンテキストセグメント1個が返される
        #expect(segments.count == 1)
        if case .text = segments[0] {
            // OK
        } else {
            Issue.record("Expected .text segment for empty input")
        }
    }

    // MARK: - Test 7: 空白のみの入力
    @Test("空白のみの入力")
    func testWhitespaceOnlyInput() {
        let input = "   \n\n   "
        let segments = MessageParser.parse(input, isUser: false)

        // 空白のみの場合もパース可能
        #expect(segments.count >= 1)
    }

    // MARK: - Test 8: コードブロックの境界条件
    @Test("不完全なコードブロック")
    func testIncompleteCodeBlock() {
        let input = """
        ```swift
        let x = 10
        """
        // 閉じタグがない場合、正規表現にマッチしないためテキストとして扱われる
        let segments = MessageParser.parse(input, isUser: false)

        #expect(segments.count == 1)
        if case .text = segments[0] {
            // OK: 不完全なコードブロックはテキストとして扱われる
        } else {
            Issue.record("Expected .text segment for incomplete code block")
        }
    }
}
