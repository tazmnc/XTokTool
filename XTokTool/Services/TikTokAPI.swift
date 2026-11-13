import Foundation

/// Lớp gọi API web nội bộ của TikTok (không chính thức) qua fetch() chạy
/// trong chính trang tiktok.com đã đăng nhập (WKWebView).
///
/// Nguyên lý: TikTok ký mọi request bằng X-Bogus / msToken do bundle
/// webmssdk tự chèn vào fetch() trong main world của trang. Gọi bằng
/// URLSession với cookie trích ra sẽ thiếu chữ ký và bị trả rỗng / lỗi,
/// còn gọi fetch() trong trang thì được ký tự động — không cần tự tính
/// chữ ký, không cần máy chủ ngoài, không cần API bên thứ ba.
///
/// Dùng cho: quét Following / Followers (JSON phân trang, nhẹ, không
/// cuộn trang), huỷ follow, liệt kê video repost. Mọi thao tác đều có
/// fallback về cách scrape DOM cũ nếu API trả lỗi.
@MainActor
final class TikTokAPI {
    private let web: TikTokWebService

    init(web: TikTokWebService) {
        self.web = web
    }

    // MARK: - Tải trang nhẹ để webmssdk hook fetch

    /// Tải trang cá nhân (nhẹ, không cuộn, không autoplay) để bundle
    /// webmssdk của TikTok tải lên và hook fetch(). Chờ tới khi dữ liệu
    /// rehydration của trang sẵn sàng (tối đa 15s).
    func ensureLoaded(username: String) async {
        web.loadProfilePage(username: username)
        let ready = await web.waitForContent(
            js: "typeof window.__UNIVERSAL_DATA_FOR_REHYDRATION__ !== 'undefined'",
            timeout: 15
        )
        if !ready {
            // Trang có thể đã tải nhưng dữ liệu chưa sẵn — chờ thêm rồi thử tiếp.
            await web.wait(seconds: 2)
        }
    }

    // MARK: - secUid

    /// Lấy secUid của user đang đăng nhập: thử đọc từ dữ liệu trang,
    /// nếu không có thì gọi /api/user/detail/.
    func getSecUid(username: String) async -> String? {
        let fromPageJS = """
        (() => {
          try {
            const d = window.__UNIVERSAL_DATA_FOR_REHYDRATION__?.__DEFAULT_SCOPE__?.['webapp.user-detail']?.userInfo?.user;
            return (d && d.secUid) ? d.secUid : '';
          } catch (e) { return ''; }
        })()
        """
        if let sec = await web.evaluateString(fromPageJS), !sec.isEmpty { return sec }

        let detailJS = """
        (async () => {
          try {
            const r = await fetch('/api/user/detail/?aid=1988&app_name=tiktok_web&device_platform=web_pc&uniqueId=' + encodeURIComponent('\(username)'), { credentials: 'include' });
            return await r.text();
          } catch (e) { return 'FETCH_ERROR'; }
        })()
        """
        guard let text = await web.evaluateString(detailJS),
              !text.hasPrefix("FETCH_ERROR"),
              let json = parseJSON(text),
              let userInfo = json["userInfo"] as? [String: Any],
              let user = userInfo["user"] as? [String: Any],
              let sec = str(user, "sec_uid"), !sec.isEmpty else { return nil }
        return sec
    }

    // MARK: - Quét Following / Followers bằng API

    /// Quét Following qua API, trả từng trang qua onBatch (streaming như
    /// cách quét DOM). Trả về (users, hadMutualSignal, error): error != nil
    /// khi trang đầu lỗi; hadMutualSignal = false nghĩa là API không cho
    /// biết ai là bạn bè (caller nên đối chiếu Followers để tính mutual).
    func fetchFollowing(secUid: String, onBatch: @escaping ([TikTokUser]) -> Void) async -> (users: [TikTokUser], hadMutualSignal: Bool, error: String?) {
        var all: [TikTokUser] = []
        var seen = Set<String>()
        var cursor = "0"
        var hadSignal = false
        var pages = 0
        while pages < 100 {
            if Task.isCancelled { break }
            pages += 1
            guard let json = await fetchListPage(secUid: secUid, scene: 21, cursor: cursor) else {
                return (all, hadSignal, all.isEmpty ? "Không gọi được API TikTok (mạng / chữ ký / phiên hết hạn)." : nil)
            }
            guard let items = json["followings"] as? [[String: Any]] else {
                return (all, hadSignal, "API trả về không có danh sách followings.")
            }
            var batch: [TikTokUser] = []
            for item in items {
                if intVal(item, "follow_status") != nil { hadSignal = true }
                guard let user = user(from: item), !seen.contains(user.username.lowercased()) else { continue }
                seen.insert(user.username.lowercased())
                batch.append(user)
            }
            if !batch.isEmpty {
                all.append(contentsOf: batch)
                onBatch(batch)
            }
            guard let next = nextCursor(from: json, current: cursor) else { break }
            cursor = next
        }
        return (all, hadSignal, nil)
    }

