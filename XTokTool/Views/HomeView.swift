import SwiftUI

/// Màn hình chính: thống kê + điều hướng tới các chức năng.
struct HomeView: View {
    @EnvironmentObject private var auth: TikTokAuthManager
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var web: TikTokWebService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    statsGrid
                    menu
                    warningCard
                }
                .padding()
            }
            .navigationTitle("XTokTool")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: LogView()) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("👋 Xin chào")
                .font(.headline)
            Text("@\(auth.username.isEmpty ? storage.savedUsername : auth.username)")
                .font(.title2.bold())
                .foregroundStyle(.pink)
            Text(auth.isLoggedIn ? "Đã đăng nhập TikTok" : "Chưa đăng nhập — vào Đăng nhập để quét")
                .font(.caption)
                .foregroundStyle(auth.isLoggedIn ? .green : .orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statsGrid: some View {
        let s = storage.stats
        let friends = storage.following.filter { $0.status == .friend }.count
        let notBack = storage.following.filter { $0.status == .notFollowingBack }.count
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Đang follow", value: "\(storage.following.count)", icon: "person.2.fill")
            StatCard(title: "Bạn bè (mutual)", value: "\(friends)", icon: "person.2.circle.fill")
            StatCard(title: "Không follow lại", value: "\(notBack)", icon: "person.slash.fill")
            StatCard(title: "Đã huỷ follow", value: "\(s.totalUnfollowed)", icon: "person.badge.minus.fill")
            StatCard(title: "Đã gỡ repost", value: "\(s.totalRepostsRemoved)", icon: "arrow.uturn.backward.circle.fill")
            StatCard(title: "Video repost đã quét", value: "\(storage.reposts.count)", icon: "repeat.circle.fill")
        }
    }

    private var menu: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: FollowingListView()) {
                MenuRow(icon: "person.3.fill", title: "Danh sách Following", subtitle: "Quét, phân loại bạn bè / không follow lại, chọn & giữ lại")
            }
            NavigationLink(destination: UnfollowView()) {
                MenuRow(icon: "person.badge.minus.fill", title: "Huỷ follow", subtitle: "Huỷ người đã chọn, hoặc huỷ tất cả trừ bạn bè + whitelist")
            }
            NavigationLink(destination: RepostView()) {
                MenuRow(icon: "repeat.circle.fill", title: "Xoá bài đăng lại (Repost)", subtitle: "Quét tab Reposts và gỡ từng video")
            }
            NavigationLink(destination: ExtraToolsView()) {
                MenuRow(icon: "ellipsis.circle.fill", title: "Công cụ thêm", subtitle: "Bỏ thích video, xoá video của mình (xác nhận từng cái)")
            }
        }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Lưu ý an toàn", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.yellow)
            Text("Huỷ follow / gỡ repost hàng loạt có thể khiến TikTok giới hạn tạm thời hoặc khoá tài khoản. Hãy chạy Dry-run trước, giới hạn mỗi phiên 30 người, để delay 5–12 giây. Thao tác không hoàn tác được.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatCard: View {
    var title: String
    var value: String
    var icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(.pink)
            Text(value).font(.title.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct MenuRow: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.pink)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Công cụ thêm: khung UI + logic cơ bản, ghi rõ trạng thái từng mục.
struct ExtraToolsView: View {
    @EnvironmentObject private var web: TikTokWebService
    @EnvironmentObject private var storage: StorageManager
    @State private var unlikeStatus = "Chưa chạy. Mở video đã like trong WebView rồi bấm Bỏ thích — mỗi video cần xác nhận riêng."
    @State private var showDeleteWarning = false

    var body: some View {
        List {
            Section("Bỏ thích video đã like (Unlike)") {
                Text("Trạng thái: khung logic đã có (selector `button[data-e2e=\"like-button\"]`). TikTok hay đổi giao diện trang Liked, nên trước khi chạy loạt hãy mở 1 video đã like và kiểm tra nút Like có bấm được không.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(unlikeStatus).font(.footnote)
                Button("Thử bỏ thích video đang mở") {
                    Task {
                        let result = await web.evaluateString(TikTokWebService.unlikeJS)
                        unlikeStatus = "Kết quả: \(result ?? "không rõ")"
                        if result == "clicked" {
                            storage.stats.totalUnliked += 1
                            storage.saveStats()
                            storage.addLog(.success, "Đã bỏ thích 1 video.")
                        }
                    }
                }
            }
            Section("Xoá video của mình") {
                Text("Trạng thái: CHƯA tự động hàng loạt. Xoá video là thao tác nguy hiểm, không hoàn tác — app chỉ hỗ trợ mở video của bạn trong WebView để bạn tự xác nhận xoá từng cái.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Mở trang cá nhân để xoá thủ công") {
                    showDeleteWarning = true
                    web.loadProfilePage(username: storage.savedUsername)
                }
            }
            Section("Thống kê") {
                Text("Đang follow: \(storage.following.count)")
                Text("Bạn bè: \(storage.following.filter { $0.status == .friend }.count)")
                Text("Không follow lại: \(storage.following.filter { $0.status == .notFollowingBack }.count)")
                Text("Đã huỷ: \(storage.stats.totalUnfollowed) • Đã gỡ repost: \(storage.stats.totalRepostsRemoved) • Đã bỏ thích: \(storage.stats.totalUnliked)")
                if let d = storage.stats.lastScanDate {
                    Text("Lần quét cuối: \(d.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .navigationTitle("Công cụ thêm")
        .alert("Xoá video không hoàn tác được", isPresented: $showDeleteWarning) {
            Button("Tôi hiểu", role: .cancel) {}
        } message: {
            Text("App chỉ mở trang cá nhân của bạn. Hãy tự mở từng video và xoá — đừng xoá hàng loạt.")
        }
    }
}
