import Foundation
import WebKit

/// WebView dùng chung cho toàn app: mọi thao tác với TikTok đều đi qua
/// https://www.tiktok.com trong WKWebView này, bằng JavaScript injection.
/// Tái dùng selector từ tool Python `tiktok-unrepost/unrepost.py`:
///  - Nút repost: `button[data-e2e="repost-button"]`
///  - Tab Reposts: `[data-e2e="reposts-tab"]`, text "Reposts" / "Đăng lại"
///  - Link video: `a[href*="/video/"]` với dạng `/@user/video/<id>`
///  - Xác nhận gỡ: nút chứa text "Remove" / "Gỡ" / "Xóa" / "Confirm"
@MainActor
final class TikTokWebService: ObservableObject {
    let webView: WKWebView
    @Published var currentURL: URL?
    @Published var isLoading = false

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Cho phép phát media inline như trình duyệt thường.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    var cookieStore: WKHTTPCookieStore {
        webView.configuration.websiteDataStore.httpCookieStore
    }

    // MARK: - Tải trang & chạy JS

    func load(_ url: URL) {
        currentURL = url
        webView.load(URLRequest(url: url))
    }

    func loadFollowingPage(username: String) {
        guard let url = URL(string: "https://www.tiktok.com/@\(username)/following") else { return }
        load(url)
    }

    func loadProfilePage(username: String) {
        guard let url = URL(string: "https://www.tiktok.com/@\(username)") else { return }
        load(url)
    }

    func loadRepostsPage(username: String) {
        loadProfilePage(username: username)
    }

    /// Chạy JS và trả về chuỗi kết quả (thường là JSON string).
    func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func evaluateString(_ script: String) async -> String? {
        try? await webView.evaluateJavaScript(script) as? String
    }

    func wait(seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Cuộn xuống cuối trang `times` lần, mỗi lần cách nhau `interval` giây.
    func scrollDown(times: Int, interval: Double = 1.5) async {
        for _ in 0..<times {
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);")
            await wait(seconds: interval)
        }
    }

    // MARK: - JS: Quét danh sách Following

    /// Gom các tài khoản trên trang /following: quét mọi link `/@username`,
    /// lấy avatar, tên hiển thị, badge verified và trạng thái follow lại.
    /// Trạng thái mutual được suy ra từ:
    ///  - nút trên card ghi "Friends" / "Bạn bè" hoặc có badge "Follow back",
    ///  - hoặc so sánh với danh sách followers (xem `collectFollowerUsernames`).
    static let collectFollowingJS = """
    (() => {
      const out = [];
      const seen = new Set();
      document.querySelectorAll('a[href^="/@"]').forEach(a => {
        const m = a.getAttribute('href').match(/^\\/@([^/?#]+)/);
        if (!m) return;
        const username = m[1];
        if (seen.has(username) || username === 'undefined') return;
        seen.add(username);
        const card = a.closest('div');
        const text = (a.closest('[data-e2e]')?.innerText || a.innerText || '');
        const img = a.querySelector('img');
        const isFriend = /Friends|Bạn bè|Follow back|Theo dõi lại/i.test(text);
        const isVerified = !!a.querySelector('svg');
        const nameEl = a.querySelector('p, span');
        out.push({
          username: username,
          displayName: (nameEl ? nameEl.innerText : username) || username,
          avatarURL: img ? img.src : '',
          isVerified: isVerified,
          isFriend: isFriend
        });
      });
      return JSON.stringify(out);
    })();
    """

    /// Gom username ở trang /followers để đối chiếu mutual.
    static let collectFollowerUsernamesJS = """
    (() => {
      const out = new Set();
      document.querySelectorAll('a[href^="/@"]').forEach(a => {
        const m = a.getAttribute('href').match(/^\\/@([^/?#]+)/);
        if (m) out.add(m[1]);
      });
      return JSON.stringify(Array.from(out));
    })();
    """

    /// Quét danh sách Following: cuộn nhiều lần rồi gom JS.
    func collectFollowing(maxScrolls: Int = 20) async -> [TikTokUser] {
        var all: [TikTokUser] = []
        var seen = Set<String>()
        for _ in 0..<maxScrolls {
            await scrollDown(times: 1, interval: 1.2)
            guard let json = await evaluateString(Self.collectFollowingJS),
                  let data = json.data(using: .utf8),
                  let rows = try? JSONDecoder().decode([FollowingRow].self, from: data) else { continue }
            for row in rows where !seen.contains(row.username.lowercased()) {
                seen.insert(row.username.lowercased())
                all.append(TikTokUser(
                    username: row.username,
                    displayName: row.displayName.isEmpty ? row.username : row.displayName,
                    avatarURL: row.avatarURL.isEmpty ? nil : row.avatarURL,
                    isVerified: row.isVerified,
                    status: row.isFriend ? .friend : .notFollowingBack
                ))
            }
        }
        return all
    }

    // MARK: - JS: Huỷ follow một người

