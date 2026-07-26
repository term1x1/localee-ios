import SwiftUI

// Настройки приложения.
//
// Приватность хранится на сервере — те же тумблеры видит сайт.
// Тема живёт только на устройстве: это оформление конкретного телефона,
// а не свойство аккаунта.
struct SettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @AppStorage(ThemeChoice.storageKey) private var themeRaw = ThemeChoice.system.rawValue

    @State private var showOnline = true
    @State private var showBirthyear = true
    // Пока не подставили значения из профиля, тумблеры не шлют ничего на сервер:
    // иначе простое открытие настроек уже отправляло бы запрос.
    @State private var ready = false
    @State private var saving = false
    @State private var error = ""
    @State private var support = false

    // Уведомления живут на устройстве (пуши ещё не подключены — храним выбор локально).
    @AppStorage("notif_pins_nearby") private var notifPins = true
    @AppStorage("notif_messages") private var notifMessages = true
    @AppStorage("notif_events_nearby") private var notifEvents = true
    @AppStorage("notif_friends_activity") private var notifFriends = true

    // Удаление аккаунта — двухшаговое подтверждение (требование App Store).
    @State private var showDeleteWarn = false
    @State private var showDeleteConfirm = false
    @State private var deleteText = ""

    private var hasBirthdate: Bool { !(store.user?.birthdate ?? "").isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !error.isEmpty {
                        Text(error).font(.system(size: 13)).foregroundColor(Theme.accent)
                            .padding(.horizontal, 16)
                    }

                    section("ОФОРМЛЕНИЕ") {
                        ForEach(ThemeChoice.selectable) { choice in
                            row {
                                Button { themeRaw = choice.rawValue } label: {
                                    HStack {
                                        Label(choice.title, systemImage: choice.icon)
                                            .font(.system(size: 16)).foregroundColor(Theme.text)
                                        Spacer()
                                        if themeRaw == choice.rawValue {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(Theme.accent)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    section("УВЕДОМЛЕНИЯ") {
                        row { localToggle("Метки рядом", isOn: $notifPins) }
                        row { localToggle("Сообщения", isOn: $notifMessages) }
                        row { localToggle("События поблизости", isOn: $notifEvents) }
                        row { localToggle("Активность друзей", isOn: $notifFriends) }
                    }

                    section("ПРИВАТНОСТЬ") {
                        row {
                            toggle("Показывать, что я в сети", isOn: $showOnline) { v in
                                await savePrivacy(["show_online": v ? 1 : 0]) { showOnline = !v }
                            }
                        }
                        row {
                            VStack(alignment: .leading, spacing: 4) {
                                toggle("Показывать год рождения", isOn: $showBirthyear, enabled: hasBirthdate) { v in
                                    await savePrivacy(["show_birthyear": v ? 1 : 0]) { showBirthyear = !v }
                                }
                                if !hasBirthdate {
                                    Text("Укажите дату рождения в профиле")
                                        .font(.system(size: 12)).foregroundColor(Theme.text3)
                                }
                            }
                        }
                    }

                    section("ПОМОЩЬ") {
                        row {
                            Button { support = true } label: {
                                HStack {
                                    Label("Написать в поддержку", systemImage: "lifepreserver")
                                        .font(.system(size: 16)).foregroundColor(Theme.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.text3)
                                }
                            }
                        }
                    }

                    section("АККАУНТ") {
                        row {
                            HStack {
                                Text("Почта").font(.system(size: 16)).foregroundColor(Theme.text)
                                Spacer()
                                Text(store.user?.email ?? "—")
                                    .font(.system(size: 15)).foregroundColor(Theme.text3)
                            }
                        }
                        row {
                            Button { store.signOut(); dismiss() } label: {
                                Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        row {
                            Button { showDeleteWarn = true } label: {
                                Text("Удалить аккаунт")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(hex: 0xE0342B))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    Text("Localee \(appVersion)")
                        .font(.system(size: 13)).foregroundColor(Theme.text3)
                        .frame(maxWidth: .infinity).padding(.top, 4).padding(.bottom, 24)
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.tint(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $support) { SupportSheet() }
        .alert("Удалить аккаунт?", isPresented: $showDeleteWarn) {
            Button("Удалить", role: .destructive) { showDeleteConfirm = true }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Профиль, посты, отметки и достижения будут удалены безвозвратно. Это действие нельзя отменить.")
        }
        .alert("Подтвердите удаление", isPresented: $showDeleteConfirm) {
            TextField("УДАЛИТЬ", text: $deleteText)
                .textInputAutocapitalization(.characters)
            Button("Удалить навсегда", role: .destructive) { deleteAccount() }
                .disabled(deleteText != "УДАЛИТЬ")
            Button("Отмена", role: .cancel) { deleteText = "" }
        } message: {
            Text("Введите слово УДАЛИТЬ, чтобы подтвердить удаление аккаунта.")
        }
        .task {
            // Пока светлая тема недоступна — держим сохранённый выбор в «тёмная»,
            // чтобы галочка стояла корректно.
            if !ThemeChoice.lightReady, themeRaw != ThemeChoice.dark.rawValue {
                themeRaw = ThemeChoice.dark.rawValue
            }
            showOnline = (store.user?.showOnline ?? 1) == 1
            // Год рождения: по умолчанию выключено; без даты рождения — недоступно и off.
            showBirthyear = hasBirthdate && (store.user?.showBirthyear ?? 0) == 1
            ready = true
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: кирпичики

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.text3).kerning(0.6)
                .padding(.horizontal, 16).padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
        }
    }

    private func row<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            content().padding(.horizontal, 14).padding(.vertical, 13)
            Divider().overlay(Theme.border).padding(.leading, 14)
        }
    }

    // Серверный тумблер приватности. enabled=false — недоступен (например, нет даты рождения).
    private func toggle(_ title: String, isOn: Binding<Bool>, enabled: Bool = true,
                        onChange: @escaping (Bool) async -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 16)).foregroundColor(enabled ? Theme.text : Theme.text3)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
                .disabled(saving || !ready || !enabled)
                .onChange(of: isOn.wrappedValue) { _, v in
                    guard ready, enabled else { return }
                    Task { await onChange(v) }
                }
        }
    }

    // Локальный тумблер (уведомления) — хранится на устройстве, без запросов на сервер.
    private func localToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 16)).foregroundColor(Theme.text)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
        }
    }

    // Удаление аккаунта — пока заглушка: настоящий серверный вызов появится позже.
    // Экран и двухступенчатое подтверждение готовы (требование App Store).
    private func deleteAccount() {
        guard deleteText == "УДАЛИТЬ" else { return }
        deleteText = ""
        // TODO: DELETE /api/auth/me на сервере, затем store.signOut().
        dismiss()
    }

    // Тумблер уже переключён визуально; если сервер не принял — откатываем.
    private func savePrivacy(_ fields: [String: Any], rollback: @escaping () -> Void) async {
        saving = true
        error = ""
        do {
            let updated = try await API.shared.updateMe(fields)
            store.user = updated
        } catch {
            rollback()
            self.error = (error as? APIError)?.errorDescription ?? "Не удалось сохранить"
        }
        saving = false
    }
}

