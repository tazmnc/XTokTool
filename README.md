# XTokTool — Dọn Following & Repost TikTok

**App iPhone (SwiftUI, iOS 17+) — Dev: MinhTaz**

XTokTool giúp bạn dọn tài khoản TikTok: huỷ follow những người không follow
lại mình (giữ lại bạn bè và những người bạn chọn), và gỡ toàn bộ video đã
đăng lại (repost). Mọi thao tác đều chạy trên chính tài khoản của bạn, trong
trình duyệt của app.

> ⚠️ **Sự thật cần biết trước:** TikTok API chính thức **KHÔNG có endpoint
> unfollow / xoá repost**. Vì vậy app **không gọi API TikTok** để làm việc này
> mà dùng **web automation qua WKWebView + JavaScript injection trên
> tiktok.com** — đúng cách tool Python `tiktok-unrepost` trước đây đã làm
> (Playwright + selector `data-e2e="repost-button"`, tab Reposts,
> link `/video/`). Nếu TikTok đổi giao diện web, selector có thể cần cập nhật.

---

## Tính năng

| # | Tính năng | Trạng thái |
|---|-----------|------------|
| 1 | **Đăng nhập TikTok — Web Login** (mặc định): mở `tiktok.com/login` trong WKWebView, đăng nhập như trên trình duyệt, phiên giữ bằng cookie (`WKHTTPCookieStore`). Không cần Client Key, không lưu mật khẩu. | ✅ Đầy đủ |
| 2 | **Đăng nhập TikTok — Login Kit OAuth** (tuỳ chọn): nhập Client Key trong Settings, app mở trang authorize qua `ASWebAuthenticationSession`. Mặc định để trống. Không hardcode Key/Secret. | ✅ Khung đầy đủ |
| 3 | **Quét Following**: mở `@username/following`, cuộn trang, gom avatar / username / tên hiển thị / verified / bạn bè (mutual — đối chiếu thêm với trang `/followers`). Lưu local JSON. | ✅ Đầy đủ |
| 4 | **Phân loại + chọn**: tab Tất cả / Bạn bè / Không follow lại / Đang follow mình, tìm kiếm theo tên, chọn từng người, Chọn tất cả / Bỏ chọn / Đảo ngược. | ✅ Đầy đủ |
| 5 | **Danh sách Giữ lại (whitelist)**: thêm/xoá, lưu UserDefaults, gợi ý giữ toàn bộ bạn bè. Người trong whitelist không bao giờ bị huỷ. | ✅ Đầy đủ |
| 6 | **Huỷ follow — 2 chế độ**: (a) huỷ người đã chọn; (b) huỷ tất cả **trừ bạn bè + whitelist**. | ✅ Đầy đủ |
| 7 | **An toàn khi huỷ**: Dry-run (chỉ liệt kê), giới hạn mỗi phiên mặc định 30 (tối đa 100), delay ngẫu nhiên 5–12 giây, nghỉ dài 60 giây sau mỗi 15 người, nút **Dừng khẩn cấp**, log từng thao tác, lưu state đã xử lý để chạy tiếp không trùng. | ✅ Đầy đủ |
| 8 | **Xoá bài đăng lại (Repost)**: quét tab Reposts, liệt kê link video, gỡ từng cái (bấm nút repost + xác nhận Remove/Gỡ), dry-run, giới hạn, delay, log, lưu state. Port từ `unrepost.py`. | ✅ Đầy đủ |
| 9 | **Bỏ thích video đã like (Unlike)**: khung logic có sẵn (`button[data-e2e="like-button"]`), cần kiểm tra selector trên bản web hiện tại trước khi chạy loạt. | 🟡 Khung logic |
| 10 | **Xoá video của mình**: **không auto hàng loạt** (nguy hiểm, không hoàn tác) — app chỉ mở trang cá nhân để bạn tự xác nhận xoá từng cái. | 🟡 Chỉ hỗ trợ thủ công |
| 11 | **Thống kê**: tổng following, bạn bè, không follow lại, đã huỷ, đã gỡ repost, đã bỏ thích. | ✅ Đầy đủ |
| 12 | **Nhật ký (Log)**: mọi thao tác ghi log có giờ, xem/xoá trong app. | ✅ Đầy đủ |

---

## Cấu trúc source

```
XTokTool/
├── XTokTool.xcodeproj/project.pbxproj   # Project Xcode (target iOS 17.0, Swift 5)
├── XTokTool/
│   ├── App/XTokToolApp.swift            # App gốc, @main
│   ├── Models/Models.swift              # TikTokUser, FollowStatus, AppLog, KeepList, AppStats, RunSettings
│   ├── Services/
│   │   ├── TikTokAuthManager.swift      # Web Login + Login Kit OAuth + cookie session
│   │   ├── TikTokWebService.swift       # WKWebView + JS: quét Following / unfollow / repost
│   │   ├── UnfollowEngine.swift         # Engine huỷ follow (dry-run, giới hạn, delay, dừng)
│   │   ├── RepostCleaner.swift          # Engine gỡ repost (port unrepost.py)
│   │   └── StorageManager.swift         # JSON local + UserDefaults (whitelist, settings, log, state)
│   ├── Views/
│   │   ├── LoginView.swift              # Đăng nhập + WebView đăng nhập
│   │   ├── HomeView.swift               # Trang chính + thống kê + Công cụ thêm
│   │   ├── FollowingListView.swift       # Quét / lọc / tìm / chọn / giữ lại
│   │   ├── UnfollowView.swift           # Huỷ follow 2 chế độ
│   │   ├── RepostView.swift             # Quét & gỡ repost
│   │   ├── SettingsView.swift           # Cài đặt + About (Dev: MinhTaz)
│   │   └── LogView.swift                # Nhật ký
│   ├── Resources/
│   │   ├── Info.plist                   # bundle id com.mintaz.xtoktool
│   │   └── Assets.xcassets/             # AppIcon (placeholder) + AccentColor (#FE2C55)
│   └── Config.xcconfig                  # TIKTOK_CLIENT_KEY = "" (trống mặc định)
├── .github/workflows/build-ipa.yml      # CI: build IPA unsigned trên macos-14
├── .gitignore
└── README.md
```

