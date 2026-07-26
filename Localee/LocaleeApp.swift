import SwiftUI
import YandexMapsMobile

@main
struct LocaleeApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var gam = Gamification()
    @StateObject private var pinStore = PinStore()
    @StateObject private var postStore = PostStore()

    init() {
        // Яндекс.Карты инициализируем один раз при старте — обязательно ДО того,
        // как где-то появится YMKMapView. Без ключа не трогаем SDK вообще,
        // иначе он падает (вместо карты покажется подсказка — см. MapConfig).
        if MapConfig.hasKey {
            // setLocale здесь НЕ вызываем: в Lite-сборке SDK он объявлен в
            // заголовках, но отсутствует в самой библиотеке — приложение падало
            // с «unrecognized selector». Язык карты берётся системный, а это
            // ровно то, что нужно.
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
                .environmentObject(pinStore)
                .environmentObject(postStore)
                // Тему задаём на уровне окна (overrideUserInterfaceStyle), а не через
                // preferredColorScheme: только так выбор доходит и до модальных шитов —
                // preferredColorScheme в них не проникает, и цвета Theme оставались тёмными.
                .onAppear { applyTheme() }
                .onChange(of: themeRaw) { _, _ in applyTheme() }
                .task {
                    // Места приезжают с сервера — тот же список, что на сайте.
                    // Грузим параллельно со входом: они не зависят друг от друга.
                    async let places: Void = loadPlaces()
                    await store.boot()
                    await places
                    if store.user != nil { await gam.sync() }
                }
                // Вошли или сменили аккаунт — подтягиваем достижения с сервера,
                // вышли — убираем чужой прогресс с экрана.
                .onChange(of: store.user?.id) { _, id in
                    Task {
                        if id != nil { await gam.sync() } else { gam.reset() }
                    }
                    // Чистим общий кеш постов ТОЛЬКО при выходе (id стал nil).
                    // Раньше reset() дёргался и при входе — возникала гонка с
                    // загрузкой ленты, и посты пропадали с экрана.
                    if id == nil { postStore.reset() }
                }
        }
    }

    // Применяем выбранную тему ко всем окнам сцены. Окно управляет всей иерархией,
    // включая презентации (.sheet, .fullScreenCover), поэтому тема доходит везде.
    private func applyTheme() {
        let style: UIUserInterfaceStyle
        switch ThemeChoice(rawValue: themeRaw) {
        case .light: style = .light
        case .dark:  style = .dark
        default:     style = .unspecified   // «как в системе»
        }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = style }
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
