import SwiftUI
import PhotosUI

// Доступные реакции — те же, что принимает сервер (reactions.js).
let REACTION_EMOJIS = ["❤️", "👍", "😂", "🔥", "😮", "😢"]

struct ConversationView: View {
    let peer: ChatUser
    @State private var messages: [ChatMessage] = []
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoDataURL = ""          // выбранное фото (data URL)
    @State private var replyingTo: ChatMessage?
    @State private var editingId: Int?
    @State private var peerOnline = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { m in
                            MessageBubble(
                                text: m.text, image: m.image, mine: m.fromMe, time: clockTime(m.createdAt),
                                edited: m.edited, read: m.read, reply: m.replyTo, forwarded: m.forwardedFrom,
                                reactions: m.reactions,
                                onReply: { replyingTo = m; editingId = nil },
                                onEdit: (m.fromMe && !m.text.isEmpty) ? { startEdit(m) } : nil,
                                onDelete: m.fromMe ? { remove(m) } : nil,
                                onReact: { react(m, $0) }
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
                text: $text, photoItem: $photoItem, photoDataURL: $photoDataURL,
                replyText: replyPreviewText, editing: editingId != nil,
                onCancelExtra: { replyingTo = nil; editingId = nil; text = "" },
                onSend: send)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(peer.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                    Text(peerOnline ? "в сети" : "не в сети")
                        .font(.system(size: 12))
                        .foregroundColor(peerOnline ? Color(hex: 0x3FAE6E) : Theme.text3)
                }
            }
        }
        .task {
            await load()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { await load() } }
        }
        .onDisappear { timer?.invalidate() }
        .onChange(of: photoItem) { _, item in Task { await pickPhoto(item) } }
    }

    private var replyPreviewText: String? {
        guard let r = replyingTo else { return nil }
        return (r.fromMe ? "Вы: " : "\(peer.name): ") + r.text
    }

    private func load() async {
        if let r = try? await API.shared.messages(with: peer.id) {
            messages = r.messages
            peerOnline = r.user.online ?? false
        }
    }
    private func pickPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data), let url = imageToDataURL(img, maxDimension: 1400) else { return }
        photoDataURL = url
    }
    private func startEdit(_ m: ChatMessage) {
        editingId = m.id; replyingTo = nil; text = m.text
    }
    private func remove(_ m: ChatMessage) {
        messages.removeAll { $0.id == m.id }
        Task { try? await API.shared.deleteMessage(m.id) }
    }
    private func react(_ m: ChatMessage, _ emoji: String) {
        Haptics.tap()
        Task {
            if let updated = try? await API.shared.react(messageId: m.id, emoji: emoji),
               let i = messages.firstIndex(where: { $0.id == m.id }) {
                messages[i].reactions = updated
            }
        }
    }
    private func send() {
        let t = text.trimmed
        let photo = photoDataURL
        // Редактируем только текст (фото при редактировании не трогаем).
        if let eid = editingId {
            guard !t.isEmpty else { return }
            text = ""; editingId = nil
            if let i = messages.firstIndex(where: { $0.id == eid }) {
                messages[i].text = t; messages[i].edited = true
            }
            Task { _ = try? await API.shared.editMessage(eid, text: t) }
            return
        }
        guard !t.isEmpty || !photo.isEmpty else { return }
        let reply = replyingTo?.id
        text = ""; replyingTo = nil; photoDataURL = ""; photoItem = nil
        Haptics.tap()
        Task {
            if let m = try? await API.shared.send(to: peer.id, text: t, image: photo, replyTo: reply) {
                messages.append(m)
            }
        }
    }
}

// Пузырь сообщения с действиями по долгому нажатию.
struct MessageBubble: View {
    let text: String
    var image = ""
    let mine: Bool
    let time: String
    var edited = false
    var read = false
    var reply: ReplyPreview? = nil
    var forwarded = ""
    var reactions: [Reaction] = []
    var senderName: String? = nil
    var senderColor: String = "#888888"
    var onReply: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onReact: ((String) -> Void)? = nil

