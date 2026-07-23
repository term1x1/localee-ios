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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !error.isEmpty {
                        Text(error).font(.system(size: 13)).foregroundColor(Theme.accent)
                            .padding(.horizontal, 16)
                    }

                    section("ОФОРМЛЕНИЕ") {
                        ForEach(ThemeChoice.allCases) { choice in
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

                    section("ПРИВАТНОСТЬ") {
                        row {
                            toggle("Показывать, что я в сети", isOn: $showOnline) { v in
                                await savePrivacy(["show_online": v ? 1 : 0]) { showOnline = !v }
                            }
                        }
                        row {
                            toggle("Показывать год рождения", isOn: $showBirthyear) { v in
                                await savePrivacy(["show_birthyear": v ? 1 : 0]) { showBirthyear = !v }
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
        .task {
            showOnline = (store.user?.showOnline ?? 1) == 1
            showBirthyear = (store.user?.showBirthyear ?? 1) == 1
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

    private func toggle(_ title: String, isOn: Binding<Bool>,
                        onChange: @escaping (Bool) async -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 16)).foregroundColor(Theme.text)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
                .disabled(saving || !ready)
                .onChange(of: isOn.wrappedValue) { _, v in
                    guard ready else { return }
                    Task { await onChange(v) }
                }
        }
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
                            .background(canSend ? Theme.accent : Theme.accent.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
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
