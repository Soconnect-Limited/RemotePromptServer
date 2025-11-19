import SwiftUI

struct RoomsListView: View {
    @StateObject private var viewModel = RoomsViewModel()
    @State private var showingCreateRoom = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.rooms.isEmpty && viewModel.isLoading {
                    ProgressView("ルームを読み込み中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.rooms.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("ルームがありません")
                            .font(.headline)
                        Text("右上のボタンから新しいルームを作成してください")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.rooms) { room in
                            NavigationLink(value: room) {
                                RoomRowView(room: room)
                            }
                        }
                        .onDelete(perform: deleteRooms)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Rooms")
            .navigationDestination(for: Room.self) { room in
                RoomDetailView(room: room)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateRoom = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await viewModel.loadRooms()
            }
            .refreshable {
                await viewModel.loadRooms()
            }
            .sheet(isPresented: $showingCreateRoom) {
                CreateRoomView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .alert("エラー", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func deleteRooms(at offsets: IndexSet) {
        Task {
            for index in offsets {
                guard viewModel.rooms.indices.contains(index) else { continue }
                let room = viewModel.rooms[index]
                _ = await viewModel.deleteRoom(room)
            }
        }
    }
}

#Preview {
    RoomsListView()
}
