import Foundation
import UIKit

struct MarkdownHighlighter {
    struct Style {
        let color: UIColor
        let font: UIFont?
    }

    private let patterns: [(NSRegularExpression, Style)] = [
        (try! NSRegularExpression(pattern: "^(#{1,3})\\s.+", options: [.anchorsMatchLines]), Style(color: .systemBlue, font: .preferredFont(forTextStyle: .headline))),
        (try! NSRegularExpression(pattern: "^(-|\\*|\\d+\\. )\\s.+", options: [.anchorsMatchLines]), Style(color: .systemGreen, font: .preferredFont(forTextStyle: .body))),
        (try! NSRegularExpression(pattern: "```.*?```", options: [.dotMatchesLineSeparators]), Style(color: .systemOrange, font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular))),
        (try! NSRegularExpression(pattern: "`[^`]+`", options: []), Style(color: .systemOrange, font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular))),
        (try! NSRegularExpression(pattern: "\\*\\*[^*]+\\*\\*", options: []), Style(color: .systemPurple, font: .boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize))),
        (try! NSRegularExpression(pattern: "\\*[^*]+\\*", options: []), Style(color: .systemPurple, font: .italicSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize))),
        (try! NSRegularExpression(pattern: "\\[[^]]+\\]\\([^)]*\\)", options: []), Style(color: .systemTeal, font: .preferredFont(forTextStyle: .body)))
    ]

    func highlight(_ text: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        for (regex, style) in patterns {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                mutable.addAttribute(.foregroundColor, value: style.color, range: range)
                if let font = style.font {
                    mutable.addAttribute(.font, value: font, range: range)
                }
            }
        }
        return AttributedString(mutable)
    }
}
