import SwiftUI
#if canImport(MarkdownUI)
import MarkdownUI
#endif

struct MarkdownView: View {
    let content: String

    var body: some View {
#if canImport(MarkdownUI)
        Markdown(content)
            .markdownTheme(.gitHub)
            .markdownTextStyle(
                .init(
                    font: .system(.body, design: .rounded),
                    foregroundColor: .primary
                )
            )
#else
        ScrollView(.horizontal, showsIndicators: false) {
            Text(MarkdownRenderer.render(content))
                .font(.system(.body, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
#endif
    }
}
