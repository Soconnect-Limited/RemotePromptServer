import SwiftUI

struct SyntaxHighlightedTextEditor: View {
    @Binding var text: String
    let highlighter = MarkdownHighlighter()

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .padding(4)
                .opacity(0.05) // keep cursor & editing
            ScrollView {
                Text(highlighter.highlight(text))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(.body, design: .monospaced))
    }
}

#Preview {
    SyntaxHighlightedTextEditor(text: .constant("# Title\n- item\n `code`"))
        .frame(height: 200)
}
