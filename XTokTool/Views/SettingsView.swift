import SwiftUI

/// Cài đặt + Giới thiệu (About) — ghi credit Dev: MinhTaz.
struct SettingsView: View {
    @EnvironmentObject private var auth: TikTokAuthManager
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var web: TikTokWebService

    @State private var showLogoutConfirm = false
    @State private var showResetConfirm = false
    @State private var savedMessage = ""

    var body: some View {
        List {
            Section("Tài khoản TikTok") {
                Text("Username: @\(storage.savedUsername.isEmpty ? "—" : storage.savedUsername)")
                Text("Trạng thái: \(auth.isLoggedIn ? "Đã đăng nhập" : "Chưa đăng nhập")")
                Button("Kiểm tra lại phiên đăng nhập") {
                    Task {
                        await auth.checkLoginState(using: web.cookieStore)
                        savedMessage = auth.isLoggedIn ? "Phiên đăng nhập vẫn còn hiệu lực." : "Phiên đã hết — đăng nhập lại."
                    }
                }
                Button("Đăng xuất (xoá cookie TikTok)", role: .destructive) {
                    showLogoutConfirm = true
                }
            }

            Section("TikTok Login Kit (tuỳ chọn)") {
                Text("Mặc định app dùng Web Login — không cần Client Key. Chỉ nhập Client Key nếu bạn đã đăng ký app trên TikTok Developers và muốn dùng Login Kit OAuth.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("TikTok Client Key (để trống = Web Login)", text: Binding(
                    get: { storage.settings.clientKey },
                    set: { storage.settings.clientKey = $0; storage.saveSettings() }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Text(storage.settings.clientKey.isEmpty
                     ? "Đang dùng: Web Login qua tiktok.com/login"
                     : "Đã nhập Client Key — Login Kit OAuth sẵn sàng (key chỉ lưu trên máy bạn).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Giới hạn & delay") {
                Stepper("Tối đa mỗi phiên: \(storage.settings.maxPerSession) (tối đa 100)", value: Binding(
                    get: { storage.settings.maxPerSession },
                    set: { storage.settings.maxPerSession = min(max($0, 1), 100); storage.saveSettings() }
                ), in: 1...100)
                Stepper("Nghỉ dài sau mỗi: \(storage.settings.pauseEvery) người", value: Binding(
                    get: { storage.settings.pauseEvery },
                    set: { storage.settings.pauseEvery = $0; storage.saveSettings() }
                ), in: 0...50)
                Text("Delay ngẫu nhiên giữa 2 thao tác: \(Int(storage.settings.delayMin))–\(Int(storage.settings.delayMax)) giây (mặc định 5–12s).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Dữ liệu") {
                Button("Đặt lại state đã xử lý (chạy lại từ đầu)") {
                    showResetConfirm = true
                }
                Text("Đã xử lý: \(storage.processedUsernames.count) người • \(storage.processedRepostURLs.count) repost.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !savedMessage.isEmpty {
                Section { Text(savedMessage).font(.footnote).foregroundStyle(.green) }
            }

            Section("Giới thiệu") {
                HStack {
                    Text("XTokTool")
                    Spacer()
                    Text("v1.0.0").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Dev")
                    Spacer()
                    Text("MinhTaz").foregroundStyle(.secondary)
                }
                Text("App iOS giúp dọn Following và Repost TikTok: huỷ follow có chọn lọc (giữ bạn bè + whitelist), gỡ bài đăng lại. Mọi thao tác đều qua trang web tiktok.com trong trình duyệt của app — TikTok API chính thức không có endpoint cho các việc này.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Cảnh báo: thao tác hàng loạt có thể bị TikTok giới hạn / khoá tạm. Dùng Dry-run trước, chạy chậm, tự chịu trách nhiệm với tài khoản của mình.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .navigationTitle("Cài đặt")
        .alert("Đăng xuất TikTok?", isPresented: $showLogoutConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Đăng xuất", role: .destructive) {
                Task { await auth.logout(using: web.cookieStore) }
            }
        } message: {
            Text("Cookie phiên TikTok trong app sẽ bị xoá. Bạn cần đăng nhập lại để dùng tiếp.")
        }
        .alert("Đặt lại state đã xử lý?", isPresented: $showResetConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Đặt lại", role: .destructive) {
                storage.resetProcessedState()
                savedMessage = "Đã đặt lại — lần chạy sau sẽ xử lý lại từ đầu."
            }
        }
    }
}
