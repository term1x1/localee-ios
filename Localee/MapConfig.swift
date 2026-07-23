import Foundation

// Настройки карты.
//
// Ключ НЕ лежит в коде: репозиторий публичный, а по ключу считается расход
// бесплатного тарифа (до 1000 пользователей в сутки) — чужие запросы съедали бы
// наш лимит. Поэтому ключ читается из файла Localee/Secrets.plist, который
// не попадает в git.
//
// Как настроить у себя:
//   1. Скопировать Secrets.example.plist из корня репозитория
//      в Localee/Secrets.plist
//   2. Вписать туда свой ключ MapKit Mobile SDK
//   3. Пересобрать
//
// Ключ берётся в кабинете https://developer.tech.yandex.ru — нужен именно
// **MapKit SDK**, а не JavaScript API (тот, что для сайта): это разные ключи.
// Привязывается к bundle id приложения (ru.localee.app).
//
// Без файла приложение НЕ падает: вместо карты показывается подсказка.
enum MapConfig {
    static let yandexMapKitKey: String = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let key = dict["YandexMapKitKey"] as? String
        else { return "" }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static var hasKey: Bool {
        !yandexMapKitKey.isEmpty && yandexMapKitKey != "ВСТАВЬТЕ_КЛЮЧ"
    }
}
