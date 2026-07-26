import SwiftUI
import PhotosUI

struct FeedScreen: View {
    @EnvironmentObject var postStore: PostStore
    @EnvironmentObject var store: AppStore
    @State private var scope = "all"          // "all" — все, "friends" — свои и друзей
    @State private var friendIds: Set<Int> = []
    @State private var newText = ""
    @State private var sending = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachments: [Attachment] = []   // фото + документы поста
    @State private var showFileImporter = false
    @State private var commentsFor: Post?
    @State private var forwardPost: Post?

    // Посты под текущую вкладку. PostStore держит ВСЕ посты (для профиля и вкладки
    // «Все»); «Друзья» фильтруем локально по друзьям — так не заводим второй
    // источник и не расходимся с профилем.
    private var visiblePosts: [Post] {
        guard scope == "friends" else { return postStore.posts }
        let me = store.user?.id ?? -1
        return postStore.posts.filter { p in
            let a = p.author?.id ?? -1
            return a == me || friendIds.contains(a)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Лента")
                        .font(.system(size: 32, weight: .heavy)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    scopeTabs
                    composer
                    if !postStore.loaded {
                        ProgressView().tint(Theme.accent).padding(.top, 40)
                    } else if visiblePosts.isEmpty {
                        emptyFeed
                    } else {
                        ForEach(visiblePosts) { post in
                            PostCard(
                                post: post,
                                onLike: { like(post) },
                                onComment: { commentsFor = post },
                                onDelete: post.mine ? { delete(post) } : nil,
                                onForward: { forwardPost = post })
                        }
                    }
                }
                .padding(14)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await postStore.refresh() }
        }
        .task {
            await postStore.loadIfNeeded()
            await loadFriends()
        }
        .sheet(item: $commentsFor) { post in
            CommentsSheet(post: post) { newCount in
                postStore.setCommentCount(post.id, newCount)
            }
        }
        .sheet(item: $forwardPost) { post in ForwardPostSheet(post: post) }
    }

    // Вкладки «Все / Друзья» — как на сайте.
    private var scopeTabs: some View {
        Picker("", selection: $scope) {
            Text("Все").tag("all")
            Text("Друзья").tag("friends")
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var emptyFeed: some View {
        if scope == "friends" {
            VStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 40, weight: .light)).foregroundColor(Theme.text3)
                Text("Пока нет постов друзей")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                Text("Добавьте друзей или посмотрите вкладку «Все».")
                    .font(.system(size: 14)).foregroundColor(Theme.text3)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            // Пустая лента: вместо сухого текста — предложение пойти на карту.
            VStack(spacing: 14) {
                Image(systemName: "square.stack")
                    .font(.system(size: 40, weight: .light)).foregroundColor(Theme.text3)
                Text("В ленте пока пусто")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                Text("Загляните на карту — там видно, где сейчас люди и что происходит в городе.")
                    .font(.system(size: 14)).foregroundColor(Theme.text3)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                Button { NotificationCenter.default.post(name: .goToMapTab, object: nil) } label: {
                    Label("Что происходит на карте?", systemImage: "map.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 13)
                        .background(Theme.accent).clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $newText, prompt: Text("Что нового?").foregroundColor(Theme.text3), axis: .vertical)
                .foregroundColor(Theme.text).lineLimit(1...5)

            if !attachments.isEmpty {
                AttachmentPreviewRow(items: $attachments).padding(.horizontal, -12)
            }

            HStack(spacing: 14) {
                // Несколько фото
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 20)).foregroundColor(Theme.accent)
                }
                // Документы
                Button { showFileImporter = true } label: {
                    Image(systemName: "paperclip").font(.system(size: 20)).foregroundColor(Theme.accent)
                }
                Spacer()
                let canPost = (!newText.trimmed.isEmpty || !attachments.isEmpty) && !sending
                Button(action: publish) {
                    Text(sending ? "…" : "Опубликовать")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .opacity(canPost ? 1 : 0.4)
                .disabled(!canPost)
            }
        }
        .padding(12).background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onChange(of: photoItems) { _, items in
            Task {
                let picked = await loadPickedPhotos(items)
                attachments.append(contentsOf: picked)
                photoItems = []
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls { if let a = fileToAttachment(url) { attachments.append(a) } }
            }
        }
    }

    private func loadFriends() async {
        if let r = try? await API.shared.friends() { friendIds = Set(r.friends.map { $0.id }) }
    }
    private func publish() {
        let t = newText.trimmed
        guard (!t.isEmpty || !attachments.isEmpty), !sending else { return }
        sending = true
        Task {
            if let post = try? await API.shared.createPost(text: t, attachments: attachments) {
                postStore.prepend(post); newText = ""; attachments = []; photoItems = []
            }
            sending = false
        }
    }
    private func like(_ post: Post) {
        postStore.toggleLike(post.id)
        Haptics.tap()
        Task {
            if let r = try? await API.shared.like(postId: post.id) {
                postStore.applyLike(post.id, liked: r.liked, count: r.likeCount)
            }
        }
    }
    private func delete(_ post: Post) {
        Haptics.tap(.medium)
        postStore.remove(post.id)
        Task { try? await API.shared.deletePost(post.id) }
    }
}