    /// Lấy tập username của Followers (scene=67) để tính mutual khi API
    /// Following không cho tín hiệu bạn bè. Trả về nil khi gọi API lỗi.
    /// Giới hạn 20 trang (~600 người) để không quét quá lâu.
    func fetchFollowerUsernames(secUid: String) async -> Set<String>? {
        var out = Set<String>()
        var cursor = "0"
        var pages = 0
        while pages < 20 {
            if Task.isCancelled { break }
            pages += 1
            guard let json = await fetchListPage(secUid: secUid, scene: 67, cursor: cursor),
                  let items = json["followers"] as? [[String: Any]] else { return nil }
            for item in items {
                if let name = str(item, "unique_id") { out.insert(name.lowercased()) }
            }
            guard let next = nextCursor(from: json, current: cursor) else { break }
            cursor = next
        }
        return out
    }

    /// Huỷ follow qua API. Trả về true khi TikTok xác nhận (status_code == 0).
    func unfollow(userId: String) async -> Bool {
        let tokenJS = "(document.cookie.match(/(?:^|; )tt_csrf_token=([^;]*)/) || [])[1] || ''"
        let token = await web.evaluateString(tokenJS) ?? ""
        let js = """
        (async () => {
          try {
            const r = await fetch('/api/commit/follow/user/?aid=1988&app_name=tiktok_web&device_platform=web_pc&user_id=\(userId)&type=0', {
              method: 'POST', credentials: 'include',
              headers: { 'tt-csrf-token': '\(token)', 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams({ user_id: '\(userId)', type: '0' })
            });
            return await r.text();
          } catch (e) { return 'FETCH_ERROR'; }
        })()
        """
        guard let text = await web.evaluateString(js),
              !text.hasPrefix("FETCH_ERROR"),
              let json = parseJSON(text) else { return false }
        return intVal(json, "status_code") == 0
    }

    /// Liệt kê video đã repost qua API. Trả về nil khi gọi API lỗi
    /// (để caller fallback sang quét DOM); mảng rỗng nghĩa là không có repost.
    func fetchReposts(secUid: String) async -> [RepostVideo]? {
        var out: [RepostVideo] = []
        var cursor = "0"
        var pages = 0
        while pages < 50 {
            if Task.isCancelled { break }
            pages += 1
            let js = """
            (async () => {
              const ctx = (window.__UNIVERSAL_DATA_FOR_REHYDRATION__ && window.__UNIVERSAL_DATA_FOR_REHYDRATION__.__DEFAULT_SCOPE__ && window.__UNIVERSAL_DATA_FOR_REHYDRATION__.__DEFAULT_SCOPE__['webapp.app-context']) || {};
              const q = new URLSearchParams({
                aid: '1988', app_name: 'tiktok_web', device_platform: 'web_pc',
                device_id: ctx.device_id || '', odinId: ctx.odinId || '', region: ctx.region || '',
                browser_language: ctx.browser_language || 'vi-VN', tz_name: ctx.tz_name || 'Asia/Ho_Chi_Minh',
                secUid: '\(secUid)', count: '35', cursor: '\(cursor)', coverFormat: '2', from_page: 'user'
              });
              try {
                const r = await fetch('/api/repost/item_list/?' + q.toString(), { credentials: 'include' });
                return await r.text();
              } catch (e) { return 'FETCH_ERROR'; }
            })()
            """
            guard let text = await web.evaluateString(js),
                  !text.hasPrefix("FETCH_ERROR"),
                  let json = parseJSON(text),
                  intVal(json, "status_code") == 0,
                  let items = json["itemList"] as? [[String: Any]] else { return nil }
            for item in items {
                guard let id = str(item, "id") else { continue }
                let author = (item["author"] as? [String: Any]).flatMap { str($0, "unique_id") }
                let desc = str(item, "desc")
                let url = author.map { "https://www.tiktok.com/@\($0)/video/\(id)" } ?? "https://www.tiktok.com/video/\(id)"
                out.append(RepostVideo(url: url, authorUsername: author, title: desc))
            }
            guard let next = nextCursor(from: json, current: cursor) else { break }
            cursor = next
        }
        return out
    }

