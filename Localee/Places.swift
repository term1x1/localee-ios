import Foundation

// Места приезжают с сервера (GET /api/places) — тот же список видит сайт.
// Раньше он лежал прямо здесь и дублировал src/data/places.ts на сайте, из-за
// чего файлы расходились; теперь источник правды один: server/src/data/places.js.
//
// PLACES остаётся обычным массивом, чтобы экраны и значки читали его как раньше.
// Локальная копия в UserDefaults — кеш: список рисуется мгновенно при запуске
// и не пропадает без сети.
@MainActor
var PLACES: [Place] = PlacesCache.load()

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
    guard let list = try? await API.shared.places(), !list.isEmpty else {
        return  // нет сети — остаёмся на кеше
    }
    PLACES = list
    PlacesCache.save(list)
}
