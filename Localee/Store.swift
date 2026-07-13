import SwiftUI

// Глобальное состояние авторизации: держит текущего пользователя,
// проверяет сохранённый токен при старте.
@MainActor
final class AppStore: ObservableObject {
    @Published var user: ApiUser?
    @Published var booting = true

    func boot() async {
        guard API.shared.token != nil else { booting = false; return }
        // Оптимистично показываем закешированного юзера — вход не мигает при плохой сети.
        user = API.shared.cachedUser
        booting = false
        do {
            user = try await API.shared.me() // обновим свежими данными
        } catch APIError.unauthorized {
            signOut() // только настоящий протухший токен разлогинивает
        } catch {
            // сетевой сбой — остаёмся в приложении на кеше
        }
    }

    func signIn(_ u: ApiUser) { user = u }

    func signOut() {
        API.shared.logout()
        user = nil
    }
}
