import SwiftUI

/// Xoá bài đăng lại (Repost): quét tab Reposts rồi gỡ từng video.
/// Port logic từ `tiktok-unrepost/unrepost.py`.
struct RepostView: View {
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var web: TikTokWebService
    @EnvironmentObject private var cleaner: RepostCleaner

    @State private var showConfirm = false

    var pending: [RepostVideo] {
        storage.reposts.filter { !storage.processedRepostURLs.contains($0.url) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("App mở tab Reposts trên trang cá nhân của bạn, cuộn gom link video (`a[href*=\"/video/\"]`), rồi mở từng video và bấm nút repost (`button[data-e2e=\"repost-button\"]`) + xác nhận Remove / Gỡ — đúng logic tool Python unrepost.py.")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack {
                        Button("Quét tab Reposts") {
                            Task { await cleaner.scan(username: storage.savedUsername, web: web, storage: storage) }
                        }
                        .buttonStyle(.borderedProminent).tint(.pink)
                        .disabled(cleaner.isScanning || storage.savedUsername.isEmpty)

                        Toggle("Dry-run", isOn: Binding(
                            get: { storage.settings.dryRun },
                            set: { storage.settings.dryRun = $0; storage.saveSettings() }
                        ))
                    }

                    if cleaner.isScanning || cleaner.isRunning {
                        ProgressView(cleaner.progressText)
                    } else if !cleaner.progressText.isEmpty {
                        Text(cleaner.progressText).font(.footnote).foregroundStyle(.secondary)
                    }

                    Text("Tìm thấy \(storage.reposts.count) video • Còn \(pending.count) chưa xử lý • Đã gỡ \(storage.stats.totalRepostsRemoved)")
                        .font(.headline)

                    if cleaner.isRunning {
                        Text("Đã gỡ: \(cleaner.doneCount) • Thất bại: \(cleaner.failedCount) / \(cleaner.totalCount)")
                            .font(.footnote)
                        Button(role: .destructive) { cleaner.stop() } label: {
                            Label("DỪNG KHẨN CẤP", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.red)
                    } else {
                        Button { showConfirm = true } label: {
                            Label(storage.settings.dryRun ? "Dry-run gỡ repost" : "Bắt đầu gỡ repost",
                                  systemImage: "repeat.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.pink)
                        .disabled(pending.isEmpty)
                    }

                    Text("WebView TikTok:")
                        .font(.headline)
                    TikTokWebViewRepresentable(webView: web.webView)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }

            List {
                ForEach(pending) { video in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.url).font(.caption).lineLimit(2)
                        Text("Chưa xử lý").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Xoá bài đăng lại")
        .alert("Xác nhận gỡ repost", isPresented: $showConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Bắt đầu", role: .destructive) {
                cleaner.run(videos: pending, settings: storage.settings, web: web, storage: storage)
            }
        } message: {
            Text("Sẽ gỡ \(min(pending.count, storage.settings.clampedMaxPerSession)) video repost trong phiên này. Video gốc không bị xoá — chỉ gỡ khỏi mục đăng lại của bạn.")
        }
    }
}
