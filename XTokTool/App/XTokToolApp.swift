import SwiftUI
import UIKit

/// XTokTool — App gốc.
/// Dev: MinhTaz
@main
struct XTokToolApp: App {
    @StateObject private var auth = TikTokAuthManager()
    @StateObject private var storage = StorageManager()
    @StateObject private var webService = TikTokWebService()
    @StateObject private var unfollowEngine = UnfollowEngine()
    @StateObject private var repostCleaner = RepostCleaner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(storage)
                .environmentObject(webService)
                .environmentObject(unfollowEngine)
                .environmentObject(repostCleaner)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var auth: TikTokAuthManager
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var web: TikTokWebService

    /// Đã kiểm tra phiên đã lưu hay chưa. Mở app là kiểm tra cookie phiên
    /// ngay — đăng nhập 1 lần, các lần sau vào thẳng màn hình chính, chỉ
    /// hiện màn đăng nhập khi phiên đã hết hạn thật.
    @State private var didCheckLogin = false

    var body: some View {
        Group {
            if !didCheckLogin {
                VStack(spacing: 16) {
                    AppLogoImage(size: 96)
                    ProgressView("Đang kiểm tra phiên đăng nhập…")
                }
            } else if auth.isLoggedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .tint(Color(red: 254/255, green: 44/255, blue: 85/255)) // Hồng TikTok #FE2C55 (không dùng Assets.xcassets nữa)
        .task {
            await auth.checkLoginState(using: web.cookieStore)
            if auth.isLoggedIn, auth.username.isEmpty {
                auth.username = storage.savedUsername
            }
            didCheckLogin = true
        }
    }
}

/// Logo app (file AppIcon-1024.png trong bundle). Nếu thiếu file thì hiện 🎵.
struct AppLogoImage: View {
    var size: CGFloat = 72

    var body: some View {
        if let ui = UIImage(named: "AppIcon-1024") {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Text("🎵").font(.system(size: size * 0.8))
        }
    }
}
