import Foundation
import UIKit

struct MarkdownHighlighter {
    struct Style {
        let color: UIColor
        let font: UIFont?
        let isBold: Bool
        let isItalic: Bool

        init(color: UIColor, font: UIFont? = nil, isBold: Bool = false, isItalic: Bool = false) {
            self.color = color
            self.font = font
            self.isBold = isBold
            self.isItalic = isItalic
        }
    }

    enum Pattern {
        case h1, h2, h3, h4, h5, h6
        case codeBlock, inlineCode
        case bold, italic, boldItalic
        case link, image
        case listItem, orderedListItem
        case blockquote
        case horizontalRule

        var regex: NSRegularExpression {
            let pattern: String
            let options: NSRegularExpression.Options

            switch self {
            case .h1: pattern = "^# (.+)$"; options = [.anchorsMatchLines]
            case .h2: pattern = "^## (.+)$"; options = [.anchorsMatchLines]
            case .h3: pattern = "^### (.+)$"; options = [.anchorsMatchLines]
            case .h4: pattern = "^#### (.+)$"; options = [.anchorsMatchLines]
            case .h5: pattern = "^##### (.+)$"; options = [.anchorsMatchLines]
            case .h6: pattern = "^###### (.+)$"; options = [.anchorsMatchLines]
            case .codeBlock: pattern = "```[\\s\\S]*?```"; options = [.dotMatchesLineSeparators]
            case .inlineCode: pattern = "`[^`\n]+`"; options = []
            case .boldItalic: pattern = "\\*\\*\\*[^*\n]+\\*\\*\\*|___[^_\n]+___"; options = []
            case .bold: pattern = "\\*\\*[^*\n]+\\*\\*|__[^_\n]+__"; options = []
            case .italic: pattern = "\\*[^*\n]+\\*|_[^_\n]+_"; options = []
            case .link: pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"; options = []
            case .image: pattern = "!\\[([^\\]]*)\\]\\(([^)]+)\\)"; options = []
            case .listItem: pattern = "^[\\*\\-\\+] .+$"; options = [.anchorsMatchLines]
            case .orderedListItem: pattern = "^\\d+\\. .+$"; options = [.anchorsMatchLines]
            case .blockquote: pattern = "^> .+$"; options = [.anchorsMatchLines]
            case .horizontalRule: pattern = "^(---|\\*\\*\\*|___)\\s*$"; options = [.anchorsMatchLines]
            }

            return try! NSRegularExpression(pattern: pattern, options: options)
        }

        var style: Style {
            let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize

            switch self {
            case .h1:
                return Style(color: .systemBlue, font: .systemFont(ofSize: baseSize * 1.8, weight: .bold), isBold: true)
            case .h2:
                return Style(color: .systemBlue, font: .systemFont(ofSize: baseSize * 1.6, weight: .bold), isBold: true)
            case .h3:
                return Style(color: .systemBlue, font: .systemFont(ofSize: baseSize * 1.4, weight: .bold), isBold: true)
            case .h4:
                return Style(color: .systemBlue, font: .systemFont(ofSize: baseSize * 1.2, weight: .semibold), isBold: true)
            case .h5:
                return Style(color: .systemBlue, font: .systemFont(ofSize: baseSize * 1.1, weight: .semibold), isBold: true)
            case .h6:
                return Style(color: .systemBlue, font: .systemFont(ofSize: baseSize, weight: .semibold), isBold: true)
            case .codeBlock, .inlineCode:
                return Style(color: .systemOrange, font: UIFont.monospacedSystemFont(ofSize: baseSize * 0.95, weight: .regular))
            case .boldItalic:
                return Style(color: .systemPurple, font: .systemFont(ofSize: baseSize, weight: .bold), isBold: true, isItalic: true)
            case .bold:
                return Style(color: .systemPurple, font: .boldSystemFont(ofSize: baseSize), isBold: true)
            case .italic:
                return Style(color: .systemPurple, font: .italicSystemFont(ofSize: baseSize), isItalic: true)
            case .link:
                return Style(color: .systemTeal, font: .systemFont(ofSize: baseSize))
            case .image:
                return Style(color: .systemIndigo, font: .systemFont(ofSize: baseSize))
            case .listItem, .orderedListItem:
                return Style(color: .systemGreen, font: .systemFont(ofSize: baseSize))
            case .blockquote:
                return Style(color: .systemGray, font: .italicSystemFont(ofSize: baseSize), isItalic: true)
            case .horizontalRule:
                return Style(color: .systemGray2, font: .systemFont(ofSize: baseSize))
            }
        }
    }

    func highlight(_ text: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        // Reset to default styling
        mutable.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        mutable.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: fullRange)

        // Apply patterns in priority order (most specific first)
        let orderedPatterns: [Pattern] = [
            .codeBlock,
            .boldItalic,
            .bold,
            .italic,
            .h1, .h2, .h3, .h4, .h5, .h6,
            .image,
            .link,
            .orderedListItem,
            .listItem,
            .blockquote,
            .horizontalRule,
            .inlineCode
        ]

        for pattern in orderedPatterns {
            let regex = pattern.regex
            let style = pattern.style

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
