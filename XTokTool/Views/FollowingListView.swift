import SwiftUI

/// Màn Quét Following — giao diện gọn: 1 thẻ quét, bộ lọc, danh sách hiện
/// dần từng đợt trong lúc quét (không chờ quét xong mới hiện).
struct FollowingListView: View {
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var web: TikTokWebService

    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var isScanning = false
    @State private var scanMessage = ""
    @State private var keepInput = ""
    @State private var scanTask: Task<Void, Never>?

    enum Filter: String, CaseIterable {
        case all = "Tất cả"
        case friends = "Bạn bè"
        case notBack = "Không follow lại"
    }

    var filtered: [TikTokUser] {
        var list = storage.following
        switch filter {
        case .all: break
        case .friends: list = list.filter { $0.status == .friend }
        case .notBack: list = list.filter { $0.status == .notFollowingBack }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { $0.username.lowercased().contains(q) || $0.displayName.lowercased().contains(q) }
        }
        return list
    }

    var selectedCount: Int { storage.following.filter(\.isSelected).count }
    var friendsCount: Int { storage.following.filter { $0.status == .friend }.count }
    var notBackCount: Int { storage.following.filter { $0.status == .notFollowingBack }.count }

    var body: some View {
        VStack(spacing: 0) {
            scanCard

            Picker("Lọc", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 4)

            List {
                DisclosureGroup("Giữ lại — \(storage.keepList.usernames.count) người (không bao giờ bị huỷ)") {
                    HStack {
                        TextField("Nhập @username để giữ lại", text: $keepInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Thêm") {
                            let name = keepInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
                            guard !name.isEmpty else { return }
                            storage.addToKeepList(name)
                            keepInput = ""
                        }
                        .disabled(keepInput.isEmpty)
                    }
                    if !storage.keepList.usernames.isEmpty {
                        ForEach(Array(storage.keepList.usernames).sorted(), id: \.self) { name in
                            HStack {
                                Text("@\(name)")
                                Spacer()
                                Button(role: .destructive) { storage.removeFromKeepList(name) } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    } else {
                        Text("Chưa có ai. Bạn bè được gợi ý giữ lại bằng nút dưới.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Giữ lại toàn bộ bạn bè") {
                        storage.suggestKeepFriends()
                        scanMessage = "Đã thêm bạn bè vào danh sách giữ lại."
                    }
                }

                Section("Đã chọn: \(selectedCount) / \(storage.following.count) người") {
                    if filtered.isEmpty {
                        Text(isScanning ? "Đang quét, danh sách sẽ hiện dần ở đây…" : "Chưa có ai — bấm Quét để quét danh sách Following.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(filtered) { user in
                        FollowingRow(user: user) { newValue in
                            if let i = storage.following.firstIndex(where: { $0.username == user.username }) {
                                storage.following[i].isSelected = newValue
                            }
                        } onKeepToggle: {
                            if user.isKept { storage.removeFromKeepList(user.username) }
                            else { storage.addToKeepList(user.username) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Tìm theo tên / username")

            bottomBar
        }
        .navigationTitle("Quét Following")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { scanTask?.cancel() }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isScanning ? "Đang quét…" : "Danh sách Following")
                        .font(.headline)
                    Text(scanMessage.isEmpty
                         ? "\(storage.following.count) người • \(friendsCount) bạn bè • \(notBackCount) không follow lại"
                         : scanMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if isScanning {
                    Button("Dừng", role: .destructive) { scanTask?.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Quét") { startScan() }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                }
            }
            if isScanning {
                ProgressView()
                    .tint(.pink)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button("Chọn tất cả") { selectAll(true) }
            Button("Bỏ chọn") { selectAll(false) }
            Button("Đảo ngược") { invertSelection() }
        }
        .font(.subheadline)
        .padding()
        .background(Color(.systemBackground))
    }

    private func selectAll(_ value: Bool) {
        for i in storage.following.indices { storage.following[i].isSelected = value }
    }

    private func invertSelection() {
        for i in storage.following.indices { storage.following[i].isSelected.toggle() }
    }

    private func startScan() {
        let username = storage.savedUsername
        guard !username.isEmpty else {
            scanMessage = "Chưa có username — đăng nhập trước."
            return
        }
        scanTask?.cancel()
        isScanning = true
        scanMessage = "Đang mở trang Following…"
        scanTask = Task {
            defer {
                isScanning = false
                if Task.isCancelled {
                    scanMessage = "Đã dừng — giữ \(storage.following.count) người đã thấy."
                }
            }
            // Cách quét mới: chỉ tải trang /following MỘT lần, gom người mới
            // theo từng đợt và hiện + lưu ngay từng đợt — không tải thêm
            // trang /followers, không chờ cứng, không gom hết rồi mới hiện.
            // Nhờ vậy app nhẹ hơn nhiều, và nếu có văng giữa chừng thì
            // những người đã thấy vẫn còn, không mất hết.
            web.loadFollowingPage(username: username)
            _ = await web.waitForContent(js: TikTokWebService.hasUserCardsJS, timeout: 15)
            guard !Task.isCancelled else { return }
            _ = await web.streamFollowing(maxScrolls: 40, onBatch: { batch in
                var fresh = batch.filter { b in
                    !storage.following.contains(where: { $0.username.lowercased() == b.username.lowercased() })
                }
                guard !fresh.isEmpty else { return }
                for i in fresh.indices {
                    fresh[i].isKept = storage.keepList.contains(fresh[i].username)
                }
                storage.following.append(contentsOf: fresh)
                storage.saveFollowing()
                scanMessage = "Đã thấy \(storage.following.count) người…"
            })
            guard !Task.isCancelled else { return }
            storage.stats.totalFollowing = storage.following.count
            storage.stats.totalFriends = friendsCount
            storage.stats.totalNotFollowingBack = notBackCount
            storage.stats.lastScanDate = Date()
            storage.saveStats()
            storage.addLog(.success, "Quét Following: \(storage.following.count) người, \(friendsCount) bạn bè, \(notBackCount) không follow lại.")
            scanMessage = "Quét xong: \(storage.following.count) người • \(friendsCount) bạn bè • \(notBackCount) không follow lại."
        }
    }
}

struct FollowingRow: View {
    var user: TikTokUser
    var onSelect: (Bool) -> Void
    var onKeepToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { onSelect(!user.isSelected) } label: {
                Image(systemName: user.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(user.isSelected ? .pink : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            AsyncImage(url: URL(string: user.avatarURL ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.circle.fill").resizable()
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.displayName).font(.headline).lineLimit(1)
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.cyan).font(.caption)
                    }
                }
                Text("@\(user.username) • \(user.status.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(user.isKept ? "Đang giữ" : "Giữ lại") { onKeepToggle() }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(user.isKept ? .green : .gray)
        }
    }
}
