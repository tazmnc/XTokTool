import Foundation

/// Gỡ video đã repost — port logic từ tool Python
/// `tiktok-unrepost/unrepost.py` (12/10/2026) sang Swift + WKWebView:
///  1. Mở trang cá nhân → bấm tab Reposts (`data-e2e="reposts-tab"`).
///  2. Cuộn trang, gom link `a[href*="/video/"]` dạng /@user/video/<id>.
///  3. Mở từng video, bấm `button[data-e2e="repost-button"]` rồi xác nhận
///     "Remove" / "Gỡ" trong hộp thoại.
///  4. Dry-run, giới hạn, delay, log, lưu state để chạy tiếp không trùng.
@MainActor
final class RepostCleaner: ObservableObject {
    @Published var isRunning = false
    @Published var isScanning = false
    @Published var progressText = ""
    @Published var doneCount = 0
    @Published var failedCount = 0
    @Published var totalCount = 0

    private var task: Task<Void, Never>?

    func stop() {
        task?.cancel()
        isRunning = false
        progressText = "Đã dừng theo yêu cầu."
    }

    // MARK: - Quét tab Reposts

    func scan(username: String, web: TikTokWebService, storage: StorageManager) async {
        guard !isScanning else { return }
        isScanning = true
        progressText = "Đang mở tab Reposts của @\(username)…"
        // Cách 1 (mới): liệt kê repost bằng API (JSON thuần, không cuộn trang).
        let api = TikTokAPI(web: web)
        await api.ensureLoaded(username: username)
        if let secUid = await api.getSecUid(username: username),
           let videos = await api.fetchReposts(secUid: secUid) {
            let fresh = videos.filter { !storage.processedRepostURLs.contains($0.url) }
            storage.reposts = fresh
            storage.saveReposts()
            storage.addLog(.info, "Quét Reposts bằng API: tìm thấy \(videos.count) video, còn \(fresh.count) chưa xử lý.")
            progressText = "Tìm thấy \(videos.count) video repost (\(fresh.count) chưa xử lý)."
            isScanning = false
            return
        }
        // Cách 2 (fallback): quét DOM như trước.
        web.loadProfilePage(username: username)
        await web.wait(seconds: 4)
        let tabResult = await web.evaluateString(TikTokWebService.openRepostsTabJS)
        if tabResult != "clicked" {
            storage.addLog(.warning, "Không tìm thấy tab Reposts — có thể tài khoản để riêng tư hoặc TikTok đổi giao diện.")
        }
        await web.wait(seconds: 3)
        progressText = "Đang cuộn và gom link video repost…"
        let found = await web.collectRepostLinks(maxScrolls: 30)
        let fresh = found.filter { !storage.processedRepostURLs.contains($0.url) }
        storage.reposts = fresh
        storage.saveReposts()
        storage.addLog(.info, "Quét Reposts: tìm thấy \(found.count) video, còn \(fresh.count) chưa xử lý.")
        progressText = "Tìm thấy \(found.count) video repost (\(fresh.count) chưa xử lý)."
        isScanning = false
    }

    // MARK: - Gỡ hàng loạt

    func run(videos: [RepostVideo],
             settings: RunSettings,
             web: TikTokWebService,
             storage: StorageManager) {
        guard !isRunning else { return }
        let limit = settings.clampedMaxPerSession
        let targets = Array(videos.prefix(limit))
        totalCount = targets.count
        doneCount = 0
        failedCount = 0
        isRunning = true

        if settings.dryRun {
            progressText = "Dry-run: sẽ gỡ \(targets.count) video repost (không thao tác thật)."
            storage.addLog(.info, "Dry-run gỡ repost: \(targets.count) video.")
            isRunning = false
            return
        }

        task = Task { [weak self] in
            guard let self else { return }
            for (index, video) in targets.enumerated() {
                if Task.isCancelled { break }
                self.progressText = "Đang gỡ [\(index + 1)/\(targets.count)] \(video.url)"
                let ok = await web.removeRepost(at: video.url)
                if ok {
                    self.doneCount += 1
                    storage.markRepostProcessed(video.url)
                    storage.stats.totalRepostsRemoved += 1
                    storage.addLog(.success, "Đã gỡ repost: \(video.url)")
                } else {
                    self.failedCount += 1
                    storage.addLog(.warning, "Không gỡ được repost (video đã xoá / riêng tư / không thấy nút): \(video.url)")
                }
                storage.saveStats()

                if settings.pauseEvery > 0,
                   (index + 1) % settings.pauseEvery == 0,
                   index + 1 < targets.count {
                    self.progressText = "Nghỉ dài \(Int(settings.pauseSeconds)) giây…"
                    await web.wait(seconds: settings.pauseSeconds)
                }
                let delay = Double.random(in: settings.delayMin...settings.delayMax)
                await web.wait(seconds: delay)
                if Task.isCancelled { break }
            }
            self.isRunning = false
            self.progressText = "Xong: gỡ thành công \(self.doneCount), thất bại \(self.failedCount) / \(targets.count)."
            storage.stats.lastRunDate = Date()
            storage.saveStats()
            storage.addLog(.info, "Kết thúc phiên gỡ repost: thành công \(self.doneCount), thất bại \(self.failedCount).")
        }
    }
}
