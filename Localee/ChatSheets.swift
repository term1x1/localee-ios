import SwiftUI

// Поиск пользователя и открытие личного чата.
struct NewChatSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var results: [ChatUser] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchField(query: $query, placeholder: "Имя или @ник") { await search() }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { u in
                            NavigationLink { ConversationView(peer: u) } label: { UserRow(user: u) }
                            Divider().overlay(Theme.border).padding(.leading, 70)
                        }
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Новый чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() }.tint(Theme.text2) } }
        }
    }
    private func search() async {
        let q = query.trimmed
        guard q.count >= 1 else { results = []; return }
        results = (try? await API.shared.searchUsers(q)) ?? []
    }
}

// Создание группы: название + выбор участников.
struct CreateGroupSheet: View {
    var onCreated: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var query = ""
    @State private var results: [ChatUser] = []
    @State private var picked: [ChatUser] = []
    @State private var creating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("", text: $name, prompt: Text("Название группы").foregroundColor(Theme.text3))
                    .foregroundColor(Theme.text).font(.system(size: 17, weight: .semibold))
                    .padding(14).background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16).padding(.top, 12)

                if !picked.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(picked) { u in
                                HStack(spacing: 6) {
                                    Text(u.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                                    Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(Theme.text3)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.card).clipShape(Capsule())
                                .onTapGesture { picked.removeAll { $0.id == u.id } }
                            }
                        }.padding(.horizontal, 16)
                    }.padding(.vertical, 10)
                }

                SearchField(query: $query, placeholder: "Добавить участников") { await search() }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { u in
                            Button { toggle(u) } label: {
                                HStack {
                                    UserRow(user: u)
                                    if picked.contains(where: { $0.id == u.id }) {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent).padding(.trailing, 16)
                                    }
                                }
                            }
                            Divider().overlay(Theme.border).padding(.leading, 70)
                        }
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Новая группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.tint(Theme.text2) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { create() }.tint(Theme.accent).fontWeight(.semibold)
                        .disabled(name.trimmed.isEmpty || creating)
                }
            }
        }
    }
    private func toggle(_ u: ChatUser) {
        if let i = picked.firstIndex(where: { $0.id == u.id }) { picked.remove(at: i) } else { picked.append(u) }
    }
    private func search() async {
        let q = query.trimmed
        guard q.count >= 1 else { results = []; return }
        results = (try? await API.shared.searchUsers(q)) ?? []
    }
    private func create() {
        creating = true
        Task {
            _ = try? await API.shared.createGroup(name: name.trimmed, memberIds: picked.map { $0.id })
            creating = false; onCreated(); dismiss()
        }
    }
}

// Выбор одного пользователя (добавление в группу).
struct UserPickerSheet: View {
    let title: String
    var onPick: (ChatUser) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var results: [ChatUser] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchField(query: $query, placeholder: "Имя или @ник") { await search() }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { u in
                            Button { onPick(u); dismiss() } label: { UserRow(user: u) }
                            Divider().overlay(Theme.border).padding(.leading, 70)
                        }
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() }.tint(Theme.text2) } }
        }
    }
    private func search() async {
        let q = query.trimmed
        guard q.count >= 1 else { results = []; return }
        results = (try? await API.shared.searchUsers(q)) ?? []
    }
}

struct SearchField: View {
    @Binding var query: String
    var placeholder: String
    var onChange: () async -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Theme.text3)
            TextField("", text: $query, prompt: Text(placeholder).foregroundColor(Theme.text3))
                .foregroundColor(Theme.text).autocorrectionDisabled()
                .onChange(of: query) { _, _ in Task { await onChange() } }
        }
        .padding(.horizontal, 14).padding(.vertical, 11).background(Theme.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct UserRow: View {
    let user: ChatUser
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(avatar: user.avatar, color: user.color, letter: user.letter, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                Text("@\(user.handle)").font(.system(size: 13)).foregroundColor(Theme.text3)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle())
    }
}
