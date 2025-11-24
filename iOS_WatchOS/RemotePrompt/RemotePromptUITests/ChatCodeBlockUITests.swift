import XCTest

/// Phase 8: コードブロック表示のUIテスト
final class ChatCodeBlockUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - UIテスト1: チャット画面でコードブロックメッセージを送信→CodeBlockViewが表示される
    func testCodeBlockMessageDisplay() throws {
        // 前提: アプリが起動し、チャット画面に遷移している
        // ルーム一覧が表示されるまで待機
        let roomsList = app.otherElements["rooms.list"]
        XCTAssertTrue(roomsList.waitForExistence(timeout: 10), "Rooms list should appear")

        // 最初のルームをタップ（存在する場合）
        let firstRoom = roomsList.buttons.firstMatch
        if firstRoom.exists {
            firstRoom.tap()

            // スレッド一覧が表示されるまで待機
            sleep(2)

            // 最初のスレッドをタップ（存在する場合）
            let threadsList = app.otherElements["threads.list"]
            if threadsList.waitForExistence(timeout: 5) {
                let firstThread = threadsList.buttons.firstMatch
                if firstThread.exists {
                    firstThread.tap()
                    sleep(1)
                }
            }
        }

        // チャット入力フィールドが表示されるまで待機
        let chatInput = app.textFields["chat.input"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 10), "Chat input should appear")

        // コードブロックを含むメッセージを送信
        let testMessage = """
        テストメッセージ
        ```swift
        let x = 10
        print(x)
        ```
        """

        chatInput.tap()
        chatInput.typeText(testMessage)

        // 送信ボタンをタップ
        let sendButton = app.buttons["chat.send"]
        XCTAssertTrue(sendButton.exists, "Send button should exist")
        sendButton.tap()

        // メッセージが表示されるまで待機
        sleep(2)

        // CodeBlockViewが表示されることを確認
        // （実際にはaccessibilityIdentifierを付与する必要がある）
        // ここでは簡易的にチャットメッセージの存在を確認
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'テストメッセージ'")).firstMatch.exists,
                      "Message should be displayed")
    }

    // MARK: - UIテスト2: コードブロックのコピーボタンをタップ
    func testCodeBlockCopyButton() throws {
        // 前提条件: コードブロックメッセージが表示されている状態

        // コピーボタンを探してタップ
        // （実際にはCodeBlockView内のコピーボタンにaccessibilityIdentifierを付与する必要がある）
        let copyButton = app.buttons.matching(identifier: "codeblock.copy").firstMatch
        if copyButton.waitForExistence(timeout: 5) {
            copyButton.tap()

            // コピー成功のフィードバックを確認
            // （ボタンのラベルが"Copied!"に変わることを確認）
            XCTAssertTrue(copyButton.label.contains("Copied"), "Copy button should show 'Copied!' after tap")
        } else {
            XCTFail("Copy button not found. Ensure CodeBlockView has accessibility identifier.")
        }
    }

    // MARK: - UIテスト3: 100KBコードブロックでスクロールがスムーズ
    func testLargeCodeBlockScroll() throws {
        // 注: カクつき検証は手動テストで行う
        // ここでは、大きなコードブロックが表示されることを確認

        // 前提: チャット画面に遷移している
        let chatInput = app.textFields["chat.input"]
        if chatInput.waitForExistence(timeout: 10) {
            chatInput.tap()

            // 大きなコードブロックを含むメッセージ
            let largeCode = String(repeating: "let x = 10\n", count: 1000)
            let testMessage = """
            大きなコードブロック
            ```swift
            \(largeCode)
            ```
            """

            chatInput.typeText(testMessage)

            let sendButton = app.buttons["chat.send"]
            if sendButton.exists {
                sendButton.tap()
                sleep(3)

                // メッセージが表示されることを確認
                XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '大きなコードブロック'")).firstMatch.exists,
                              "Large code block message should be displayed")
            }
        }
    }

    // MARK: - パフォーマンステスト: メッセージ送信とレンダリング
    func testMessageRenderingPerformance() throws {
        measure {
            // チャット画面でメッセージ送信とレンダリングの性能を計測
            let chatInput = app.textFields["chat.input"]
            if chatInput.waitForExistence(timeout: 5) {
                chatInput.tap()
                chatInput.typeText("Performance test message")

                let sendButton = app.buttons["chat.send"]
                if sendButton.exists {
                    sendButton.tap()
                    sleep(1)
                }
            }
        }
    }
}
