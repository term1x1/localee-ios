import SwiftUI

// Пересылка поста в личный чат или группу.
// Пост уходит как обычное сообщение: подпись «Пост от N» + текст и фото поста.
struct ForwardPostSheet: View {
    let post: Post
    @Environment(\.dismiss) var dismiss
    @State private var chats: [ChatListItem] = []
    @State private var groups: [GroupListItem] = []
    @State private var loading = true
    @State private var sendingTo: String?      // "u<id>" / "g<id>" — идёт отправка
    @State private var sentTo: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if !chats.isEmpty { header("ЛИЧНЫЕ") }
                            ForEach(chats) { c in
                                row(key: "u\(c.user.id)", avatar: c.user.avatar, color: c.user.color,
                                    letter: c.user.letter, handle: c.user.handle, name: c.user.name) {
                                    await forwardToChat(c.user.id)
                                }
                            }
                            if !groups.isEmpty { header("ГРУППЫ") }
                            ForEach(groups) { g in
                                row(key: "g\(g.id)", avatar: "", color: g.color,
                                    letter: g.letter, handle: "", name: g.name) {
                                    await forwardToGroup(g.id)
                                }
                            }
                        }
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Переслать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.tint(Theme.accent) } }
        }
        .task {
            async let c = try? await API.shared.chats()
            async let g = try? await API.shared.groupList()
            chats = (await c) ?? []
            groups = (await g) ?? []
            loading = false
        }
    }

    private func header(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text3).kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
    }

    private func row(key: String, avatar: String, color: String, letter: String,
                     handle: String, name: String, _ act: @escaping () async -> Void) -> some View {
        Button { Task { await act() } } label: {
            HStack(spacing: 12) {
                AvatarView(avatar: avatar, color: color, letter: letter, handle: handle, name: name, size: 46)
                Text(name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                if sendingTo == key {
                    ProgressView().tint(Theme.accent)
                } else if sentTo.contains(key) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: 0x3FAE6E))
                } else {
                    Image(systemName: "paperplane").foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sentTo.contains(key) || sendingTo != nil)
    }

    // Текст пересылаемого поста: подпись + сам текст.
    private var forwardText: String {
        let who = post.author?.name ?? "Пользователь"
        return post.text.isEmpty ? "📮 Пост от \(who)" : "📮 Пост от \(who):\n\(post.text)"
    }

    private func forwardToChat(_ userId: Int) async {
        sendingTo = "u\(userId)"
        _ = try? await API.shared.send(to: userId, text: forwardText, image: post.image)
        sentTo.insert("u\(userId)"); sendingTo = nil
        Haptics.success()
    }
    private func forwardToGroup(_ groupId: Int) async {
        sendingTo = "g\(groupId)"
        _ = try? await API.shared.groupSend(groupId, text: forwardText, image: post.image)
        sentTo.insert("g\(groupId)"); sendingTo = nil
        Haptics.success()
    }
}
