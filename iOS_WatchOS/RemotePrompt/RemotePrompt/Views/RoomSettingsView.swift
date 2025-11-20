import SwiftUI

struct RoomSettingsView: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("設定機能は現在開発中です")
                    .font(.headline)
                Text("Room: \(room.name)")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    RoomSettingsView(room: Room(
        id: UUID().uuidString,
        name: "Preview Room",
        workspacePath: "/tmp",
        icon: "📁",
        deviceId: "device",
        createdAt: Date(),
        updatedAt: Date()
    ))
}
