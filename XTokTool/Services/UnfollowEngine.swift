import Foundation

/// Engine huỷ follow.
///
/// Hai chế độ:
///  (a) Huỷ những người đã chọn trong danh sách.
///  (b) Huỷ tất cả TRỪ bạn bè (mutual) + whitelist.
///
/// An toàn: dry-run, giới hạn mỗi phiên (mặc định 30, tối đa 100),
/// delay ngẫu nhiên 5–12 giây, nghỉ dài 60 giây sau mỗi 15 người,
/// nút Dừng khẩn cấp (Task.cancel), lưu state đã xử lý để chạy tiếp
/// không trùng. Huỷ hàng loạt có thể khiến TikTok giới hạn / khoá tạm
/// tài khoản — app luôn cảnh báo trước khi chạy và không hoàn tác được.
@MainActor
final class UnfollowEngine: ObservableObject {
    @Published var isRunning = false
    @Published var progressText = ""
    @Published var doneCount = 0
    @Published var failedCount = 0
    @Published var totalCount = 0

    private var task: Task<Void, Never>?

    var canStop: Bool { isRunning }

    func stop() {
        task?.cancel()
        isRunning = false
        progressText = "Đã dừng theo yêu cầu."
    }

    /// Tính danh sách đích theo chế độ đã chọn.
    func targets(from following: [TikTokUser],
                 settings: RunSettings,
                 keepList: KeepList,
                 processed: Set<String>) -> [TikTokUser] {
        let pending = following.filter { !processed.contains($0.username.lowercased()) }
        if settings.unfollowAllExceptFriendsAndKeep {
            return pending.filter { user in
                user.status != .friend && !keepList.contains(user.username) && !user.isKept
            }
        } else {
            return pending.filter { $0.isSelected && !keepList.contains($0.username) && !$0.isKept }
        }
    }

    func run(targets allTargets: [TikTokUser],
             settings: RunSettings,
             web: TikTokWebService,
             storage: StorageManager) {
        guard !isRunning else { return }
        let limit = settings.clampedMaxPerSession
        let targets = Array(allTargets.prefix(limit))
        totalCount = targets.count
        doneCount = 0
        failedCount = 0
        isRunning = true

        if settings.dryRun {
            progressText = "Dry-run: sẽ huỷ \(targets.count) người (không thao tác thật)."
            storage.addLog(.info, "Dry-run huỷ follow: \(targets.count) người — \(targets.map(\.username).joined(separator: ", "))")
            isRunning = false
            return
        }

        task = Task { [weak self] in
            guard let self else { return }
            // Thử huỷ bằng API trước (nhẹ, không cần mở trang từng người).
            // Chỉ bật khi có ít nhất 1 người đã có userId (lấy từ lần quét API).
            let api = TikTokAPI(web: web)
            var apiReady = false
            if targets.contains(where: { $0.userId != nil }) {
                await api.ensureLoaded(username: storage.savedUsername)
                apiReady = true
            }
            for (index, user) in targets.enumerated() {
                if Task.isCancelled { break }
                self.progressText = "Đang huỷ [\(index + 1)/\(targets.count)] @\(user.username)…"
                var ok = false
                if apiReady, let uid = user.userId {
                    ok = await api.unfollow(userId: uid)
                    if !ok {
                        storage.addLog(.info, "API không huỷ được @\(user.username) — thử bằng cách bấm trên trang.")
                    }
                }
                if !ok {
                    // Fallback: mở trang following rồi bấm huỷ trong WebView.
                    web.loadFollowingPage(username: storage.savedUsername)
                    await web.wait(seconds: 3)
                    ok = await web.unfollow(username: user.username)
                }
                if ok {
                    self.doneCount += 1
                    storage.markUserProcessed(user.username)
                    storage.stats.totalUnfollowed += 1
                    storage.addLog(.success, "Đã huỷ follow @\(user.username)")
                } else {
                    self.failedCount += 1
                    storage.addLog(.warning, "Không huỷ được @\(user.username) (không tìm thấy nút / đã huỷ trước đó)")
                }
                storage.saveStats()

                // Nghỉ dài sau mỗi N người.
                if settings.pauseEvery > 0,
                   (index + 1) % settings.pauseEvery == 0,
                   index + 1 < targets.count {
                    self.progressText = "Nghỉ dài \(Int(settings.pauseSeconds)) giây để tránh bị gắn cờ…"
                    storage.addLog(.info, "Nghỉ dài \(Int(settings.pauseSeconds))s sau \(index + 1) người.")
                    await web.wait(seconds: settings.pauseSeconds)
                }
                // Delay ngẫu nhiên giữa 2 người.
                let delay = Double.random(in: settings.delayMin...settings.delayMax)
                await web.wait(seconds: delay)
                if Task.isCancelled { break }
            }
            self.isRunning = false
            self.progressText = "Xong: thành công \(self.doneCount), thất bại \(self.failedCount) / \(targets.count)."
            storage.stats.lastRunDate = Date()
            storage.saveStats()
            storage.addLog(.info, "Kết thúc phiên huỷ follow: thành công \(self.doneCount), thất bại \(self.failedCount).")
        }
    }
}
