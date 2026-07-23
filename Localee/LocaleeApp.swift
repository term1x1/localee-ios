import SwiftUI
import YandexMapsMobile

@main
struct LocaleeApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var gam = Gamification()

    init() {
        // Яндекс.Карты инициализируем один раз при старте — обязательно ДО того,
        // как где-то появится YMKMapView. Без ключа не трогаем SDK вообще,
        // иначе он падает (вместо карты покажется подсказка — см. MapConfig).
        if MapConfig.hasKey {
            YMKMapKit.setLocale("ru_RU")
            YMKMapKit.setApiKey(MapConfig.yandexMapKitKey)
            YMKMapKit.sharedInstance()
        }
    }

    // Выбранная тема (настройки). nil = как в системе.
    @AppStorage(ThemeChoice.storageKey) private var themeRaw = ThemeChoice.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(gam)
                .preferredColorScheme(ThemeChoice(rawValue: themeRaw)?.colorScheme)
                .task {
                    await store.boot()
                    if store.user != nil { await gam.sync() }
                }
                // Вошли или сменили аккаунт — подтягиваем достижения с сервера,
                // вышли — убираем чужой прогресс с экрана.
                .onChange(of: store.user?.id) { _, id in
                    Task { if id != nil { await gam.sync() } else { gam.reset() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if store.booting {
                ProgressView().tint(Theme.accent)
            } else if store.user == nil {
                AuthView()
            } else {
                MainTabs()
            }
        }
    }
}
