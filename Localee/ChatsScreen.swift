import SwiftUI

struct ChatsScreen: View {
    @State private var seg = 0            // 0 — личные, 1 — группы
    @State private var chats: [ChatListItem] = []
    @State private var groups: [GroupListItem] = []
    @State private var loading = true
    @State private var showNewChat = false
    @State private var showCreateGroup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $seg) {
                    Text("Личные").tag(0)
                    Text("Группы").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)

                if loading {
                    Spacer(); ProgressView().tint(Theme.accent); Spacer()
                } else if seg == 0 {
                    personalList
                } else {
                    groupsList
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Чаты")
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showNewChat = true } label: { Label("Новый чат", systemImage: "person") }
                        Button { showCreateGroup = true } label: { Label("Новая группа", systemImage: "person.3") }
                    } label: {
                        Image(systemName: "square.and.pencil").foregroundColor(Theme.accent)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showNewChat) { NewChatSheet() }
        .sheet(isPresented: $showCreateGroup) { CreateGroupSheet { Task { await load() } } }
    }

    private var personalList: some View {
        Group {
            if chats.isEmpty {
                emptyView("Нет диалогов", "Начните новый чат кнопкой ✎")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(chats) { item in
                            NavigationLink { ConversationView(peer: item.user) } label: { chatRow(item) }
                            Divider().overlay(Theme.border).padding(.leading, 78)
                        }
                    }
                }
            }
        }
    }

    private var groupsList: some View {
        Group {
            if groups.isEmpty {
                emptyView("Нет групп", "Создайте группу кнопкой ✎")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { g in
                            NavigationLink { GroupChatView(groupId: g.id, initialName: g.name) } label: { groupRow(g) }
                            Divider().overlay(Theme.border).padding(.leading, 78)
                        }
                    }
                }
            }
        }
    }

    private func chatRow(_ item: ChatListItem) -> some View {
        HStack(spacing: 12) {
            AvatarView(avatar: item.user.avatar, color: item.user.color, letter: item.user.letter, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.user.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                    Spacer()
                    if let last = item.last { Text(timeAgo(last.createdAt)).font(.system(size: 12)).foregroundColor(Theme.text3) }
                }
                HStack {
                    Text(item.last.map { ($0.fromMe ? "Вы: " : "") + $0.text } ?? "Нет сообщений")
                        .font(.system(size: 14)).foregroundColor(Theme.text2).lineLimit(1)
                    Spacer()
                    if item.unread > 0 { unreadBadge(item.unread) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11).contentShape(Rectangle())
    }

    private func groupRow(_ g: GroupListItem) -> some View {
        HStack(spacing: 12) {
            AvatarView(avatar: "", color: g.color, letter: g.letter, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(g.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                    Spacer()
                    if let last = g.last { Text(timeAgo(last.createdAt)).font(.system(size: 12)).foregroundColor(Theme.text3) }
                }
                HStack {
                    Text(groupPreview(g)).font(.system(size: 14)).foregroundColor(Theme.text2).lineLimit(1)
                    Spacer()
                    if g.unread > 0 { unreadBadge(g.unread) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11).contentShape(Rectangle())
    }

    private func groupPreview(_ g: GroupListItem) -> String {
        guard let last = g.last else { return "\(g.memberCount) участников" }
        let who = last.fromMe ? "Вы" : last.author
        return "\(who): \(last.text)"
    }

    private func unreadBadge(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.accent).clipShape(Capsule())
    }

    private func emptyView(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text2)
            Text(sub).font(.system(size: 14)).foregroundColor(Theme.text3)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        async let c = try? await API.shared.chats()
        async let g = try? await API.shared.groupList()
        chats = (await c) ?? []
        groups = (await g) ?? []
        loading = false
    }
}