    /// Trên trang /following, tìm card của `username`, bấm nút Following /
    /// "Đang follow" rồi bấm xác nhận "Unfollow" / "Bỏ theo dõi" nếu có.
    /// Trả về true nếu đã bấm được nút.
    static func unfollowJS(username: String) -> String {
        let safe = username.replacingOccurrences(of: "'", with: "\\'")
        return """
        (() => {
          const link = document.querySelector('a[href="/@\(safe)"]')
            || document.querySelector('a[href^="/@\(safe)?"]')
            || document.querySelector('a[href^="/@\(safe)/"]');
          if (!link) return 'not-found';
          const root = link.closest('div');
          const btns = (root ? root.parentElement : document).querySelectorAll('button');
          for (const b of btns) {
            const t = (b.innerText || '').trim();
            if (/^(Following|Đang follow|Friends|Bạn bè)$/i.test(t)) { b.click(); return 'clicked'; }
          }
          // Fallback: nút đầu tiên có data-e2e chứa follow trong card.
          const fb = root ? root.querySelector('button[data-e2e*="follow"]') : null;
          if (fb) { fb.click(); return 'clicked'; }
          return 'no-button';
        })();
        """
    }

    /// Bấm nút xác nhận trong hộp thoại sau khi bấm Unfollow.
    static let confirmUnfollowJS = """
    (() => {
      const btns = document.querySelectorAll('button');
      for (const b of btns) {
        const t = (b.innerText || '').trim();
        if (/^(Unfollow|Bỏ theo dõi|Hủy theo dõi|Confirm|Xác nhận)$/i.test(t)) { b.click(); return 'confirmed'; }
      }
      return 'no-dialog';
    })();
    """

    func unfollow(username: String) async -> Bool {
        guard let result = await evaluateString(Self.unfollowJS(username: username)) else { return false }
        if result == "clicked" {
            await wait(seconds: 1.5)
            _ = await evaluateString(Self.confirmUnfollowJS)
            return true
        }
        return false
    }

    // MARK: - JS: Repost (tái dùng unrepost.py)

    /// Gom link video trên tab Reposts: `a[href*="/video/"]`, dạng /@user/video/<id>.
    static let collectRepostLinksJS = """
    (() => {
      const out = new Set();
      document.querySelectorAll('a[href*="/video/"]').forEach(a => {
        const href = a.getAttribute('href') || '';
        const m = href.match(/(\\/@[^/]+\\/video\\/\\d+)/);
        if (m) out.add('https://www.tiktok.com' + m[1]);
      });
      return JSON.stringify(Array.from(out));
    })();
    """

    /// Mở tab Reposts trên trang cá nhân (data-e2e="reposts-tab" hoặc text).
    static let openRepostsTabJS = """
    (() => {
      const tab = document.querySelector('[data-e2e="reposts-tab"]')
        || Array.from(document.querySelectorAll('[role="tab"], a, p'))
            .find(el => /^(Reposts|Đăng lại)$/i.test((el.innerText || '').trim()));
      if (!tab) return 'not-found';
      tab.click();
      return 'clicked';
    })();
    """

    /// Gỡ repost của video đang mở: bấm `button[data-e2e="repost-button"]`
    /// rồi bấm xác nhận "Remove" / "Gỡ" (giống `click_repost_toggle` trong unrepost.py).
    static let removeRepostJS = """
    (() => {
      const btn = document.querySelector('button[data-e2e="repost-button"]')
        || Array.from(document.querySelectorAll('button'))
            .find(b => /repost/i.test(b.getAttribute('aria-label') || b.getAttribute('title') || ''));
      if (!btn) return 'no-button';
      btn.click();
      setTimeout(() => {
        const confirmBtn = Array.from(document.querySelectorAll('button'))
          .find(b => /^(Remove|Gỡ|Xóa|Delete|Confirm|Xác nhận)/i.test((b.innerText || '').trim()));
        if (confirmBtn) confirmBtn.click();
      }, 1200);
      return 'clicked';
    })();
    """

    func collectRepostLinks(maxScrolls: Int = 20) async -> [RepostVideo] {
        var urls = Set<String>()
        for _ in 0..<maxScrolls {
            await scrollDown(times: 1, interval: 1.2)
            guard let json = await evaluateString(Self.collectRepostLinksJS),
                  let data = json.data(using: .utf8),
                  let links = try? JSONDecoder().decode([String].self, from: data) else { continue }
            links.forEach { urls.insert($0) }
        }
        return urls.sorted().map { RepostVideo(url: $0) }
    }

    func removeRepost(at url: String) async -> Bool {
        guard let pageURL = URL(string: url) else { return false }
        load(pageURL)
        await wait(seconds: 3.5)
        guard let result = await evaluateString(Self.removeRepostJS) else { return false }
        await wait(seconds: 1.5)
        return result == "clicked"
    }

    // MARK: - JS: Bỏ thích (Unlike) — khung logic

    /// Trên trang video đã like, bấm nút Like để bỏ thích.
    /// Trạng thái: khung logic đã có, cần người dùng tự kiểm tra selector
    /// `data-e2e="like-button"` trên bản web TikTok hiện tại trước khi chạy loạt.
    static let unlikeJS = """
    (() => {
      const btn = document.querySelector('button[data-e2e="like-button"]');
      if (!btn) return 'no-button';
      const pressed = btn.getAttribute('aria-pressed') === 'true';
      if (!pressed) return 'not-liked';
      btn.click();
      return 'clicked';
    })();
    """
}

// MARK: - Hàng trung gian để decode JSON từ JS

private struct FollowingRow: Decodable {
    var username: String
    var displayName: String
    var avatarURL: String
    var isVerified: Bool
    var isFriend: Bool
}