struct PostCard: View {
    let post: Post
    let onLike: () -> Void
    var onComment: () -> Void = {}
    var onDelete: (() -> Void)? = nil       // задано только для своих постов
    var onForward: (() -> Void)? = nil      // переслать пост в чат/группу

    // Отдельное состояние — чтобы анимировать «прыжок» сердечка независимо
    // от прихода ответа сервера.
    @State private var likeBounce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !post.text.isEmpty {
                Text(post.text).font(.system(size: 15.5)).foregroundColor(Theme.text).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !post.allAttachments.isEmpty {
                AttachmentsView(attachments: post.allAttachments, maxWidth: .infinity)
            }
            actionBar
        }
        .padding(14).background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Шапка: аватар и имя ведут в профиль автора; справа — меню (⋯).
    private var header: some View {
        HStack(spacing: 10) {
            authorLink {
                AvatarView(avatar: post.author?.avatar ?? "", color: post.author?.color ?? "",
                           letter: post.author?.letter ?? "", handle: post.author?.handle ?? "",
                           name: post.author?.name ?? "", size: 40)
            }
            authorLink {
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.author?.name ?? "Пользователь")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    Text("@\(post.author?.handle ?? "") · \(timeAgo(post.createdAt))")
                        .font(.system(size: 13)).foregroundColor(Theme.text3)
                }
            }
            Spacer()
            Menu {
                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: { Label("Удалить пост", systemImage: "trash") }
                }
                if let onForward {
                    Button { onForward() } label: { Label("Переслать в чат", systemImage: "paperplane") }
                }
                if !post.text.isEmpty {
                    Button { UIPasteboard.general.string = post.text } label: { Label("Копировать текст", systemImage: "doc.on.doc") }
                }
                ShareLink(item: shareText) { Label("Поделиться", systemImage: "square.and.arrow.up") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text3).frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
        }
    }

    // Строка действий: лайк / комментарий / поделиться — иконки SF Symbols.
    private var actionBar: some View {
        HStack(spacing: 4) {
            Button(action: liked) {
                actionLabel(post.liked ? "heart.fill" : "heart", "\(post.likeCount)",
                            tint: post.liked ? Theme.accent : Theme.text2)
                    .scaleEffect(likeBounce ? 1.25 : 1)
            }
            Button(action: onComment) {
                actionLabel("bubble.right", "\(post.commentCount)", tint: Theme.text2)
            }
            Spacer()
            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 16))
                    .foregroundColor(Theme.text2).frame(width: 40, height: 34)
            }
        }
        .padding(.top, 2)
    }

    private func actionLabel(_ icon: String, _ count: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium))
            Text(count).font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
    }

    // Тап на лайк: мгновенная анимация сердечка + отдаём наверх.
    private func liked() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { likeBounce = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { likeBounce = false }
        }
        onLike()
    }

    private var shareText: String {
        let who = post.author?.name ?? "Пользователь"
        return post.text.isEmpty ? "Пост от \(who) в Localee" : "\(post.text)\n\n— \(who), Localee"
    }

    // Автор кликабелен только если известен.
    @ViewBuilder private func authorLink<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if let id = post.author?.id {
            NavigationLink { UserProfileScreen(userId: id) } label: { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }
}

// Лист комментариев к посту.
struct CommentsSheet: View {
    let post: Post
    var onCountChange: (Int) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var comments: [PostComment] = []
    @State private var text = ""
    @State private var loading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    if loading {
                        ProgressView().tint(Theme.accent).padding(.top, 30)
                    } else if comments.isEmpty {
                        Text("Комментариев пока нет").foregroundColor(Theme.text3).padding(.top, 30)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(comments) { c in
                                HStack(alignment: .top, spacing: 10) {
                                    AvatarView(avatar: c.author?.avatar ?? "", color: c.author?.color ?? "",
                                               letter: c.author?.letter ?? "", handle: c.author?.handle ?? "",
                                               name: c.author?.name ?? "", size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.author?.name ?? "Пользователь")
                                            .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                                        Text(c.text).font(.system(size: 15)).foregroundColor(Theme.text2)
                                        Text(timeAgo(c.createdAt)).font(.system(size: 12)).foregroundColor(Theme.text3)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                inputBar
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Комментарии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.tint(Theme.accent) } }
        }
        .presentationDetents([.large, .medium])
        .task { await load() }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("", text: $text, prompt: Text("Комментарий…").foregroundColor(Theme.text3), axis: .vertical)
                .foregroundColor(Theme.text).lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 20))
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                    .frame(width: 42, height: 42).background(Theme.accent).clipShape(Circle())
            }
            .opacity(text.trimmed.isEmpty ? 0.4 : 1)
            .disabled(text.trimmed.isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8).background(Theme.bg)
    }

    private func load() async {
        comments = (try? await API.shared.comments(postId: post.id)) ?? []
        loading = false
    }
    private func send() {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        text = ""
        Task {
            if let c = try? await API.shared.addComment(postId: post.id, text: t) {
                comments.append(c)
                onCountChange(comments.count)
            }
        }
    }
}
