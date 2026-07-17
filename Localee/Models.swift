import SwiftUI

// --- Места (локальные данные, как на сайте) ---
enum PlaceCategory: String, Codable {
    case landmark, park, museum, restaurant, entertainment, nightlife

    var label: String {
        switch self {
        case .landmark: return "Достопримечательность"
        case .park: return "Парк"
        case .museum: return "Музей"
        case .restaurant: return "Ресторан"
        case .entertainment: return "Развлечения"
        case .nightlife: return "18+ · Ночная жизнь"
        }
    }
    var color: Color {
        switch self {
        case .landmark: return Color(hex: 0xFA3C3C)
        case .park: return Color(hex: 0x378ADD)
        case .museum: return Color(hex: 0xD4537E)
        case .restaurant: return Color(hex: 0xBA7517)
        case .entertainment: return Color(hex: 0x7F77DD)
        case .nightlife: return Color(hex: 0xC04CFF)
        }
    }
}

struct Place: Identifiable {
    let id: Int
    let name: String
    let category: PlaceCategory
    let description: String
    let address: String
    let lat: Double
    let lng: Double
    let price: Int
    let duration: Int
    let rating: Double
    let imageUrl: String
}

// --- Сетевые модели (зеркало ответов api.localee.ru) ---
// Сервер отдаёт всю строку БД: часть полей может быть null у новых юзеров,
// поэтому декодируем через decodeIfPresent — устойчиво и к null, и к отсутствию.
struct ApiUser: Codable, Identifiable {
    let id: Int
    var handle: String = ""
    var name: String = ""
    var email: String = ""
    var color: String = "#888888"
    var letter: String = "?"
    var bio: String = ""
    var city: String = ""
    var avatar: String = ""
    var cover: String = ""
    var role: String = "user"

    enum CodingKeys: String, CodingKey {
        case id, handle, name, email, color, letter, bio, city, avatar, cover, role
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        handle = (try? c.decodeIfPresent(String.self, forKey: .handle) ?? "") ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name) ?? "") ?? ""
        email = (try? c.decodeIfPresent(String.self, forKey: .email) ?? "") ?? ""
        color = (try? c.decodeIfPresent(String.self, forKey: .color) ?? "") ?? ""
        letter = (try? c.decodeIfPresent(String.self, forKey: .letter) ?? "") ?? ""
        bio = (try? c.decodeIfPresent(String.self, forKey: .bio) ?? "") ?? ""
        city = (try? c.decodeIfPresent(String.self, forKey: .city) ?? "") ?? ""
        avatar = (try? c.decodeIfPresent(String.self, forKey: .avatar) ?? "") ?? ""
        cover = (try? c.decodeIfPresent(String.self, forKey: .cover) ?? "") ?? ""
        role = (try? c.decodeIfPresent(String.self, forKey: .role) ?? "user") ?? "user"
        if color.isEmpty { color = "#888888" }
        if letter.isEmpty { letter = name.first.map { String($0).uppercased() } ?? "?" }
    }
    init(id: Int) { self.id = id }
}

struct AuthResponse: Codable {
    let token: String
    let user: ApiUser
}
struct MeResponse: Codable { let user: ApiUser }

struct ChatUser: Codable, Identifiable {
    let id: Int
    var name: String = ""
    var handle: String = ""
    var color: String = "#888888"
    var letter: String = "?"
    var avatar: String = ""
    var online: Bool? = nil

    enum CodingKeys: String, CodingKey { case id, name, handle, color, letter, avatar, online }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decodeIfPresent(String.self, forKey: .name) ?? "") ?? ""
        handle = (try? c.decodeIfPresent(String.self, forKey: .handle) ?? "") ?? ""
        color = (try? c.decodeIfPresent(String.self, forKey: .color) ?? "") ?? ""
        letter = (try? c.decodeIfPresent(String.self, forKey: .letter) ?? "") ?? ""
        avatar = (try? c.decodeIfPresent(String.self, forKey: .avatar) ?? "") ?? ""
        online = try? c.decodeIfPresent(Bool.self, forKey: .online)
        if color.isEmpty { color = "#888888" }
        if letter.isEmpty { letter = name.first.map { String($0).uppercased() } ?? "?" }
    }
    init(id: Int, name: String, handle: String, color: String, letter: String, avatar: String = "") {
        self.id = id; self.name = name; self.handle = handle
        self.color = color; self.letter = letter; self.avatar = avatar
    }
}
struct LastMessage: Codable {
    let text: String
    let fromMe: Bool
    let createdAt: String
}
struct ChatListItem: Codable, Identifiable {
    var id: Int { user.id }
    let user: ChatUser
    let last: LastMessage?
    let unread: Int
}
struct ChatListResponse: Codable { let chats: [ChatListItem] }

struct ChatMessage: Codable, Identifiable {
    let id: Int
    let fromMe: Bool
    let text: String
    let createdAt: String
    var edited: Bool = false
}
struct ChatMessagesResponse: Codable {
    let user: ChatUser
    let messages: [ChatMessage]
}
struct SendMessageResponse: Codable { let message: ChatMessage }

struct Post: Codable, Identifiable {
    let id: Int
    let author: ChatUser?
    let text: String
    var image: String = ""
    let createdAt: String
    var likeCount: Int
    var liked: Bool
    var commentCount: Int
    var mine: Bool = false
}
struct FeedResponse: Codable { let posts: [Post] }
struct PostResponse: Codable { let post: Post }
struct LikeResponse: Codable { let liked: Bool; let likeCount: Int }

struct PostComment: Codable, Identifiable {
    let id: Int
    let text: String
    let createdAt: String
    let author: ChatUser?
    var mine: Bool = false
}
struct CommentsResponse: Codable { let comments: [PostComment] }
struct CommentResponse: Codable { let comment: PostComment }

// --- Метки на карте ---
struct PinAuthor: Codable { let name: String; let handle: String }
struct MapPin: Codable, Identifiable {
    let id: Int
    let kind: String        // "crowd" | "meetup" | "drift"
    let note: String
    let lat: Double
    let lng: Double
    let createdAt: String
    let mine: Bool
    let author: PinAuthor?

    var emoji: String {
        switch kind {
        case "crowd": return "👥"
        case "meetup": return "📣"
        case "drift": return "🏎️"
        default: return "📍"
        }
    }
    var title: String {
        switch kind {
        case "crowd": return "Скопление людей"
        case "meetup": return "Сходка"
        case "drift": return "Дрифт-гонки"
        default: return "Метка"
        }
    }
}
struct FriendsResponse: Codable {
    let friends: [ChatUser]
    let incoming: [ChatUser]
    let outgoing: [ChatUser]
}

struct PinsResponse: Codable { let pins: [MapPin] }
struct PinResponse: Codable { let pin: MapPin }
struct OkResponse: Codable { let ok: Bool? }

struct ApiErrorBody: Codable { let error: String? }
