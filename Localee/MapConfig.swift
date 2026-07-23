import Foundation

// Настройки карты.
//
// ВАЖНО: нужен ключ именно **MapKit Mobile SDK**, а не ключ JavaScript API
// Яндекс.Карт (тот, что для сайта) — это разные ключи, друг к другу не подходят.
//
// Где взять:
//   1. https://developer.tech.yandex.ru → «Подключить API» → MapKit Mobile SDK
//   2. Дождаться выдачи ключа (бесплатная версия Lite — по заявке)
//   3. Вставить ключ в строку ниже вместо ВСТАВЬТЕ_КЛЮЧ
//
// Ключ привязывается к bundle id приложения (ru.localee.app), поэтому чужому
// приложению он не подойдёт.
enum MapConfig {
    static let yandexMapKitKey = "ВСТАВЬТЕ_КЛЮЧ"

    // Пока ключ не вписан, приложение не падает, а показывает подсказку вместо карты.
    static var hasKey: Bool {
        !yandexMapKitKey.isEmpty && yandexMapKitKey != "ВСТАВЬТЕ_КЛЮЧ"
    }
}