    // MARK: - Gọi API nội bộ

    /// Gọi 1 trang /api/user/list/ (scene 21 = following, 67 = followers).
    /// Trả về JSON đã parse, hoặc nil khi fetch lỗi / status_code != 0.
    private func fetchListPage(secUid: String, scene: Int, cursor: String) async -> [String: Any]? {
        let js = """
        (async () => {
          const ctx = (window.__UNIVERSAL_DATA_FOR_REHYDRATION__ && window.__UNIVERSAL_DATA_FOR_REHYDRATION__.__DEFAULT_SCOPE__ && window.__UNIVERSAL_DATA_FOR_REHYDRATION__.__DEFAULT_SCOPE__['webapp.app-context']) || {};
          const q = new URLSearchParams({
            aid: '1988', app_name: 'tiktok_web', device_platform: 'web_pc',
            device_id: ctx.device_id || '', odinId: ctx.odinId || '', region: ctx.region || '',
            browser_language: ctx.browser_language || 'vi-VN', tz_name: ctx.tz_name || 'Asia/Ho_Chi_Minh',
            secUid: '\(secUid)', count: '30', minCursor: '\(cursor)', maxCursor: '0', scene: '\(scene)'
          });
          try {
            const r = await fetch('/api/user/list/?' + q.toString(), { credentials: 'include' });
            return await r.text();
          } catch (e) { return 'FETCH_ERROR'; }
        })()
        """
        guard let text = await web.evaluateString(js),
              !text.hasPrefix("FETCH_ERROR"),
              let json = parseJSON(text),
              intVal(json, "status_code") == 0 else { return nil }
        return json
    }

    /// Cursor trang tiếp theo từ response (min_cursor), hoặc nil khi hết.
    private func nextCursor(from json: [String: Any], current: String) -> String? {
        let hasMore = boolVal(json, "has_more") ?? false
        guard hasMore else { return nil }
        guard let next = intVal(json, "min_cursor"), next != -1, String(next) != current else { return nil }
        return String(next)
    }

    /// Đổi 1 item trong followings[] / followers[] thành TikTokUser.
    /// follow_status: 2 = bạn bè (mutual), còn lại = không follow lại.
    private func user(from item: [String: Any]) -> TikTokUser? {
        guard let username = str(item, "unique_id"), !username.isEmpty else { return nil }
        let nickname = str(item, "nickname") ?? username
        var avatar: String?
        if let thumb = item["avatar_thumb"] as? [String: Any],
           let list = thumb["url_list"] as? [String], let first = list.first {
            avatar = first
        } else if let med = item["avatar_medium"] as? [String: Any],
                  let list = med["url_list"] as? [String], let first = list.first {
            avatar = first
        }
        let verified = boolVal(item, "verified") ?? false
        let followStatus = intVal(item, "follow_status")
        let status: FollowStatus = (followStatus == 2) ? .friend : .notFollowingBack
        var user = TikTokUser(username: username, displayName: nickname, avatarURL: avatar, isVerified: verified, status: status)
        user.userId = str(item, "uid")
        return user
    }

    // MARK: - Parse JSON linh hoạt (API không có tài liệu chính thức)

    private func parseJSON(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    private func str(_ d: [String: Any], _ key: String) -> String? {
        if let s = d[key] as? String { return s }
        if let n = d[key] as? NSNumber { return n.stringValue }
        return nil
    }

    private func intVal(_ d: [String: Any], _ key: String) -> Int? {
        if d[key] is Bool { return nil }
        if let n = d[key] as? NSNumber { return n.intValue }
        if let s = d[key] as? String { return Int(s) }
        return nil
    }

    private func boolVal(_ d: [String: Any], _ key: String) -> Bool? {
        if let b = d[key] as? Bool { return b }
        if let n = d[key] as? NSNumber { return n.boolValue }
        return nil
    }
}
