import SwiftUI

/// Màn hình chính — gọn: logo + tài khoản, 3 số liệu, 4 chức năng chính.
struct HomeView: View {
    @EnvironmentObject private var auth: TikTokAuthManager
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var web: TikTokWebService

    private var friendsCount: Int { storage.following.filter { $0.status == .friend }.count }
    private var notBackCount: Int { storage.following.filter { $0.status == .notFollowingBack }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    statsRow
                    actions
                    footnote
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
        VStack(spacing: 8) {
            AppLogoImage(size: 72)
            Text("@\(auth.username.isEmpty ? storage.savedUsername : auth.username)")
                .font(.title2.bold())
            Label(auth.isLoggedIn ? "Đã đăng nhập TikTok" : "Chưa đăng nhập", systemImage: auth.isLoggedIn ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(auth.isLoggedIn ? .green : .orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatChip(title: "Đang follow", value: "\(storage.following.count)")
            StatChip(title: "Bạn bè", value: "\(friendsCount)")
            StatChip(title: "Không follow lại", value: "\(notBackCount)")
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: FollowingListView()) {
                ActionRow(icon: "person.3.fill", title: "Quét Following", subtitle: "Quét danh sách, phân loại bạn bè / không follow lại")
            }
            NavigationLink(destination: UnfollowView()) {
                ActionRow(icon: "person.badge.minus.fill", title: "Huỷ follow", subtitle: "Huỷ người đã chọn, hoặc huỷ tất cả trừ bạn bè + giữ lại")
            }
            NavigationLink(destination: RepostView()) {
                ActionRow(icon: "repeat.circle.fill", title: "Xoá bài đăng lại", subtitle: "Quét tab Reposts và gỡ từng video")
            }
            NavigationLink(destination: ExtraToolsView()) {
                ActionRow(icon: "ellipsis.circle.fill", title: "Công cụ thêm", subtitle: "Bỏ thích, xoá video của mình, thống kê")
            }
        }
    }

    private var footnote: some View {
        Text("Huỷ follow / gỡ repost hàng loạt có thể khiến TikTok giới hạn tạm thời. Chạy Dry-run trước, mỗi phiên tối đa 30 người, delay 5–12 giây. Thao tác không hoàn tác được.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }
}

struct StatChip: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ActionRow: View {
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
        .background(Color(.secondarySystemBackground))
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
