import Foundation

// Настройки карты.
//
// Ключ НЕ лежит в коде: репозиторий публичный, а по ключу считается расход
// бесплатного тарифа (до 1000 пользователей в сутки) — чужие запросы съедали бы
// наш лимит. Поэтому ключ передаётся через файл Localee/Secrets.xcconfig, который
// не попадает в git, и на сборке прокидывается в Info.plist (см. project.yml).
//
// Как настроить у себя:
//   1. Скопировать Secrets.example.xcconfig из корня репозитория
//      в Localee/Secrets.xcconfig
//   2. Вписать туда свой ключ MapKit Mobile SDK
//   3. xcodegen generate && собрать
//
// Ключ берётся в кабинете https://developer.tech.yandex.ru — нужен именно
// **MapKit SDK**, а не JavaScript API (тот, что для сайта): это разные ключи.
// Привязывается к bundle id приложения (ru.localee.app).
//
// Без ключа приложение НЕ падает: вместо карты показывается подсказка.
enum MapConfig {
    static let yandexMapKitKey: String = {
        let key = Bundle.main.object(forInfoDictionaryKey: "YandexMapKitKey") as? String ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static var hasKey: Bool {
        !yandexMapKitKey.isEmpty && yandexMapKitKey != "ВСТАВЬТЕ_КЛЮЧ"
    }
}
