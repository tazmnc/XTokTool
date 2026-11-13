import Foundation

// MARK: - Người dùng TikTok trong danh sách Following

enum FollowStatus: String, Codable, CaseIterable {
    case friend = "friend"           // Bạn bè: follow lẫn nhau (mutual)
    case notFollowingBack = "notFollowingBack" // Không follow lại mình
    case followingMe = "followingMe" // Đang follow mình (chưa rõ chiều ngược lại)
    case unknown = "unknown"

    var label: String {
        switch self {
        case .friend: return "Bạn bè"
        case .notFollowingBack: return "Không follow lại"
        case .followingMe: return "Đang follow mình"
        case .unknown: return "Chưa rõ"
        }
    }
}

struct TikTokUser: Identifiable, Codable, Equatable, Hashable {
    var id: String { username } // username là khoá duy nhất
    var username: String        // không có @
    var displayName: String
    var avatarURL: String?
    var isVerified: Bool
    var status: FollowStatus
    var isKept: Bool = false    // nằm trong danh sách Giữ lại (whitelist)
    var isSelected: Bool = false
    var profileURL: String { "https://www.tiktok.com/@\(username)" }

    static func == (lhs: TikTokUser, rhs: TikTokUser) -> Bool {
        lhs.username == rhs.username
    }
    func hash(into hasher: inout Hasher) { hasher.combine(username) }
}

// MARK: - Video đã repost

struct RepostVideo: Identifiable, Codable, Equatable {
    var id: String { url }
    var url: String
    var authorUsername: String?
    var title: String?
    var isProcessed: Bool = false
}

// MARK: - Nhật ký thao tác

enum LogLevel: String, Codable {
    case info, success, warning, error
}

struct AppLog: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var level: LogLevel
    var message: String

    var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss dd/MM/yyyy"
        f.locale = Locale(identifier: "vi_VN")
        return f.string(from: date)
    }
}

// MARK: - Danh sách Giữ lại (whitelist)

struct KeepList: Codable {
    var usernames: Set<String> = []

    func contains(_ username: String) -> Bool {
        usernames.contains(username.lowercased())
    }
    mutating func add(_ username: String) {
        usernames.insert(username.lowercased().trimmingCharacters(in: .whitespaces))
    }
    mutating func remove(_ username: String) {
        usernames.remove(username.lowercased())
    }
}

// MARK: - Thống kê

struct AppStats: Codable {
    var totalFollowing: Int = 0
    var totalFriends: Int = 0
    var totalNotFollowingBack: Int = 0
    var totalUnfollowed: Int = 0
    var totalRepostsRemoved: Int = 0
    var totalUnliked: Int = 0
    var lastScanDate: Date?
    var lastRunDate: Date?
}

// MARK: - Cài đặt chạy

struct RunSettings: Codable {
    var dryRun: Bool = false
    var maxPerSession: Int = 30        // mặc định 30, tối đa 100
    var delayMin: Double = 5           // giây
    var delayMax: Double = 12          // giây
    var pauseEvery: Int = 15           // cứ N người thì nghỉ dài
    var pauseSeconds: Double = 60
    var unfollowAllExceptFriendsAndKeep: Bool = false
    var clientKey: String = ""         // TikTok Client Key tuỳ chọn, mặc định trống

    var clampedMaxPerSession: Int { min(max(maxPerSession, 1), 100) }
}
