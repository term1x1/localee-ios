import SwiftUI

// Глобальное состояние авторизации: держит текущего пользователя,
// проверяет сохранённый токен при старте.
@MainActor
final class AppStore: ObservableObject {
    @Published var user: ApiUser?
    @Published var booting = true
    // Причина блокировки, если аккаунт забанили. Показываем на экране входа:
    // без неё выход выглядел бы как поломка приложения.
    @Published var banNotice = ""

    func boot() async {
        guard API.shared.token != nil else { booting = false; return }
        // Оптимистично показываем закешированного юзера — вход не мигает при плохой сети.
        user = API.shared.cachedUser
        booting = false
        do {
            user = try await API.shared.me() // обновим свежими данными
        } catch APIError.unauthorized {
            signOut() // только настоящий протухший токен разлогинивает
        } catch APIError.banned(let message) {
            banNotice = message
            signOut()
        } catch {
            // сетевой сбой — остаёмся в приложении на кеше
        }
    }

    func signIn(_ u: ApiUser) { user = u; banNotice = "" }

    func signOut() {
        API.shared.logout()
        user = nil
    }
}
