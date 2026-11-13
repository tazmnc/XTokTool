import AuthenticationServices
import Foundation
import WebKit

/// Quản lý đăng nhập TikTok.
///
/// Hai cách đăng nhập:
///  1. Web Login (mặc định, không cần Client Key): mở https://www.tiktok.com/login
///     trong WKWebView, người dùng đăng nhập như trên trình duyệt. Phiên được
///     giữ bằng cookie trong WKHTTPCookieStore của app.
///  2. Login Kit OAuth (tuỳ chọn): nếu người dùng nhập TikTok Client Key trong
///     Settings, dùng ASWebAuthenticationSession mở trang authorize của TikTok.
///     KHÔNG hardcode Client Key / Secret trong source.
///
/// Lưu ý quan trọng: TikTok API chính thức KHÔNG có endpoint unfollow hay
/// xoá repost. Vì vậy mọi thao tác huỷ follow / gỡ repost trong app đều là
/// web automation qua WKWebView + JavaScript injection trên tiktok.com
/// (giống tool Python tiktok-unrepost trước đây), không phải gọi API.
@MainActor
final class TikTokAuthManager: ObservableObject {
    @Published var isLoggedIn = false
    @Published var username: String = ""
    @Published var isCheckingLogin = false

    /// Cookie phiên TikTok — TikTok dùng các cookie như `sessionid`, `sid_tt`,
    /// `msToken`, `ttwid`. Chỉ cần có `sessionid` (hoặc `sid_tt`) là coi như
    /// đã đăng nhập. Tên cookie có thể thay đổi theo TikTok, nên kiểm tra
    /// cả dấu hiệu nút "Log in" trên trang chủ.
    private let sessionCookieNames: Set<String> = ["sessionid", "sid_tt", "sessionid_ss"]

    private var authSession: ASWebAuthenticationSession?
    /// Giữ mạnh context trình bày cho ASWebAuthenticationSession — thuộc tính
    /// presentationContextProvider của session chỉ giữ weak, tạo tạm rồi bỏ
    /// sẽ bị nil ngay và cảnh báo "weak reference will always be nil".
    private var authContext: AuthPresentationContext?

    // MARK: - Kiểm tra phiên từ cookie store

    func checkLoginState(using cookieStore: WKHTTPCookieStore) async {
        isCheckingLogin = true
        defer { isCheckingLogin = false }
        let cookies = await cookieStore.allCookies()
        let hasSession = cookies.contains { sessionCookieNames.contains($0.name.lowercased()) }
        // TikTok đặt cookie session cho domain .tiktok.com; nếu không có
        // cookie phiên thì chắc chắn chưa đăng nhập.
        isLoggedIn = hasSession
        if !username.isEmpty && !hasSession {
            // Giữ lại username đã lưu để quét, nhưng báo chưa đăng nhập.
        }
    }

    func markLoggedIn(username: String) {
        self.username = username
        isLoggedIn = true
    }

    // MARK: - Login Kit OAuth (tuỳ chọn, cần Client Key)

    /// Mở trang authorize của TikTok. Trả về `true` nếu nhận được `code`.
    /// App KHÔNG tự đổi code lấy access token trong client (cần Client Secret
    /// và server) — code chỉ được ghi log rút gọn để dev tự xử lý nếu cần.
    /// Khi chưa có Client Key thì hàm này không làm gì và trả về false.
    func loginWithLoginKit(clientKey: String, presentationAnchor: ASPresentationAnchor) async -> Bool {
        let key = clientKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        let redirectURI = "https://www.tiktok.com/auth/redirect"
        let scope = "user.info.basic"
        var components = URLComponents(string: "https://www.tiktok.com/v2/auth/authorize/")!
        components.queryItems = [
            URLQueryItem(name: "client_key", value: key),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        guard let url = components.url else { return false }

        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "https") { callbackURL, error in
                if let callbackURL,
                   let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value,
                   !code.isEmpty {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
            let context = AuthPresentationContext(anchor: presentationAnchor)
            self.authContext = context
            session.presentationContextProvider = context
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    // MARK: - Đăng xuất

    func logout(using cookieStore: WKHTTPCookieStore) async {
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where cookie.domain.contains("tiktok.com") {
            await cookieStore.deleteCookie(cookie)
        }
        isLoggedIn = false
        username = ""
    }
}

private final class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
