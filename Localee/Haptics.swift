import UIKit

// Тактильный отклик — то, что делает интерфейс «живым» (лайк, отправка, ошибка).
// Обёртка, чтобы не плодить генераторы по всему коду.
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
