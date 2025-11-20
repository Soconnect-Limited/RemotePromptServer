import SwiftUI
import UIKit

struct SyntaxHighlightedTextEditor: UIViewRepresentable {
    @Binding var text: String
    let highlighter = MarkdownHighlighter()

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        textView.backgroundColor = .systemBackground
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.isEditable = true
        textView.isScrollEnabled = true
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update if text changed from outside (not from user typing)
        if uiView.text != text {
            let attributedText = NSMutableAttributedString(highlighter.highlight(text))

            // Preserve cursor position
            let selectedRange = uiView.selectedRange
            uiView.attributedText = attributedText

            // Restore cursor position if valid
            if selectedRange.location <= attributedText.length {
                uiView.selectedRange = selectedRange
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxHighlightedTextEditor

        init(_ parent: SyntaxHighlightedTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // Update the binding
            parent.text = textView.text

            // Apply syntax highlighting
            let attributedText = NSMutableAttributedString(parent.highlighter.highlight(textView.text))

            // Preserve cursor position
            let selectedRange = textView.selectedRange
            textView.attributedText = attributedText

            // Restore cursor position
            if selectedRange.location <= attributedText.length {
                textView.selectedRange = selectedRange
            }
        }
    }
}

#Preview {
    SyntaxHighlightedTextEditor(text: .constant("# Title\n- item\n `code`"))
        .frame(height: 200)
}
