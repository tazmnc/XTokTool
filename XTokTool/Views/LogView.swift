import SwiftUI

/// Nhật ký thao tác của app.
struct LogView: View {
    @EnvironmentObject private var storage: StorageManager
    @State private var showClearConfirm = false

    var body: some View {
        List {
            if storage.logs.isEmpty {
                Text("Chưa có log nào. Chạy quét / huỷ follow / gỡ repost để xem nhật ký tại đây.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(storage.logs) { log in
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.message).font(.footnote)
                    Text(log.timeText).font(.caption2).foregroundStyle(.secondary)
                }
                .listRowBackground(logBackground(for: log.level))
            }
        }
        .navigationTitle("Nhật ký")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Xoá log", role: .destructive) { showClearConfirm = true }
                    .disabled(storage.logs.isEmpty)
            }
        }
        .alert("Xoá toàn bộ nhật ký?", isPresented: $showClearConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Xoá", role: .destructive) { storage.clearLogs() }
        }
    }

    private func logBackground(for level: LogLevel) -> Color {
        switch level {
        case .success: return Color.green.opacity(0.08)
        case .warning: return Color.yellow.opacity(0.08)
        case .error: return Color.red.opacity(0.10)
        case .info: return Color.clear
        }
    }
}
