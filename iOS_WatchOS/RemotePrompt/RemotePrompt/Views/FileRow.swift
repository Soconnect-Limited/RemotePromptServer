import SwiftUI

struct FileRow: View {
    let item: FileItem

    private var iconName: String {
        switch item.type {
        case .directory:
            return "folder.fill"
        case .markdownFile:
            return "doc.text.fill"
        case .pdfFile:
            return "doc.richtext.fill"
        }
    }

    private var iconColor: Color {
        switch item.type {
        case .directory:
            return .blue
        case .markdownFile:
            return .green
        case .pdfFile:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let size = item.size, item.type != .directory {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(relativeDate(for: item.modifiedAt))
                    .font(.footnote)
                    .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func relativeDate(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    FileRow(item: FileItem(
        id: "Docs/README.md",
        name: "README.md",
        type: .markdownFile,
        path: "Docs/README.md",
        size: 5234,
        modifiedAt: Date().addingTimeInterval(-3600)
    ))
    .padding()
}
