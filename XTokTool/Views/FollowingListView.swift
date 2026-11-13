import SwiftUI

/// Quét Following, phân loại, tìm kiếm, chọn / giữ lại.
struct FollowingListView: View {
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var web: TikTokWebService

    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var isScanning = false
    @State private var scanMessage = ""
    @State private var keepInput = ""

    enum Filter: String, CaseIterable {
        case all = "Tất cả"
        case friends = "Bạn bè"
        case notBack = "Không follow lại"
        case followingMe = "Đang follow mình"
    }

    var filtered: [TikTokUser] {
        var list = storage.following
        switch filter {
        case .all: break
        case .friends: list = list.filter { $0.status == .friend }
        case .notBack: list = list.filter { $0.status == .notFollowingBack }
        case .followingMe: list = list.filter { $0.status == .followingMe }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { $0.username.lowercased().contains(q) || $0.displayName.lowercased().contains(q) }
        }
        return list
    }

    var selectedCount: Int { storage.following.filter(\.isSelected).count }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Lọc", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)
            .padding()

            if isScanning {
                ProgressView("Đang quét trang Following… (cuộn nhiều lần để tải hết)")
                    .padding()
            }
            if !scanMessage.isEmpty {
                Text(scanMessage).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }

            List {
                Section("Giữ lại (whitelist) — những người này không bao giờ bị huỷ") {
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
                        Text("Chưa có ai trong danh sách giữ lại. Bạn bè được gợi ý giữ lại bằng nút dưới.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Gợi ý: giữ lại toàn bộ bạn bè") {
                        storage.suggestKeepFriends()
                        scanMessage = "Đã thêm bạn bè vào danh sách giữ lại."
                    }
                }

                Section("Đã chọn: \(selectedCount) / \(storage.following.count) người") {
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
            .searchable(text: $searchText, prompt: "Tìm theo tên / username")

            HStack(spacing: 8) {
                Button("Chọn tất cả") { selectAll(true) }
                Button("Bỏ chọn") { selectAll(false) }
                Button("Đảo ngược") { invertSelection() }
                Spacer()
                Button("Quét Following") { scan() }
                    .buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(isScanning)
            }
            .font(.footnote)
            .padding()
        }
        .navigationTitle("Following")
    }

    private func selectAll(_ value: Bool) {
        for i in storage.following.indices { storage.following[i].isSelected = value }
    }

    private func invertSelection() {
        for i in storage.following.indices { storage.following[i].isSelected.toggle() }
    }

    private func scan() {
        let username = storage.savedUsername
        guard !username.isEmpty else {
            scanMessage = "Chưa có username — đăng nhập trước."
            return
        }
        isScanning = true
        scanMessage = ""
        Task {
            web.loadFollowingPage(username: username)
            await web.wait(seconds: 4)
            // Đối chiếu followers để xác định mutual chính xác hơn.
            var followers = Set<String>()
            web.load(URL(string: "https://www.tiktok.com/@\(username)/followers")!)
            await web.wait(seconds: 4)
            if let json = await web.evaluateString(TikTokWebService.collectFollowerUsernamesJS),
               let data = json.data(using: .utf8),
               let names = try? JSONDecoder().decode([String].self, from: data) {
                followers = Set(names.map { $0.lowercased() })
            }
            web.loadFollowingPage(username: username)
            await web.wait(seconds: 4)
            var users = await web.collectFollowing(maxScrolls: 20)
            for i in users.indices {
                if followers.contains(users[i].username.lowercased()) {
                    users[i].status = .friend
                } else if users[i].status == .friend {
                    users[i].status = .notFollowingBack
                }
                users[i].isKept = storage.keepList.contains(users[i].username)
                // Giữ lại lựa chọn cũ nếu đã quét trước đó.
                if let old = storage.following.first(where: { $0.username == users[i].username }) {
                    users[i].isSelected = old.isSelected
                }
            }
            storage.following = users
            storage.saveFollowing()
            storage.stats.totalFollowing = users.count
            storage.stats.totalFriends = users.filter { $0.status == .friend }.count
            storage.stats.totalNotFollowingBack = users.filter { $0.status == .notFollowingBack }.count
            storage.stats.lastScanDate = Date()
            storage.saveStats()
            storage.addLog(.success, "Quét Following: \(users.count) người, \(storage.stats.totalFriends) bạn bè, \(storage.stats.totalNotFollowingBack) không follow lại.")
            scanMessage = "Quét xong: \(users.count) người • \(storage.stats.totalFriends) bạn bè • \(storage.stats.totalNotFollowingBack) không follow lại."
            isScanning = false
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
