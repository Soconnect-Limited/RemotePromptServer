import Foundation
import SwiftUI

struct MarkdownHighlighter {
    struct Style {
        let color: Color
        let font: Font?
    }

    private let patterns: [(NSRegularExpression, Style)] = [
        (try! NSRegularExpression(pattern: "^(#{1,3})\\s.+", options: [.anchorsMatchLines]), Style(color: .blue, font: .headline)),
        (try! NSRegularExpression(pattern: "^(-|\\*|\\d+\\. )\\s.+", options: [.anchorsMatchLines]), Style(color: .green, font: .body)),
        (try! NSRegularExpression(pattern: "```.*?```", options: [.dotMatchesLineSeparators]), Style(color: .orange, font: .body.monospaced())),
        (try! NSRegularExpression(pattern: "`[^`]+`", options: []), Style(color: .orange, font: .body.monospaced())),
        (try! NSRegularExpression(pattern: "\\*\\*[^*]+\\*\\*", options: []), Style(color: .purple, font: .body.bold())),
        (try! NSRegularExpression(pattern: "\\*[^*]+\\*", options: []), Style(color: .purple, font: .body.italic())),
        (try! NSRegularExpression(pattern: "\\[[^]]+\\]\\([^)]*\\)", options: []), Style(color: .cyan, font: .body))
    ]

    func highlight(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        for (regex, style) in patterns {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                if let swiftRange = Range(range, in: text) {
                    var sub = AttributedString(text[swiftRange])
                    sub.foregroundColor = style.color
                    if let font = style.font {
                        sub.font = font
                    }
                    attributed.replaceSubrange(swiftRange, with: sub)
                }
            }
        }
        return attributed
    }
}
