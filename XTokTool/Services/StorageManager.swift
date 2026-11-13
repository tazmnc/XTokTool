import Foundation

/// Lưu trữ cục bộ: danh sách Following (JSON), whitelist (UserDefaults),
/// nhật ký, thống kê và state đã xử lý (để chạy tiếp không trùng).
/// Không lưu mật khẩu / token TikTok ở đây — phiên đăng nhập nằm trong
/// WKHTTPCookieStore của WKWebView, do hệ thống quản lý.
@MainActor
final class StorageManager: ObservableObject {
    @Published var following: [TikTokUser] = []
    @Published var reposts: [RepostVideo] = []
    @Published var logs: [AppLog] = []
    @Published var keepList = KeepList()
    @Published var stats = AppStats()
    @Published var settings = RunSettings()
    @Published var processedUsernames: Set<String> = []
    @Published var processedRepostURLs: Set<String> = []

    private let followingFile = "following.json"
    private let repostsFile = "reposts.json"
    private let logsFile = "logs.json"
    private let statsFile = "stats.json"
    private let processedFile = "processed.json"
    private let keepKey = "xtoktool.keepList"
    private let settingsKey = "xtoktool.settings"
    private let usernameKey = "xtoktool.username"

    init() {
        loadAll()
    }

    // MARK: - Đường dẫn

    private func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func fileURL(_ name: String) -> URL { documentsURL().appendingPathComponent(name) }

    // MARK: - Load / Save chung

    private func loadJSON<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        let url = fileURL(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, to name: String) {
        let url = fileURL(name)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func loadAll() {
        following = loadJSON(followingFile, as: [TikTokUser].self) ?? []
        reposts = loadJSON(repostsFile, as: [RepostVideo].self) ?? []
        logs = loadJSON(logsFile, as: [AppLog].self) ?? []
        stats = loadJSON(statsFile, as: AppStats.self) ?? AppStats()
        if let raw: [String: [String]] = loadJSON(processedFile, as: [String: [String]].self) {
            processedUsernames = Set(raw["users"] ?? [])
            processedRepostURLs = Set(raw["reposts"] ?? [])
        }
        if let data = UserDefaults.standard.data(forKey: keepKey),
           let list = try? JSONDecoder().decode(KeepList.self, from: data) {
            keepList = list
        }
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(RunSettings.self, from: data) {
            settings = s
        }
    }

    // MARK: - Following / Repost

    func saveFollowing() { saveJSON(following, to: followingFile) }
    func saveReposts() { saveJSON(reposts, to: repostsFile) }

    func markUserProcessed(_ username: String) {
        processedUsernames.insert(username.lowercased())
        saveJSON(["users": Array(processedUsernames), "reposts": Array(processedRepostURLs)],
                 to: processedFile)
    }

    func markRepostProcessed(_ url: String) {
        processedRepostURLs.insert(url)
        saveJSON(["users": Array(processedUsernames), "reposts": Array(processedRepostURLs)],
                 to: processedFile)
    }

    // MARK: - Whitelist

    func saveKeepList() {
        if let data = try? JSONEncoder().encode(keepList) {
            UserDefaults.standard.set(data, forKey: keepKey)
        }
    }

    func addToKeepList(_ username: String) {
        keepList.add(username)
        saveKeepList()
        if let i = following.firstIndex(where: { $0.username.lowercased() == username.lowercased() }) {
            following[i].isKept = true
        }
    }

    func removeFromKeepList(_ username: String) {
        keepList.remove(username)
        saveKeepList()
        if let i = following.firstIndex(where: { $0.username.lowercased() == username.lowercased() }) {
            following[i].isKept = false
        }
    }

    /// Gợi ý giữ lại toàn bộ bạn bè (mutual) vào whitelist.
    func suggestKeepFriends() {
        for user in following where user.status == .friend {
            keepList.add(user.username)
        }
        saveKeepList()
        refreshKeptFlags()
    }

    func refreshKeptFlags() {
        for i in following.indices {
            following[i].isKept = keepList.contains(following[i].username)
        }
    }

    // MARK: - Settings / username

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    var savedUsername: String {
        get { UserDefaults.standard.string(forKey: usernameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }

    // MARK: - Log & thống kê

    func addLog(_ level: LogLevel, _ message: String) {
        logs.insert(AppLog(level: level, message: message), at: 0)
        if logs.count > 500 { logs = Array(logs.prefix(500)) }
        saveJSON(logs, to: logsFile)
    }

    func saveStats() { saveJSON(stats, to: statsFile) }

    func clearLogs() {
        logs = []
        saveJSON(logs, to: logsFile)
    }

    func resetProcessedState() {
        processedUsernames = []
        processedRepostURLs = []
        saveJSON(["users": [String](), "reposts": [String]()], to: processedFile)
    }
}
