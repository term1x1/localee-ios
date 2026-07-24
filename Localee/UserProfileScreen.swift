import SwiftUI

// Профиль другого пользователя — открывается по тапу на автора поста, участника
// группы и т.д. Только просмотр: чужое не редактируем. Действия — дружба и чат.
struct UserProfileScreen: View {
    let userId: Int
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var user: ApiUser?
    @State private var relation = "none"     // self | friends | incoming | outgoing | none
    @State private var posts: [Post] = []
    @State private var loading = true
    @State private var busy = false
    @State private var avatarZoom = false

    var body: some View {
        ScrollView {
            if let u = user {
                VStack(spacing: 0) {
                    header(u)
                    actions(u)
                    if !u.bio.isEmpty || !u.interestList.isEmpty || !u.city.isEmpty {
                        about(u)
                    }
                    postsSection
                }
            } else if loading {
                ProgressView().tint(Theme.accent).padding(.top, 60)
            } else {
                Text("Профиль недоступен").foregroundColor(Theme.text3).padding(.top, 60)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(user?.name ?? "Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .task { await load() }
        .fullScreenCover(isPresented: $avatarZoom) {
            if let u = user {
                ImageLightbox(src: u.avatar, fallbackColor: u.color, letter: u.letter) { avatarZoom = false }
            }
        }
    }

    // MARK: шапка
    private func header(_ u: ApiUser) -> some View {
        VStack(spacing: 0) {
            Group {
                if !u.cover.isEmpty { NetImage(src: u.cover) { coverGradient }.scaledToFill() }
                else { coverGradient }
            }
            .frame(height: 140).frame(maxWidth: .infinity).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)

            Button { if !u.avatar.isEmpty { avatarZoom = true } } label: {
                AvatarView(avatar: u.avatar, color: u.color, letter: u.letter,
                           handle: u.handle, name: u.name, size: 88)
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 4))
                    .overlay(alignment: .bottomTrailing) {
                        if u.online {
                            Circle().fill(Color(hex: 0x3FAE6E))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                        }
                    }
            }
            .offset(y: -44).padding(.bottom, -44)

            Text(u.name).font(.system(size: 22, weight: .heavy)).foregroundColor(Theme.text).padding(.top, 10)
            HStack(spacing: 6) {
                Text("@\(u.handle)").font(.system(size: 15)).foregroundColor(Theme.text2)
                if u.online {
                    Text("· в сети").font(.system(size: 14)).foregroundColor(Color(hex: 0x3FAE6E))
                }
            }
        }
    }

    private var coverGradient: some View {
        LinearGradient(colors: [Theme.accent, Theme.nightlife], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: кнопки действий (дружба + чат)
    @ViewBuilder private func actions(_ u: ApiUser) -> some View {
        if relation != "self" {
            HStack(spacing: 10) {
                friendButton
                NavigationLink { ConversationView(peer: chatUser(u)) } label: {
                    Label("Написать", systemImage: "bubble.right")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 16).padding(.top, 16)
        }
    }

    @ViewBuilder private var friendButton: some View {
        switch relation {
        case "friends":
            actionBtn("В друзьях", icon: "checkmark", filled: false) { await changeFriend { try await API.shared.removeFriend(userId) } }
        case "incoming":
            actionBtn("Принять", icon: "person.badge.plus", filled: true) { await changeFriend { try await API.shared.acceptFriend(userId) } }
        case "outgoing":
            actionBtn("Заявка отправлена", icon: "clock", filled: false) { await changeFriend { try await API.shared.removeFriend(userId) } }
        default:
            actionBtn("Добавить", icon: "person.badge.plus", filled: true) { await changeFriend { _ = try await API.shared.addFriend(userId) } }
        }
    }

    private func actionBtn(_ title: String, icon: String, filled: Bool,
                           _ act: @escaping () async -> Void) -> some View {
        Button { Task { await act() } } label: {
            Group {
                if busy { ProgressView().tint(filled ? .white : Theme.accent) }
                else { Label(title, systemImage: icon).font(.system(size: 15, weight: .bold)) }
            }
            .foregroundColor(filled ? .white : Theme.accent)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(filled ? Theme.accent : Theme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(busy)
    }

    // MARK: о себе
    private func about(_ u: ApiUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("О СЕБЕ").font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.text3).kerning(0.6)
            VStack(alignment: .leading, spacing: 12) {
                if !u.bio.isEmpty {
                    Text(u.bio).font(.system(size: 15)).foregroundColor(Theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading).lineSpacing(3)
                }
                if !u.city.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 14))
                            .foregroundColor(Theme.accent).frame(width: 22)
                        Text(u.city).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                    }
                }
                if !u.interestList.isEmpty { FlowChips(items: u.interestList) }
            }
            .padding(16).background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 18)
    }

    // MARK: посты пользователя
    @ViewBuilder private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ПОСТЫ").font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.text3).kerning(0.6)
            if posts.isEmpty {
                Text("Постов пока нет").font(.system(size: 15)).foregroundColor(Theme.text3)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ForEach(posts) { post in
                    PostCard(post: post, onLike: { likeInList(post) })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: данные
    private func load() async {
        if let r = try? await API.shared.userProfile(userId) {
            user = r.user
            relation = r.relation
        }
        posts = (try? await API.shared.userPosts(userId)) ?? []
        loading = false
    }

    private func changeFriend(_ act: () async throws -> Void) async {
        busy = true
        Haptics.tap()
        try? await act()
        if let r = try? await API.shared.userProfile(userId) { relation = r.relation }
        busy = false
    }

    private func likeInList(_ post: Post) {
        guard let i = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[i].liked.toggle()
        posts[i].likeCount += posts[i].liked ? 1 : -1
        Haptics.tap()
        Task {
            if let r = try? await API.shared.like(postId: post.id),
               let j = posts.firstIndex(where: { $0.id == post.id }) {
                posts[j].liked = r.liked; posts[j].likeCount = r.likeCount
            }
        }
    }

    private func chatUser(_ u: ApiUser) -> ChatUser {
        ChatUser(id: u.id, name: u.name, handle: u.handle,
                 color: u.color, letter: u.letter, avatar: u.avatar)
    }
}
