import SwiftUI

// Локальный слой поверх серверных меток: TTL, подтверждения «Актуально»,
// скрытия «Уже нет» и фото. На сервере у метки этих полей нет, поэтому
// храним рядом (UserDefaults) и накладываем при отображении.
@MainActor
final class PinStore: ObservableObject {
    static let ttl: TimeInterval = 3 * 3600      // 3 часа по умолчанию
    static let extendBy: TimeInterval = 3 * 3600 // «Актуально» продлевает на 3 часа

    @Published private var confirmedAt: [Int: Date] = [:]   // id → когда подтвердили
    @Published private var dismissed: Set<Int> = []         // «Уже нет» — прячем
    @Published private var photos: [Int: [String]] = [:]    // id → data-URL фото

    private let kConfirm = "localee_pin_confirmed"
    private let kDismiss = "localee_pin_dismissed"
    private let kPhotos  = "localee_pin_photos"

    init() { load() }

    // Срок жизни: от создания, либо от последнего подтверждения
    func expiry(of pin: MapPin) -> Date {
        let base = confirmedAt[pin.id] ?? parseDate(pin.createdAt) ?? Date()
        let span = confirmedAt[pin.id] != nil ? Self.extendBy : Self.ttl
        return base.addingTimeInterval(span)
    }
    func isAlive(_ pin: MapPin) -> Bool {
        !dismissed.contains(pin.id) && expiry(of: pin) > Date()
    }
    func isConfirmed(_ pin: MapPin) -> Bool { confirmedAt[pin.id] != nil }

    /// Сколько осталось: «ещё 2 ч 15 мин» / «истекает»
    func remainingText(_ pin: MapPin) -> String {
        let left = expiry(of: pin).timeIntervalSinceNow
        if left <= 0 { return "истекла" }
        let h = Int(left) / 3600, m = (Int(left) % 3600) / 60
        return h > 0 ? "ещё \(h) ч \(m) мин" : "ещё \(m) мин"
    }

    func confirm(_ pin: MapPin) { confirmedAt[pin.id] = Date(); save() }
    func dismiss(_ pin: MapPin) { dismissed.insert(pin.id); save() }

    func photos(of pin: MapPin) -> [String] { photos[pin.id] ?? [] }
    func setPhotos(_ list: [String], for id: Int) {
        if list.isEmpty { photos.removeValue(forKey: id) } else { photos[id] = list }
        save()
    }

    private func parseDate(_ iso: String) -> Date? {
        let s = iso.contains("T") ? iso : iso.replacingOccurrences(of: " ", with: "T") + "Z"
        return ISO8601DateFormatter().date(from: s)
    }

    private func load() {
        let d = UserDefaults.standard
        if let raw = d.dictionary(forKey: kConfirm) as? [String: Double] {
            confirmedAt = Dictionary(uniqueKeysWithValues: raw.compactMap {
                guard let id = Int($0.key) else { return nil }
                return (id, Date(timeIntervalSince1970: $0.value))
            })
        }
        dismissed = Set((d.array(forKey: kDismiss) as? [Int]) ?? [])
        photos = (d.dictionary(forKey: kPhotos) as? [String: [String]])
            .map { Dictionary(uniqueKeysWithValues: $0.compactMap {
                guard let id = Int($0.key) else { return nil }
                return (id, $0.value)
            }) } ?? [:]
    }
    private func save() {
        let d = UserDefaults.standard
        d.set(Dictionary(uniqueKeysWithValues: confirmedAt.map { (String($0.key), $0.value.timeIntervalSince1970) }), forKey: kConfirm)
        d.set(Array(dismissed), forKey: kDismiss)
        d.set(Dictionary(uniqueKeysWithValues: photos.map { (String($0.key), $0.value) }), forKey: kPhotos)
    }
}

// Возраст метки: «только что» / «15 мин назад» / «2 ч назад»
func pinAgeText(_ iso: String) -> String {
    let s = iso.contains("T") ? iso : iso.replacingOccurrences(of: " ", with: "T") + "Z"
    guard let d = ISO8601DateFormatter().date(from: s) else { return "" }
    let diff = Date().timeIntervalSince(d)
    if diff < 60 { return "только что" }
    if diff < 3600 { return "\(Int(diff / 60)) мин назад" }
    return "\(Int(diff / 3600)) ч назад"
}
