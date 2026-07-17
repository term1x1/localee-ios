import SwiftUI
import PhotosUI

struct FeedScreen: View {
    @State private var posts: [Post] = []
    @State private var loading = true
    @State private var newText = ""
    @State private var sending = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoDataURL = ""      // выбранная картинка (data-URL)
    @State private var commentsFor: Post?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    composer
                    if loading {
                        ProgressView().tint(Theme.accent).padding(.top, 40)
                    } else if posts.isEmpty {
                        Text("Пока пусто — напишите первый пост!")
                            .foregroundColor(Theme.text3).padding(.top, 40)
                    } else {
                        ForEach(posts) { post in
                            PostCard(post: post, onLike: { like(post) }, onComment: { commentsFor = post })
                        }
                    }
                }
                .padding(14)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Лента")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .refreshable { await load() }
        }
        .task { await load() }
        .sheet(item: $commentsFor) { post in
            CommentsSheet(post: post) { newCount in
                if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].commentCount = newCount }
            }
        }
        .onChange(of: photoItem) { _, item in Task { await pickPhoto(item) } }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $newText, prompt: Text("Что нового?").foregroundColor(Theme.text3), axis: .vertical)
                .foregroundColor(Theme.text).lineLimit(1...5)

            if !photoDataURL.isEmpty {
                ZStack(alignment: .topTrailing) {
                    NetImage(src: photoDataURL) { Theme.bg2 }.scaledToFill()
                        .frame(height: 160).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button { photoDataURL = ""; photoItem = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            .padding(7).background(.black.opacity(0.5)).clipShape(Circle())
                    }
                    .padding(8)
                }
            }

            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo").font(.system(size: 20)).foregroundColor(Theme.accent)
                }
                Spacer()
                Button(action: publish) {
                    Text(sending ? "…" : "Опубликовать")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .opacity((newText.trimmed.isEmpty && photoDataURL.isEmpty) || sending ? 0.45 : 1)
            }
        }
        .padding(12).background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func load() async {
        do { posts = try await API.shared.feed() } catch {}
        loading = false
    }
    private func pickPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data), let url = imageToDataURL(img, maxDimension: 1200) else { return }
        photoDataURL = url
    }
    private func publish() {
        let t = newText.trimmed
        guard (!t.isEmpty || !photoDataURL.isEmpty), !sending else { return }
        sending = true
        Task {
            if let post = try? await API.shared.createPost(text: t, image: photoDataURL) {
                posts.insert(post, at: 0); newText = ""; photoDataURL = ""; photoItem = nil
            }
            sending = false
        }
    }
    private func like(_ post: Post) {
        guard let i = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[i].liked.toggle()
        posts[i].likeCount += posts[i].liked ? 1 : -1
        Task {
            if let r = try? await API.shared.like(postId: post.id),
               let j = posts.firstIndex(where: { $0.id == post.id }) {
                posts[j].liked = r.liked; posts[j].likeCount = r.likeCount
            }
        }
    }
}

struct PostCard: View {
    let post: Post
    let onLike: () -> Void
    var onComment: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(avatar: post.author?.avatar ?? "", color: post.author?.color ?? "#888",
                           letter: post.author?.letter ?? "?", size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.author?.name ?? "Пользователь")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    Text("@\(post.author?.handle ?? "") · \(timeAgo(post.createdAt))")
                        .font(.system(size: 13)).foregroundColor(Theme.text3)
                }
                Spacer()
            }
            if !post.text.isEmpty {
                Text(post.text).font(.system(size: 15.5)).foregroundColor(Theme.text).lineSpacing(3)
            }
            if !post.image.isEmpty {
                NetImage(src: post.image) { Theme.bg2 }.scaledToFill()
                    .frame(height: 240).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 22) {
                Button(action: onLike) {
                    Text("\(post.liked ? "♥" : "♡") \(post.likeCount)")
                        .foregroundColor(post.liked ? Theme.accent : Theme.text2)
                }
                Button(action: onComment) {
                    Text("💬 \(post.commentCount)").foregroundColor(Theme.text2)
                }
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .padding(14).background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                                    AvatarView(avatar: c.author?.avatar ?? "", color: c.author?.color ?? "#888",
                                               letter: c.author?.letter ?? "?", size: 34)
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
