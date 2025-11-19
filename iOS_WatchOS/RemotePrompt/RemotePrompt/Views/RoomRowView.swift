import SwiftUI

struct RoomRowView: View {
    let room: Room

    var body: some View {
        HStack(spacing: 12) {
            Text(room.icon.isEmpty ? "📁" : room.icon)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                Text(room.workspacePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RoomRowView(
        room: Room(
            id: UUID().uuidString,
            name: "RemotePrompt",
            workspacePath: "/Users/macstudio/Projects/RemotePrompt",
            icon: "📁",
            deviceId: "device",
            createdAt: Date(),
            updatedAt: Date()
        )
    )
    .previewLayout(.sizeThatFits)
}
