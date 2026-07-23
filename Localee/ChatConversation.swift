import SwiftUI

struct ConversationView: View {
    let peer: ChatUser
    @State private var messages: [ChatMessage] = []
    @State private var text = ""
    @State private var replyingTo: ChatMessage?
    @State private var editingId: Int?
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
        .navigationTitle(peer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .task {
            await load()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { await load() } }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var replyPreviewText: String? {
        guard let r = replyingTo else { return nil }
        return (r.fromMe ? "Вы: " : "\(peer.name): ") + r.text
    }

    private func load() async {
        if let r = try? await API.shared.messages(with: peer.id) { messages = r.messages }
    }
    private func startEdit(_ m: ChatMessage) {
        editingId = m.id; replyingTo = nil; text = m.text
    }
    private func remove(_ m: ChatMessage) {
        messages.removeAll { $0.id == m.id }
        Task { try? await API.shared.deleteMessage(m.id) }
    }
    private func send() {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        if let eid = editingId {
            text = ""; editingId = nil
            if let i = messages.firstIndex(where: { $0.id == eid }) {
                messages[i].text = t; messages[i].edited = true
            }
            Task { _ = try? await API.shared.editMessage(eid, text: t) }
            return
        }
        let reply = replyingTo?.id
        text = ""; replyingTo = nil
        Task {
            if let m = try? await API.shared.send(to: peer.id, text: t, replyTo: reply) { messages.append(m) }
        }
    }
}

// Пузырь сообщения с действиями по долгому нажатию.
struct MessageBubble: View {
    let text: String
    let mine: Bool
    let time: String
    var edited = false
    var reply: ReplyPreview? = nil
    var forwarded = ""
    var senderName: String? = nil
    var senderColor: String = "#888888"
    var onReply: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 3) {
                if let s = senderName, !mine {
                    Text(s).font(.system(size: 12, weight: .bold)).foregroundColor(Color(hexString: senderColor))
                }
                if !forwarded.isEmpty {
                    Text("↪ Переслано от \(forwarded)").font(.system(size: 11)).foregroundColor(Theme.text3)
                }
                if let r = reply {
                    HStack(spacing: 6) {
                        Rectangle().fill(mine ? Color.white.opacity(0.6) : Theme.accent).frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            if let a = r.author { Text(a).font(.system(size: 11, weight: .bold)) }
                            Text(r.text).font(.system(size: 12)).lineLimit(1)
                        }
                        .foregroundColor(mine ? .white.opacity(0.85) : Theme.text2)
                    }
                    .padding(.leading, 2)
                }
                Text(text).font(.system(size: 15.5)).foregroundColor(mine ? .white : Theme.text)
                Text(time + (edited ? " · изменено" : ""))
                    .font(.system(size: 11)).foregroundColor(mine ? .white.opacity(0.7) : Theme.text3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(mine ? Theme.accent : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contextMenu {
                Button { UIPasteboard.general.string = text } label: { Label("Копировать", systemImage: "doc.on.doc") }
                if let onReply { Button { onReply() } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") } }
                if let onEdit { Button { onEdit() } label: { Label("Изменить", systemImage: "pencil") } }
                if let onDelete { Button(role: .destructive) { onDelete() } label: { Label("Удалить", systemImage: "trash") } }
            }
            if !mine { Spacer(minLength: 44) }
        }
    }
}

// Поле ввода с плашкой ответа/редактирования.
struct ChatInputBar: View {
    @Binding var text: String
    var replyText: String?
    var editing: Bool
    var onCancelExtra: () -> Void
    var onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if replyText != nil || editing {
                HStack(spacing: 8) {
                    Image(systemName: editing ? "pencil" : "arrowshape.turn.up.left")
                        .foregroundColor(Theme.accent).font(.system(size: 13))
                    Text(editing ? "Редактирование" : (replyText ?? ""))
                        .font(.system(size: 13)).foregroundColor(Theme.text2).lineLimit(1)
                    Spacer()
                    Button { onCancelExtra() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.text3) }
                }
                .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.bg2)
            }
            HStack(spacing: 8) {
                TextField("", text: $text, prompt: Text("Сообщение…").foregroundColor(Theme.text3), axis: .vertical)
                    .foregroundColor(Theme.text).lineLimit(1...5)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 20))
                Button(action: onSend) {
                    Image(systemName: editing ? "checkmark" : "arrow.up")
                        .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .frame(width: 42, height: 42).background(Theme.accent).clipShape(Circle())
                }
                .opacity(text.trimmed.isEmpty ? 0.4 : 1)
            .disabled(text.trimmed.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Theme.bg)
    }
}
