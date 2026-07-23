import SwiftUI

struct MainTabs: View {
    @State private var tab = 0

    init() {
        // Непрозрачный фон таб-бара в цвет приложения (как у шторки),
        // чтобы под иконками не просвечивала карта.
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x121013) : UIColor(rgb: 0xF2F2F6) }
        a.shadowColor = .clear  // без разделительной полоски сверху таб-бара
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }

    var body: some View {
        TabView(selection: $tab) {
            MapScreen()
                .toolbarBackground(Theme.bg, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem { Label("Карта", systemImage: "map.fill") }.tag(0)
            FeedScreen()
                .toolbarBackground(Theme.bg, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem { Label("Лента", systemImage: "square.stack.fill") }.tag(1)
            ChatsScreen()
                .toolbarBackground(Theme.bg, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }.tag(2)
            ProfileScreen()
                .toolbarBackground(Theme.bg, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }.tag(3)
        }
        .tint(Theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .goToMapTab)) { _ in tab = 0 }
    }
}

// Общий аватар: картинка с сервера или кружок с инициалами.
// Если сервер не прислал цвет/букву — считаем их детерминированно из ника,
// чтобы у пользователя всегда был свой узнаваемый аватар (а не синий круг с «1»).
struct AvatarView: View {
    let avatar: String
    let color: String
    let letter: String
    var handle: String = ""
    var name: String = ""
    var size: CGFloat = 44

    private var initials: String {
        let fromLetter = letter.trimmingCharacters(in: .whitespaces)
        if !fromLetter.isEmpty, fromLetter != "?" { return fromLetter.uppercased() }
        return avatarInitials(name: name, handle: handle)
    }
    private var bg: Color {
        let c = color.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty, c != "#888888" { return Color(hexString: c) }
        return avatarColor(for: handle.isEmpty ? name : handle)
    }

    var body: some View {
        if !avatar.isEmpty {
            NetImage(src: avatar) { Circle().fill(bg) }
                .scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
        } else {
            Circle().fill(bg)
                .frame(width: size, height: size)
                .overlay(Text(initials)
                    .font(.system(size: size * (initials.count > 1 ? 0.34 : 0.42), weight: .bold))
                    .foregroundColor(.white))
        }
    }
}

// Инициалы: «Иван Петров» → «ИП», иначе первая буква ника.
func avatarInitials(name: String, handle: String) -> String {
    let parts = name.split(separator: " ").filter { !$0.isEmpty }
    if parts.count >= 2 {
        return (parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
    }
    if let f = parts.first?.first { return String(f).uppercased() }
    if let f = handle.first { return String(f).uppercased() }
    return "?"
}

// Цвет фона — детерминированно из строки: один и тот же ник всегда даёт
// один и тот же цвет (на всех устройствах и запусках).
func avatarColor(for seed: String) -> Color {
    let palette: [UInt] = [
        0xFA3C3C, 0x3B82F6, 0x22C55E, 0xF59E0B, 0xC04CFF,
        0xD4537E, 0x0EA5E9, 0x7F77DD, 0xBA7517, 0x14B8A6,
    ]
    guard !seed.isEmpty else { return Color(hex: palette[0]) }
    // Простая стабильная хэш-функция (djb2) — Hashable в Swift рандомизирован
    var hash: UInt64 = 5381
    for b in seed.utf8 { hash = (hash &* 33) &+ UInt64(b) }
    return Color(hex: palette[Int(hash % UInt64(palette.count))])
}

// Переход на вкладку карты из других экранов (например из пустой ленты).
extension Notification.Name {
    static let goToMapTab = Notification.Name("localee_go_to_map_tab")
}