// Обращение в поддержку — уходит админам, они видят его на сайте.
struct SupportSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if sent {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 54)).foregroundColor(Theme.accent)
                        Text("Сообщение отправлено")
                            .font(.system(size: 20, weight: .heavy)).foregroundColor(Theme.text)
                        Text("Мы ответим на почту, указанную в профиле.")
                            .font(.system(size: 15)).foregroundColor(Theme.text2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 50)
                } else {
                    Text("Опишите проблему или предложение — мы прочитаем.")
                        .font(.system(size: 15)).foregroundColor(Theme.text2)
                    TextField("", text: $text,
                              prompt: Text("Ваше сообщение").foregroundColor(Theme.text3),
                              axis: .vertical)
                        .foregroundColor(Theme.text).lineLimit(6...12)
                        .padding(12).background(Theme.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if !error.isEmpty {
                        Text(error).font(.system(size: 13)).foregroundColor(Theme.accent)
                    }
                    Button { Task { await send() } } label: {
                        Text(sending ? "Отправляем…" : "Отправить")
                            .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    // Неактивная кнопка — приглушённая целиком, а не тусклой заливкой
                    .opacity(canSend ? 1 : 0.4)
                    .disabled(!canSend)
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Поддержка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(sent ? "Готово" : "Закрыть") { dismiss() }.tint(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var canSend: Bool { !text.trimmed.isEmpty && !sending }

    private func send() async {
        sending = true
        error = ""
        do {
            try await API.shared.sendSupport(text.trimmed)
            sent = true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Не удалось отправить"
        }
        sending = false
    }
}

// Выбор темы. Хранится на устройстве, применяется в корне приложения.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "localee_theme"
    var id: String { rawValue }

    // Светлая тема ещё не доведена: в модальных шитах цвета не переключаются
    // (preferredColorScheme не доходит до презентаций). Пока доступна только
    // тёмная — вернуть true, когда починим проброс темы в шиты.
    static let lightReady = false
    static var selectable: [ThemeChoice] { lightReady ? allCases : [.dark] }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
