import SwiftUI
import WebKit

/// Màn hình đăng nhập TikTok qua Web Login (WKWebView mở tiktok.com/login).
/// Người dùng đăng nhập như trên trình duyệt; cookie phiên được giữ lại
/// trong WKWebView để các chức năng quét / huỷ follow / gỡ repost dùng tiếp.
struct LoginView: View {
    @EnvironmentObject private var auth: TikTokAuthManager
    @EnvironmentObject private var web: TikTokWebService
    @EnvironmentObject private var storage: StorageManager

    @State private var usernameInput = ""
    @State private var showWebLogin = false
    @State private var showOAuthInfo = false
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Text("🎵")
                    .font(.system(size: 64))
                Text("XTokTool")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(
                        LinearGradient(colors: [.pink, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                Text("Dọn Following & Repost TikTok\nnhanh — an toàn — có chọn lọc")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Username TikTok của bạn")
                        .font(.headline)
                    TextField("@username (không cần @)", text: $usernameInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Text("Dùng để mở trang /following và tab Reposts của bạn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Button {
                    let name = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "@", with: "")
                    guard !name.isEmpty else {
                        statusMessage = "Nhập username TikTok trước đã."
                        return
                    }
                    storage.savedUsername = name
                    auth.username = name
                    showWebLogin = true
                } label: {
                    Label("Đăng nhập bằng TikTok (Web Login)", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .padding(.horizontal)

                Button("Tôi có TikTok Client Key — dùng Login Kit OAuth") {
                    showOAuthInfo = true
                }
                .font(.footnote)

                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.footnote).foregroundStyle(.orange)
                }

                Text("App không lưu mật khẩu TikTok. Phiên đăng nhập chỉ nằm trong trình duyệt của app (cookie). TikTok API chính thức không có endpoint huỷ follow / xoá repost, nên app thao tác qua trang web tiktok.com như bạn tự bấm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            }
            .navigationTitle("Đăng nhập")
            .sheet(isPresented: $showWebLogin) {
                WebLoginSheet(onDone: {
                    Task {
                        await auth.checkLoginState(using: web.cookieStore)
                        if auth.isLoggedIn {
                            auth.markLoggedIn(username: storage.savedUsername)
                            statusMessage = "Đã đăng nhập. Chào @\(storage.savedUsername)!"
                        } else {
                            statusMessage = "Chưa thấy phiên đăng nhập — thử đăng nhập lại trong trang web."
                        }
                    }
                })
            }
            .alert("Login Kit OAuth", isPresented: $showOAuthInfo) {
                Button("Đã hiểu", role: .cancel) {}
            } message: {
                Text("Nhập TikTok Client Key trong Cài đặt (Settings) trước. Nếu để trống, app dùng Web Login mặc định — không cần Client Key, không cần đăng ký app TikTok.")
            }
            .onAppear { usernameInput = storage.savedUsername }
        }
    }
}

/// Sheet chứa WKWebView mở trang đăng nhập TikTok.
struct WebLoginSheet: View {
    @EnvironmentObject private var web: TikTokWebService
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            TikTokWebViewRepresentable(webView: web.webView)
                .onAppear {
                    web.load(URL(string: "https://www.tiktok.com/login")!)
                }
                .navigationTitle("Đăng nhập TikTok")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Xong") {
                            onDone()
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// Cầu nối WKWebView vào SwiftUI.
struct TikTokWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