    @State private var zoomPhoto = false

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 44) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                bubble
                if !reactions.isEmpty { reactionChips }
            }
            if !mine { Spacer(minLength: 44) }
        }
        .fullScreenCover(isPresented: $zoomPhoto) {
            ImageLightbox(src: image) { zoomPhoto = false }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let s = senderName, !mine {
                Text(s).font(.system(size: 12, weight: .bold)).foregroundColor(Color(hexString: senderColor))
            }
            if !forwarded.isEmpty {
                Label("Переслано от \(forwarded)", systemImage: "arrowshape.turn.up.right")
                    .font(.system(size: 11)).foregroundColor(Theme.text3)
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
            if !image.isEmpty {
                Button { zoomPhoto = true } label: {
                    NetImage(src: image) { Theme.bg2 }.scaledToFill()
                        .frame(maxWidth: 240).frame(height: 200).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            if !text.isEmpty {
                Text(text).font(.system(size: 15.5)).foregroundColor(mine ? .white : Theme.text)
            }
            // Время + галочки прочтения (у своих). ✓ — отправлено, ✓✓ — прочитано.
            HStack(spacing: 4) {
                Text(time + (edited ? " · изменено" : ""))
                    .font(.system(size: 11)).foregroundColor(mine ? .white.opacity(0.7) : Theme.text3)
                if mine { readTicks }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(mine ? Theme.accent : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contextMenu {
            // Ряд реакций сверху — как в Telegram (эмодзи в одну линию).
            if onReact != nil {
                ControlGroup {
                    ForEach(REACTION_EMOJIS, id: \.self) { e in
                        Button { onReact?(e) } label: { Text(e) }
                    }
                }
            }
            if !text.isEmpty {
                Button { UIPasteboard.general.string = text } label: { Label("Копировать", systemImage: "doc.on.doc") }
            }
            if let onReply { Button { onReply() } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") } }
            if let onEdit { Button { onEdit() } label: { Label("Изменить", systemImage: "pencil") } }
            if let onDelete { Button(role: .destructive) { onDelete() } label: { Label("Удалить", systemImage: "trash") } }
        }
    }

    // Чипы реакций под пузырём. Тап по своей — снимает, по чужой — присоединяет.
    private var reactionChips: some View {
        HStack(spacing: 4) {
            ForEach(reactions) { r in
                Button { onReact?(r.emoji) } label: {
                    HStack(spacing: 3) {
                        Text(r.emoji).font(.system(size: 12))
                        if r.count > 1 {
                            Text("\(r.count)").font(.system(size: 11, weight: .semibold))
                                .foregroundColor(r.mine ? Theme.accent : Theme.text2)
                        }
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(r.mine ? Theme.accent.opacity(0.18) : Theme.bg2)
                    .overlay(Capsule().stroke(r.mine ? Theme.accent : .clear, lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Две галочки вплотную = прочитано, одна = доставлено (стиль Telegram/WhatsApp).
    private var readTicks: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
            if read { Image(systemName: "checkmark").offset(x: 4) }
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundColor(.white.opacity(read ? 1 : 0.7))
    }
}

// Поле ввода с плашкой ответа/редактирования и выбором фото.
struct ChatInputBar: View {
    @Binding var text: String
    @Binding var photoItem: PhotosPickerItem?
    @Binding var photoDataURL: String
    var replyText: String?
    var editing: Bool
    var onCancelExtra: () -> Void
    var onSend: () -> Void

    private var canSend: Bool { !text.trimmed.isEmpty || !photoDataURL.isEmpty }

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
            // Превью выбранного фото над полем ввода.
            if !photoDataURL.isEmpty {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        NetImage(src: photoDataURL) { Theme.bg2 }.scaledToFill()
                            .frame(width: 80, height: 80).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button { photoDataURL = ""; photoItem = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                .padding(5).background(.black.opacity(0.55)).clipShape(Circle())
                        }
                        .padding(4)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
            HStack(spacing: 8) {
                // Фото при редактировании не прикрепляем.
                if !editing {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo").font(.system(size: 20)).foregroundColor(Theme.accent)
                            .frame(width: 34, height: 42)
                    }
                }
                TextField("", text: $text, prompt: Text("Сообщение…").foregroundColor(Theme.text3), axis: .vertical)
                    .foregroundColor(Theme.text).lineLimit(1...5)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 20))
                Button(action: onSend) {
                    Image(systemName: editing ? "checkmark" : "arrow.up")
                        .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .frame(width: 42, height: 42).background(Theme.accent).clipShape(Circle())
                }
                .opacity(canSend ? 1 : 0.4)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Theme.bg)
    }
}
