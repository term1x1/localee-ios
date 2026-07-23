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
    // SF Symbol категории — для пинов на карте и фолбэка галереи
    var icon: String {
        switch self {
        case .landmark: return "building.columns.fill"
        case .park: return "tree.fill"
        case .museum: return "paintpalette.fill"
        case .restaurant: return "fork.knife"
        case .entertainment: return "star.fill"
        case .nightlife: return "moon.stars.fill"
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
    let ratingCount: Int        // сколько оценок — «4,9 (127)»
    let tags: [String]
    let imageUrl: String
    let photos: [String]        // галерея; пустая строка = градиент-заглушка
    let opensAt: String         // "HH:mm"
    let closesAt: String        // "HH:mm"; пусто = круглосуточно

    // Сейчас открыто? Учитываем ночные заведения (закрытие после полуночи).
    var isOpenNow: Bool {
        guard !closesAt.isEmpty else { return true }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let cur = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        func mins(_ s: String) -> Int {
            let p = s.split(separator: ":")
            return (Int(p.first ?? "0") ?? 0) * 60 + (Int(p.last ?? "0") ?? 0)
        }
        let o = mins(opensAt), c = mins(closesAt)
        return o <= c ? (cur >= o && cur < c) : (cur >= o || cur < c)  // через полночь
    }
    var hoursText: String {
        if closesAt.isEmpty { return "Открыто круглосуточно" }
        return isOpenNow ? "Открыто до \(closesAt)" : "Закрыто"
    }
    // Иконка категории — для фолбэка галереи и пинов на карте
    var categoryIcon: String { category.icon }
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
    var birthdate: String = ""     // 'YYYY-MM-DD' или ''
    var gender: String = ""        // '' | 'male' | 'female' | 'other'
    var interests: String = ""     // через запятую
    var createdAt: String = ""

    var interestList: [String] {
        interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case id, handle, name, email, color, letter, bio, city, avatar, cover, role
        case birthdate, gender, interests
        case createdAt = "created_at"
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys, _ def: String = "") -> String {
            ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? def
        }
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        handle = str(.handle); name = str(.name); email = str(.email)
        color = str(.color); letter = str(.letter); bio = str(.bio); city = str(.city)
        avatar = str(.avatar); cover = str(.cover); role = str(.role, "user")
        birthdate = str(.birthdate); gender = str(.gender); interests = str(.interests)
        createdAt = str(.createdAt)
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

struct ReplyPreview: Codable {
    let id: Int
    var text: String = ""
    var fromMe: Bool = false
    var author: String? = nil
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        text = ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? ""
        fromMe = ((try? c.decodeIfPresent(Bool.self, forKey: .fromMe)) ?? nil) ?? false
        author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? nil
    }
    enum CodingKeys: String, CodingKey { case id, text, fromMe, author }
}

struct ChatMessage: Codable, Identifiable {
    let id: Int
    var fromMe: Bool = false
    var text: String = ""
    var createdAt: String = ""
    var edited: Bool = false
    var forwardedFrom: String = ""
    var replyTo: ReplyPreview? = nil
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        fromMe = ((try? c.decodeIfPresent(Bool.self, forKey: .fromMe)) ?? nil) ?? false
        text = ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? ""
        createdAt = ((try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil) ?? ""
        edited = ((try? c.decodeIfPresent(Bool.self, forKey: .edited)) ?? nil) ?? false
        forwardedFrom = ((try? c.decodeIfPresent(String.self, forKey: .forwardedFrom)) ?? nil) ?? ""
        replyTo = (try? c.decodeIfPresent(ReplyPreview.self, forKey: .replyTo)) ?? nil
    }
    enum CodingKeys: String, CodingKey { case id, fromMe, text, createdAt, edited, forwardedFrom, replyTo }
}
struct ChatMessagesResponse: Codable {
    let user: ChatUser
    let messages: [ChatMessage]
}
struct SendMessageResponse: Codable { let message: ChatMessage }

// --- Группы ---
struct GroupInfo: Codable, Identifiable {
    let id: Int
    var name: String = ""
    var color: String = "#888888"
    var letter: String = "?"
    var ownerId: Int = 0
    var inviteToken: String = ""
    var memberCount: Int = 0
    enum CodingKeys: String, CodingKey { case id, name, color, letter, ownerId, inviteToken, memberCount }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        color = ((try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil) ?? "#888888"
        letter = ((try? c.decodeIfPresent(String.self, forKey: .letter)) ?? nil) ?? "?"
        ownerId = ((try? c.decodeIfPresent(Int.self, forKey: .ownerId)) ?? nil) ?? 0
        inviteToken = ((try? c.decodeIfPresent(String.self, forKey: .inviteToken)) ?? nil) ?? ""
        memberCount = ((try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? nil) ?? 0
        if color.isEmpty { color = "#888888" }
        if letter.isEmpty { letter = name.first.map { String($0).uppercased() } ?? "#" }
    }
}
struct GroupLast: Codable { let text: String; let fromMe: Bool; let author: String; let createdAt: String }
struct GroupListItem: Codable, Identifiable {
    let id: Int
    let name: String
    let color: String
    let letter: String
    let memberCount: Int
    let last: GroupLast?
    let unread: Int
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        color = ((try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil) ?? "#888888"
        letter = ((try? c.decodeIfPresent(String.self, forKey: .letter)) ?? nil) ?? "#"
        memberCount = ((try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? nil) ?? 0
        last = (try? c.decodeIfPresent(GroupLast.self, forKey: .last)) ?? nil
        unread = ((try? c.decodeIfPresent(Int.self, forKey: .unread)) ?? nil) ?? 0
    }
    enum CodingKeys: String, CodingKey { case id, name, color, letter, memberCount, last, unread }
}
struct GroupSender: Codable { let id: Int; let name: String; let color: String; let letter: String; var avatar: String = "" }
struct GroupMessage: Codable, Identifiable {
    let id: Int
    var fromMe = false
    var text = ""
    var createdAt = ""
    var edited = false
    var forwardedFrom = ""
    var replyTo: ReplyPreview? = nil
    var sender: GroupSender? = nil
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        fromMe = ((try? c.decodeIfPresent(Bool.self, forKey: .fromMe)) ?? nil) ?? false
        text = ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? ""
        createdAt = ((try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil) ?? ""
        edited = ((try? c.decodeIfPresent(Bool.self, forKey: .edited)) ?? nil) ?? false
        forwardedFrom = ((try? c.decodeIfPresent(String.self, forKey: .forwardedFrom)) ?? nil) ?? ""
        replyTo = (try? c.decodeIfPresent(ReplyPreview.self, forKey: .replyTo)) ?? nil
        sender = (try? c.decodeIfPresent(GroupSender.self, forKey: .sender)) ?? nil
    }
    enum CodingKeys: String, CodingKey { case id, fromMe, text, createdAt, edited, forwardedFrom, replyTo, sender }
}
struct GroupListResponse: Codable { let groups: [GroupListItem] }
struct GroupResponse: Codable { let group: GroupInfo }
struct GroupInfoResponse: Codable { let group: GroupInfo; let members: [ChatUser] }
struct GroupMessagesResponse: Codable { let group: GroupInfo; let messages: [GroupMessage] }
struct GroupMessageResponse: Codable { let message: GroupMessage }
struct UsersSearchResponse: Codable { let users: [ChatUser] }

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

struct PhotoItem: Codable, Identifiable {
    let postId: Int
    let image: String
    let createdAt: String
    var id: Int { postId }
}
struct PhotosResponse: Codable { let photos: [PhotoItem] }

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

// Посещённое место с сервера. Заметку приложение пока не показывает, но
// принимаем её, чтобы не терять текст, написанный на сайте.
struct ApiVisit: Codable {
    let placeId: Int
    let visitedAt: String
    let note: String?
}
struct VisitsResponse: Codable { let visits: [ApiVisit] }
struct VisitResponse: Codable { let visit: ApiVisit }

struct ApiErrorBody: Codable { let error: String? }
