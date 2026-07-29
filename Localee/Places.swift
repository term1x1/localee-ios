import Foundation
import SwiftUI

// Места приезжают с сервера (GET /api/places) — тот же список видит сайт.
// Раньше он лежал прямо здесь и дублировал src/data/places.ts на сайте, из-за
// чего файлы расходились; теперь источник правды один: server/src/data/places.js.
//
// Список лежит в ObservableObject, а НЕ в простой глобальной переменной. Он
// догружается с сервера уже после первого показа экранов, и SwiftUI обязан об
// этом узнать. Когда это был обычный `var`, на холодном старте с пустым кешем
// карта успевала отрисоваться с нулём мест, обновление списка проходило мимо
// SwiftUI — и метки не появлялись, пока экран не перерисуется по другой
// причине (переключение вкладки, фильтр). Приложение открывается сразу на
// карте, поэтому попадание в эту гонку было обычным делом.
//
// Локальная копия в UserDefaults — кеш: список рисуется мгновенно при запуске
// и не пропадает без сети.
@MainActor
final class PlacesStore: ObservableObject {
    static let shared = PlacesStore()

    @Published private(set) var list: [Place] = PlacesCache.load()

    private init() {}

    // Обновить список с сервера. Вызывается при старте приложения.
    func refresh() async {
        guard let fresh = try? await API.shared.places(), !fresh.isEmpty else {
            return  // нет сети — остаёмся на кеше
        }
        list = fresh
        PlacesCache.save(fresh)
    }
}

// Экраны и значки читают список как раньше — через PLACES. Внутри это то же
// хранилище, так что вьюхи, подписанные на PlacesStore, обновятся сами.
@MainActor
var PLACES: [Place] { PlacesStore.shared.list }

@MainActor
enum PlacesCache {
    private static let key = "localee_places"

    static func load() -> [Place] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Place].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [Place]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// Обновить список с сервера. Вызывается при старте приложения.
@MainActor
func loadPlaces() async {
    await PlacesStore.shared.refresh()
}
