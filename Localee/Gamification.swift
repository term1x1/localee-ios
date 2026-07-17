import SwiftUI

// Одно посещение места (локально, как visits в localStorage на сайте).
struct Visit: Codable, Identifiable {
    let placeId: Int
    let at: Date
    var id: Int { placeId }
}

struct Badge: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let condition: ([Visit]) -> Bool
}

struct LevelInfo { let level: Int; let name: String; let next: Int }

// Все значки — перенос из src/data/badges.ts.
let BADGES: [Badge] = {
    func ids(_ cat: PlaceCategory) -> Set<Int> { Set(PLACES.filter { $0.category == cat }.map { $0.id }) }
    let museums = ids(.museum), parks = ids(.park), landmarks = ids(.landmark), restos = ids(.restaurant)
    let freeIds = Set(PLACES.filter { $0.price == 0 }.map { $0.id })
    func count(_ v: [Visit], _ s: Set<Int>) -> Int { v.filter { s.contains($0.placeId) }.count }
    return [
        Badge(id: "first_visit", title: "Первый шаг", description: "Отметь своё первое место", icon: "🥾") { $0.count >= 1 },
        Badge(id: "explorer_5", title: "Исследователь", description: "Посети 5 мест", icon: "🗺️") { $0.count >= 5 },
        Badge(id: "explorer_10", title: "Бывалый странник", description: "Посети 10 мест", icon: "🧭") { $0.count >= 10 },
        Badge(id: "explorer_all", title: "Покоритель Москвы", description: "Посети все места", icon: "🏆") { $0.count >= PLACES.count },
        Badge(id: "museum_lover", title: "Ценитель искусства", description: "Посети 3 музея", icon: "🎨") { count($0, museums) >= 3 },
        Badge(id: "park_walker", title: "Любитель природы", description: "Посети 4 парка", icon: "🌳") { count($0, parks) >= 4 },
        Badge(id: "landmark_hunter", title: "Охотник за достопримечательностями", description: "Посети 5 достопримечательностей", icon: "🏛️") { count($0, landmarks) >= 5 },
        Badge(id: "foodie", title: "Гурман", description: "Посети 2 ресторана", icon: "🍽️") { count($0, restos) >= 2 },
        Badge(id: "kremlin_visitor", title: "Гость Кремля", description: "Посети Московский Кремль", icon: "🏰") { $0.contains { $0.placeId == 2 } },
        Badge(id: "viewpoint", title: "С высоты птичьего полёта", description: "Воробьёвы горы или Останкино", icon: "🔭") { $0.contains { $0.placeId == 7 || $0.placeId == 17 } },
        Badge(id: "free_spirit", title: "Бесплатный дух", description: "Посети 5 бесплатных мест", icon: "🆓") { count($0, freeIds) >= 5 },
        Badge(id: "weekend_warrior", title: "Выходной герой", description: "Посети 3 места за один день", icon: "⚡") { visits in
            let byDay = Dictionary(grouping: visits) { Calendar.current.startOfDay(for: $0.at) }
            return byDay.values.contains { $0.count >= 3 }
        },
    ]
}()

let LEVELS: [(level: Int, name: String, min: Int)] = [
    (1, "Новичок", 0), (2, "Исследователь", 300), (3, "Знаток города", 1000), (4, "Гид", 2500), (5, "Мастер", 5000),
]

// Хранилище посещений + вычисление достижений. Инжектится через environment.
@MainActor
final class Gamification: ObservableObject {
    @Published private(set) var visits: [Visit] = []
    private let key = "localee_visits"

    init() { load() }

    func isVisited(_ placeId: Int) -> Bool { visits.contains { $0.placeId == placeId } }

    func toggleVisit(_ placeId: Int) {
        if isVisited(placeId) { visits.removeAll { $0.placeId == placeId } }
        else { visits.append(Visit(placeId: placeId, at: Date())) }
        save()
    }

    var unlocked: [Badge] { BADGES.filter { $0.condition(visits) } }
    var unlockedCount: Int { unlocked.count }
    var placesCount: Int { visits.count }
    var points: Int { visits.count * 100 + unlockedCount * 50 }

    var levelInfo: LevelInfo {
        var cur = LEVELS[0]
        for l in LEVELS where points >= l.min { cur = l }
        let next = LEVELS.first { $0.min > cur.min }
        return LevelInfo(level: cur.level, name: cur.name, next: next?.min ?? cur.min)
    }
    var progress: Double {
        let n = levelInfo.next
        return n > 0 ? min(1, Double(points) / Double(n)) : 1
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode([Visit].self, from: d) else { return }
        visits = v
    }
    private func save() {
        if let d = try? JSONEncoder().encode(visits) { UserDefaults.standard.set(d, forKey: key) }
    }
}
