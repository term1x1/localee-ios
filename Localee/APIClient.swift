import Foundation

// Клиент API Localee. Тот же бэкенд, что у сайта и веб-версии.
enum APIError: LocalizedError {
    case network(String)
    case server(String)
    case unauthorized          // 401 — токен недействителен, надо разлогинить
    var errorDescription: String? {
        switch self {
        case .network(let m): return "Нет связи с сервером: \(m)"
        case .server(let m): return m
        case .unauthorized: return "Сессия истекла, войдите заново"
        }
    }
}

final class API {
    static let shared = API()
    private let base = URL(string: "https://api.localee.ru")!
    private let tokenKey = "localee_token"

    private let userKey = "localee_user"

    var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: tokenKey) }
            else { UserDefaults.standard.removeObject(forKey: tokenKey) }
        }
    }

    // Кеш последнего пользователя — чтобы вход переживал сетевые сбои при старте.
    var cachedUser: ApiUser? {
        get {
            guard let d = UserDefaults.standard.data(forKey: userKey) else { return nil }
            return try? JSONDecoder().decode(ApiUser.self, from: d)
        }
        set {
            if let u = newValue, let d = try? JSONEncoder().encode(u) {
                UserDefaults.standard.set(d, forKey: userKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userKey)
            }
        }
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        auth: Bool = false
    ) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        if !(200..<300).contains(code) {
            let msg = (try? JSONDecoder().decode(ApiErrorBody.self, from: data))?.error
            throw APIError.server(msg ?? "Ошибка \(code)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.server("Не удалось прочитать ответ сервера")
        }
    }

    // --- Авторизация ---
    func login(email: String, password: String) async throws -> ApiUser {
        let r: AuthResponse = try await request(
            "/api/auth/login", method: "POST",
            body: ["email": email, "password": password])
        token = r.token; cachedUser = r.user
        return r.user
    }
    func register(name: String, handle: String, email: String, password: String) async throws -> ApiUser {
        let r: AuthResponse = try await request(
            "/api/auth/register", method: "POST",
            body: ["name": name, "handle": handle, "email": email, "password": password])
        token = r.token; cachedUser = r.user
        return r.user
    }
    func me() async throws -> ApiUser {
        let r: MeResponse = try await request("/api/auth/me", auth: true)
        cachedUser = r.user
        return r.user
    }
    func logout() { token = nil; cachedUser = nil }

    // --- Чаты ---
    func chats() async throws -> [ChatListItem] {
        let r: ChatListResponse = try await request("/api/chats", auth: true)
        return r.chats
    }
    func messages(with userId: Int) async throws -> ChatMessagesResponse {
        try await request("/api/chats/\(userId)/messages", auth: true)
    }
    func send(to userId: Int, text: String) async throws -> ChatMessage {
        let r: SendMessageResponse = try await request(
            "/api/chats/\(userId)/messages", method: "POST",
            body: ["text": text], auth: true)
        return r.message
    }

    // --- Лента ---
    func feed() async throws -> [Post] {
        let r: FeedResponse = try await request("/api/posts?scope=all", auth: true)
        return r.posts
    }
    func createPost(text: String, image: String = "") async throws -> Post {
        var body: [String: Any] = ["text": text]
        if !image.isEmpty { body["image"] = image }
        let r: PostResponse = try await request("/api/posts", method: "POST", body: body, auth: true)
        return r.post
    }
    func like(postId: Int) async throws -> LikeResponse {
        try await request("/api/posts/\(postId)/like", method: "POST", auth: true)
    }
    func comments(postId: Int) async throws -> [PostComment] {
        let r: CommentsResponse = try await request("/api/posts/\(postId)/comments", auth: true)
        return r.comments
    }
    func addComment(postId: Int, text: String) async throws -> PostComment {
        let r: CommentResponse = try await request(
            "/api/posts/\(postId)/comments", method: "POST", body: ["text": text], auth: true)
        return r.comment
    }
    func userPosts(_ userId: Int) async throws -> [Post] {
        let r: FeedResponse = try await request("/api/posts/user/\(userId)", auth: true)
        return r.posts
    }
    func friends() async throws -> FriendsResponse {
        try await request("/api/friends", auth: true)
    }
    func updateMe(_ fields: [String: Any]) async throws -> ApiUser {
        let r: MeResponse = try await request("/api/auth/me", method: "PATCH", body: fields, auth: true)
        return r.user
    }

    // --- Метки на карте (скопления, сходки, дрифт) ---
    func pins() async throws -> [MapPin] {
        let r: PinsResponse = try await request("/api/pins", auth: true)
        return r.pins
    }
    func createPin(kind: String, lat: Double, lng: Double, note: String) async throws -> MapPin {
        let r: PinResponse = try await request(
            "/api/pins", method: "POST",
            body: ["kind": kind, "lat": lat, "lng": lng, "note": note], auth: true)
        return r.pin
    }
    func deletePin(id: Int) async throws {
        let _: OkResponse = try await request("/api/pins/\(id)", method: "DELETE", auth: true)
    }
}

// Относительное время из ISO-строки сервера.
func timeAgo(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    let s = iso.contains("T") ? iso : iso.replacingOccurrences(of: " ", with: "T") + "Z"
    guard let d = f.date(from: s) ?? {
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f2.date(from: s)
    }() else { return "" }
    let diff = Date().timeIntervalSince(d)
    if diff < 60 { return "только что" }
    if diff < 3600 { return "\(Int(diff / 60)) мин" }
    if diff < 86400 { return "\(Int(diff / 3600)) ч" }
    if diff < 172800 { return "вчера" }
    let df = DateFormatter(); df.dateFormat = "dd.MM"
    return df.string(from: d)
}
