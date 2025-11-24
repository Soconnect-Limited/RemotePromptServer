import Foundation
import UIKit

/// Debug用: 100KB級Markdownの変換・高さ計測時間を測るユーティリティ。
/// リリースビルドには含めない (DEBUGガード推奨)。
enum MarkdownBench {
    static func runOnce(contentSizeKB: Int = 100) {
        #if DEBUG
        let sample = sampleMarkdown(sizeKB: contentSizeKB)
        let t1 = CFAbsoluteTimeGetCurrent()
        let attributed = try? AttributedString(markdown: sample)
        let t2 = CFAbsoluteTimeGetCurrent()

        let tv = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: .greatestFiniteMagnitude))
        if let attributed {
            tv.attributedText = NSAttributedString(attributed)
        } else {
            tv.text = sample
        }
        let t3 = CFAbsoluteTimeGetCurrent()
        _ = tv.sizeThatFits(CGSize(width: 300, height: .greatestFiniteMagnitude))
        let t4 = CFAbsoluteTimeGetCurrent()

        print("[MD-BENCH] size=\(contentSizeKB)KB, convert=\((t2 - t1)*1000)ms, layout=\((t4 - t3)*1000)ms")
        #endif
    }

    private static func sampleMarkdown(sizeKB: Int) -> String {
        let chunk = "# Heading\n\nLorem ipsum dolor sit amet.\n\n```swift\nlet x = 10\n```\n\n"
        var s = ""
        while s.utf8.count < sizeKB * 1024 {
            s.append(chunk)
        }
        return s
    }
}
