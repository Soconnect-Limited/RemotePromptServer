import SwiftUI

struct RoomRowView: View {
    let room: Room

    var body: some View {
        HStack(spacing: 12) {
            // v4.3.2: 未読バッジ（スレッドと同じ位置に表示）
            if room.unreadCount > 0 {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 20, height: 20)
                    Text("\(room.unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }

            Text(room.icon.isEmpty ? "📁" : room.icon)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .fontWeight(room.unreadCount > 0 ? .bold : .regular)
                Text(room.workspacePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("roomRow.\(room.id)")
    }
}

#Preview("No Unread") {
    RoomRowView(
        room: Room(
            id: UUID().uuidString,
            name: "RemotePrompt",
            workspacePath: "/Users/macstudio/Projects/RemotePrompt",
            icon: "📁",
            deviceId: "device",
            unreadCount: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    )
}

#Preview("With Unread") {
    RoomRowView(
        room: Room(
            id: UUID().uuidString,
            name: "RemotePrompt",
            workspacePath: "/Users/macstudio/Projects/RemotePrompt",
            icon: "📁",
            deviceId: "device",
            unreadCount: 3,
            createdAt: Date(),
            updatedAt: Date()
        )
    )
}
