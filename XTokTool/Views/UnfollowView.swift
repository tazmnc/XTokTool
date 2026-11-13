import SwiftUI

/// Huỷ follow: 2 chế độ + dry-run + giới hạn + delay + dừng khẩn cấp.
struct UnfollowView: View {
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var web: TikTokWebService
    @EnvironmentObject private var engine: UnfollowEngine

    @State private var showConfirm = false
    @State private var showWarning = false

    var targets: [TikTokUser] {
        engine.targets(from: storage.following,
                       settings: storage.settings,
                       keepList: storage.keepList,
                       processed: storage.processedUsernames)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                warningBox

                VStack(alignment: .leading, spacing: 10) {
                    Text("Chế độ huỷ").font(.headline)
                    Picker("Chế độ", selection: Binding(
                        get: { storage.settings.unfollowAllExceptFriendsAndKeep },
                        set: { storage.settings.unfollowAllExceptFriendsAndKeep = $0; storage.saveSettings() }
                    )) {
                        Text("Huỷ những người đã chọn").tag(false)
                        Text("Huỷ tất cả trừ bạn bè + giữ lại").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(storage.settings.unfollowAllExceptFriendsAndKeep
                         ? "Sẽ huỷ mọi người trong Following TRỪ bạn bè (mutual) và những người trong danh sách Giữ lại."
                         : "Chỉ huỷ những người bạn đã tick chọn trong màn Danh sách Following.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                settingsBox

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sẽ huỷ: \(targets.count) người (đã trừ \(storage.processedUsernames.count) người xử lý trước đó)")
                        .font(.headline)
                    if !targets.isEmpty {
                        Text(targets.prefix(10).map { "@\($0.username)" }.joined(separator: ", ")
                             + (targets.count > 10 ? " … (+\(targets.count - 10) người nữa)" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Chưa có ai để huỷ — quét Following và chọn người, hoặc bật chế độ huỷ tất cả.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if engine.isRunning {
                    ProgressView(engine.progressText).padding(.vertical)
                    Text("Đã huỷ: \(engine.doneCount) • Thất bại: \(engine.failedCount) / \(engine.totalCount)")
                        .font(.footnote)
                    Button(role: .destructive) { engine.stop() } label: {
                        Label("DỪNG KHẨN CẤP", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                } else {
                    if !engine.progressText.isEmpty {
                        Text(engine.progressText).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { showConfirm = true } label: {
                        Label(storage.settings.dryRun ? "Chạy Dry-run (chỉ liệt kê)" : "Bắt đầu huỷ follow",
                              systemImage: "person.badge.minus.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(targets.isEmpty)
                }

                Text("WebView TikTok (để xem thao tác đang chạy):")
                    .font(.headline)
                TikTokWebViewRepresentable(webView: web.webView)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle("Huỷ follow")
        .alert("Xác nhận huỷ follow", isPresented: $showConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Bắt đầu", role: .destructive) {
                engine.run(targets: targets, settings: storage.settings, web: web, storage: storage)
            }
        } message: {
            Text("Sẽ huỷ \(min(targets.count, storage.settings.clampedMaxPerSession)) người trong phiên này (giới hạn \(storage.settings.clampedMaxPerSession)). Thao tác KHÔNG hoàn tác được. Bạn bè và danh sách Giữ lại sẽ không bị huỷ.")
        }
    }

    private var warningBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Cảnh báo", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.yellow)
            Text("Huỷ hàng loạt có thể bị TikTok giới hạn / khoá tạm tài khoản. Chạy Dry-run trước, mỗi phiên tối đa 30 người, delay 5–12 giây, nghỉ 60 giây sau mỗi 15 người.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var settingsBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Dry-run (chỉ liệt kê, không huỷ thật)", isOn: Binding(
                get: { storage.settings.dryRun },
                set: { storage.settings.dryRun = $0; storage.saveSettings() }
            ))
            HStack {
                Text("Giới hạn mỗi phiên")
                Spacer()
                Stepper("\(storage.settings.maxPerSession) người", value: Binding(
                    get: { storage.settings.maxPerSession },
                    set: { storage.settings.maxPerSession = min(max($0, 1), 100); storage.saveSettings() }
                ), in: 1...100)
            }
            HStack {
                Text("Delay giữa 2 người")
                Spacer()
                Text("\(Int(storage.settings.delayMin))–\(Int(storage.settings.delayMax)) giây")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Nghỉ dài sau mỗi")
                Spacer()
                Stepper("\(storage.settings.pauseEvery) người / \(Int(storage.settings.pauseSeconds))s", value: Binding(
                    get: { storage.settings.pauseEvery },
                    set: { storage.settings.pauseEvery = $0; storage.saveSettings() }
                ), in: 0...50)
            }
        }
        .font(.footnote)
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