- **Tên app:** XTokTool — **Bundle ID:** `com.mintaz.xtoktool`
- **Giao diện:** tiếng Việt, tông đen/hồng TikTok, SwiftUI + NavigationStack, Dark mode.
- **Không hardcode** token / mật khẩu / Client Key / Secret. Client Key chỉ nhập
  tay trong Settings hoặc `Config.xcconfig`, mặc định trống.

---

## Cách build trên máy Mac (có Xcode 15+)

```bash
git clone <repo-của-bạn>
cd XTokTool
open XTokTool.xcodeproj
```

1. Trong Xcode: chọn target **XTokTool** → tab **Signing & Capabilities** →
   tick **Automatically manage signing**, chọn Team = Apple ID của bạn.
2. Cắm iPhone (hoặc chọn simulator), bấm **Run** (⌘R).
3. Lần đầu chạy trên iPhone thật: vào iPhone **Cài đặt → Cài đặt chung →
   Quản lý VPN & Thiết bị** → tin cậy chứng chỉ nhà phát triển của bạn.

## Cách lấy file IPA

### Cách 1 — GitHub Actions (không cần máy Mac, không cần cert)
1. Push repo này lên GitHub.
2. Vào tab **Actions** → chạy workflow **"Build XTokTool IPA (unsigned)"**.
3. Tải artifact `XTokTool-unsigned-ipa` → file `XTokTool-unsigned.ipa`.

### Cách 2 — Xcode trên máy Mac
```bash
xcodebuild -project XTokTool.xcodeproj -scheme XTokTool -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
# rồi đóng gói .app trong DerivedData thành Payload/XTokTool.app → zip thành .ipa
```

### Cài IPA lên iPhone
IPA từ 2 cách trên là **unsigned** — iPhone không cài trực tiếp được.
Cần ký lại bằng một trong các cách sau (dùng Apple ID miễn phí của chính bạn):

- **AltStore / SideStore**: ký bằng Apple ID miễn phí, dùng được 7 ngày, gia hạn lại.
- **Sideloadly** (miễn phí, trên Windows/Mac): kéo IPA vào, nhập Apple ID.
- **Xcode + Apple ID trả phí (99$/năm)**: ký chính thức, dùng lâu dài.
- **TrollStore** (nếu máy đã jailbreak / đúng phiên bản hỗ trợ): cài IPA không cần ký.

> Không có cách nào tạo IPA "đã ký sẵn, cài là chạy" mà không có chứng chỉ
> Apple — bất kỳ ai hứa điều đó đều không đúng quy trình của Apple.

---

## Cách dùng app (quy trình khuyên dùng)

1. **Đăng nhập**: mở app → nhập `@username` → **Đăng nhập bằng TikTok
   (Web Login)** → đăng nhập trong trang web hiện ra → bấm **Xong**.
2. **Quét Following**: vào **Danh sách Following** → **Quét Following** →
   chờ app cuộn hết trang (đối chiếu cả Followers để biết ai là bạn bè).
3. **Giữ lại**: bấm **"Gợi ý: giữ lại toàn bộ bạn bè"**, thêm tay vài người
   quan trọng vào whitelist nếu cần.
4. **Dry-run trước**: vào **Huỷ follow**, bật **Dry-run**, chạy thử để xem
   danh sách sẽ huỷ — kiểm tra kỹ không có người quen bị lọt vào.
5. **Chạy thật**: tắt Dry-run, để giới hạn **30 người/phiên**, bấm bắt đầu.
   Muốn huỷ tiếp thì chạy phiên sau (app tự bỏ qua người đã xử lý).
6. **Gỡ repost**: vào **Xoá bài đăng lại** → **Quét tab Reposts** → Dry-run
   → chạy thật, tương tự.
7. Xem kết quả trong **Nhật ký** (icon danh sách ở góc phải màn hình chính).

---

## Rủi ro & lưu ý

- **Huỷ follow / gỡ repost hàng loạt có thể bị TikTok giới hạn tạm thời,
  khoá tính năng hoặc khoá tài khoản.** Hãy chạy chậm (delay 5–12 giây,
  nghỉ 60 giây sau mỗi 15 người), mỗi phiên tối đa 30, đừng chạy liên tục
  nhiều phiên trong ngày.
- Thao tác **không hoàn tác được** — huỷ follow rồi phải follow lại tay,
  gỡ repost rồi phải repost lại tay.
- TikTok hay đổi giao diện web: nếu một ngày nút bấm không còn hoạt động,
  selector trong `TikTokWebService.swift` (các hằng `*JS`) cần cập nhật
  theo giao diện mới — xem lại selector gốc trong tool Python
  `tiktok-unrepost/unrepost.py`.
- App chỉ thao tác trên `tiktok.com` trong WKWebView của chính người dùng,
  không gửi dữ liệu tài khoản đi đâu khác, không gọi API lạ.

---

## Dev

**Dev: MinhTaz** — XTokTool v1.0.0 (13/11/2026).
