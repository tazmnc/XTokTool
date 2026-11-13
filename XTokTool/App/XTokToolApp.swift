import SwiftUI

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

    var body: some View {
        Group {
            if auth.isLoggedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .tint(Color(red: 254/255, green: 44/255, blue: 85/255)) // Hồng TikTok #FE2C55 (không dùng Assets.xcassets nữa)
    }
}
