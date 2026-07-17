import SwiftUI

struct GroupChatView: View {
    let groupId: Int
    let initialName: String
    @EnvironmentObject var store: AppStore
    @State private var messages: [GroupMessage] = []
    @State private var group: GroupInfo?
    @State private var text = ""
    @State private var replyingTo: GroupMessage?
    @State private var editingId: Int?
    @State private var showSettings = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { m in
                            MessageBubble(
                                text: m.text, mine: m.fromMe, time: clockTime(m.createdAt),
                                edited: m.edited, reply: m.replyTo, forwarded: m.forwardedFrom,
                                senderName: m.sender?.name, senderColor: m.sender?.color ?? "#888888",
                                onReply: { replyingTo = m; editingId = nil },
                                onEdit: m.fromMe ? { startEdit(m) } : nil,
                                onDelete: m.fromMe ? { remove(m) } : nil
                            ).id(m.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            ChatInputBar(
                text: $text, replyText: replyPreviewText, editing: editingId != nil,
                onCancelExtra: { replyingTo = nil; editingId = nil; text = "" },
                onSend: send)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(group?.name ?? initialName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Image(systemName: "ellipsis").foregroundColor(Theme.accent) }
            }
        }
        .sheet(isPresented: $showSettings) {
            if let g = group { GroupSettingsSheet(group: g, myId: store.user?.id ?? 0) }
        }
        .task {
            await load()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { await load() } }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var replyPreviewText: String? {
        guard let r = replyingTo else { return nil }
        return (r.sender?.name ?? "") + ": " + r.text
    }
    private func load() async {
        if let r = try? await API.shared.groupMessages(groupId) { messages = r.messages; group = r.group }
    }
    private func startEdit(_ m: GroupMessage) { editingId = m.id; replyingTo = nil; text = m.text }
    private func remove(_ m: GroupMessage) {
        messages.removeAll { $0.id == m.id }
        Task { try? await API.shared.groupDeleteMessage(m.id) }
    }
    private func send() {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        if let eid = editingId {
            text = ""; editingId = nil
            if let i = messages.firstIndex(where: { $0.id == eid }) { messages[i].text = t; messages[i].edited = true }
            Task { _ = try? await API.shared.groupEditMessage(eid, text: t) }
            return
        }
        let reply = replyingTo?.id
        text = ""; replyingTo = nil
        Task { if let m = try? await API.shared.groupSend(groupId, text: t, replyTo: reply) { messages.append(m) } }
    }
}

struct GroupSettingsSheet: View {
    let group: GroupInfo
    let myId: Int
    @Environment(\.dismiss) var dismiss
    @State private var members: [ChatUser] = []
    @State private var name = ""
    @State private var showAdd = false

    private var isOwner: Bool { group.ownerId == myId }
    private var inviteURL: String { "https://localee.ru/g/\(group.inviteToken)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AvatarView(avatar: "", color: group.color, letter: group.letter, size: 80).padding(.top, 12)
                    if isOwner {
                        TextField("", text: $name, prompt: Text("Название группы").foregroundColor(Theme.text3))
                            .multilineTextAlignment(.center).foregroundColor(Theme.text)
                            .font(.system(size: 20, weight: .bold))
                            .onSubmit { Task { _ = try? await API.shared.groupRename(group.id, name: name.trimmed) } }
                    } else {
                        Text(group.name).font(.system(size: 22, weight: .heavy)).foregroundColor(Theme.text)
                    }
                    Text("\(members.count) участников").font(.system(size: 14)).foregroundColor(Theme.text3)

                    // Пригласительная ссылка
                    Button { UIPasteboard.general.string = inviteURL } label: {
                        Label("Скопировать ссылку-приглашение", systemImage: "link")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.padding(.horizontal, 16)

                    if isOwner {
                        Button { showAdd = true } label: {
                            Label("Добавить участника", systemImage: "person.badge.plus")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                                .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }.padding(.horizontal, 16)
                    }

                    // Участники
                    VStack(spacing: 0) {
                        ForEach(members) { m in
                            HStack(spacing: 12) {
                                AvatarView(avatar: m.avatar, color: m.color, letter: m.letter, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name + (m.id == group.ownerId ? " · владелец" : ""))
                                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                                    Text("@\(m.handle)").font(.system(size: 12)).foregroundColor(Theme.text3)
                                }
                                Spacer()
                                if isOwner && m.id != myId {
                                    Button { removeMember(m) } label: {
                                        Image(systemName: "minus.circle").foregroundColor(Theme.accent)
                                    }
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            Divider().overlay(Theme.border).padding(.leading, 70)
                        }
                    }
                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)

                    // Опасные действия
                    Button(role: .destructive) { leave() } label: {
                        Text(isOwner ? "Удалить группу" : "Покинуть группу")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 13).background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Настройки группы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.tint(Theme.accent) } }
        }
        .sheet(isPresented: $showAdd) {
            UserPickerSheet(title: "Добавить") { u in
                Task { try? await API.shared.groupAddMember(group.id, userId: u.id); await loadMembers() }
            }
        }
        .task { name = group.name; await loadMembers() }
    }

    private func loadMembers() async {
        if let r = try? await API.shared.groupInfo(group.id) { members = r.members }
    }
    private func removeMember(_ m: ChatUser) {
        members.removeAll { $0.id == m.id }
        Task { try? await API.shared.groupRemoveMember(group.id, userId: m.id) }
    }
    private func leave() {
        Task {
            if isOwner { try? await API.shared.groupDelete(group.id) }
            else { try? await API.shared.groupLeave(group.id) }
            dismiss()
        }
    }
}
