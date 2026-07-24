import SwiftUI

// Единое хранилище постов на весь клиент.
//
// Пост — одна сущность: и Лента, и стена профиля читают ОДИН массив.
// Лента показывает все посты, профиль — отфильтрованные по автору. Поэтому
// пост, опубликованный из профиля, сразу виден в Ленте, и наоборот — без
// перезагрузки экрана. На сервере посты и так общие (GET /api/posts), здесь мы
// лишь держим единую клиентскую копию, чтобы вкладки не расходились.
@MainActor
final class PostStore: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var loaded = false
    private var loading = false

    // Грузим ленту один раз. Повторные заходы на вкладки ничего не дёргают.
    func loadIfNeeded() async {
        guard !loaded, !loading else { return }
        await refresh()
    }

    func refresh() async {
        loading = true
        // Помечаем «загружено» после ЛЮБОЙ попытки (успех или сбой), иначе при
        // отсутствии сети спиннер крутился бы вечно. Пустой стейт честнее.
        defer { loaded = true; loading = false }
        if let p = try? await API.shared.feed() { posts = p }
    }

    // Новый пост появляется вверху общего списка — виден и в Ленте, и в профиле.
    func prepend(_ p: Post) { posts.insert(p, at: 0) }

    // Посты конкретного автора (стена профиля).
    func byAuthor(_ userId: Int) -> [Post] {
        posts.filter { ($0.author?.id ?? -1) == userId }
    }
    func countByAuthor(_ userId: Int) -> Int { byAuthor(userId).count }

    // MARK: лайки/комментарии — правим в одном месте, меняется везде

    // Оптимистичное переключение лайка до ответа сервера.
    func toggleLike(_ id: Int) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].liked.toggle()
        posts[i].likeCount += posts[i].liked ? 1 : -1
    }
    func applyLike(_ id: Int, liked: Bool, count: Int) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].liked = liked
        posts[i].likeCount = count
    }
    func setCommentCount(_ id: Int, _ n: Int) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].commentCount = n
    }

    func reset() { posts = []; loaded = false }
}
