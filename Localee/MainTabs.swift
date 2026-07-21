import SwiftUI

struct MainTabs: View {
    @State private var tab = 0

    init() {
        // Непрозрачный фон таб-бара в цвет приложения (как у шторки),
        // чтобы под иконками не просвечивала карта.
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x121013) : UIColor(rgb: 0xF2F2F6) }
        a.shadowColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.08) }
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }

    var body: some View {
        TabView(selection: $tab) {
            MapScreen()
                .tabItem { Label("Карта", systemImage: "map.fill") }.tag(0)
            FeedScreen()
                .tabItem { Label("Лента", systemImage: "square.stack.fill") }.tag(1)
            ChatsScreen()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }.tag(2)
            ProfileScreen()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }.tag(3)
        }
        .tint(Theme.accent)
    }
}

// Общий аватар: картинка с сервера или кружок с буквой.
struct AvatarView: View {
    let avatar: String
    let color: String
    let letter: String
    var size: CGFloat = 44

    var body: some View {
        if !avatar.isEmpty {
            NetImage(src: avatar) {
                Circle().fill(Color(hexString: color))
            }
            .scaledToFill()
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            Circle().fill(Color(hexString: color))
                .frame(width: size, height: size)
                .overlay(Text(letter.isEmpty ? "?" : letter)
                    .font(.system(size: size * 0.42, weight: .bold)).foregroundColor(.white))
        }
    }
}
