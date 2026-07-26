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
    @State private var showMiniProfile = false
    @State private var selecting = false
    @State private var selectedIds: Set<Int> = []
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
                                onReact: { react(m, $0) },
                                onSelectMode: m.fromMe ? { enterSelection(m) } : nil,
                                selecting: selecting,
                                selected: selectedIds.contains(m.id),
                                onToggleSelect: { toggleSelect(m) }
                            ).id(m.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if selecting {
                selectionBar
            } else {
                ChatInputBar(
                    text: $text, photoItem: $photoItem, photoDataURL: $photoDataURL,
                    replyText: replyPreviewText, editing: editingId != nil,
                    onCancelExtra: { replyingTo = nil; editingId = nil; text = "" },
                    onSend: send)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Тап на имя → мини-профиль собеседника (как в Telegram).
                Button { showMiniProfile = true } label: {
                    HStack(spacing: 7) {
                        Text(peer.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                        // Точка статуса: зелёная — в сети, серая — нет.
                        Circle()
                            .fill(peerOnline ? Color(hex: 0x3FAE6E) : Theme.text3)
                            .frame(width: 9, height: 9)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showMiniProfile) { MiniProfileSheet(userId: peer.id) }
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

    // Нижняя панель в режиме множественного выбора: отмена + удалить N.
    private var selectionBar: some View {
        HStack {
            Button("Отмена") { selecting = false; selectedIds = [] }
                .foregroundColor(Theme.accent)
            Spacer()
            Text(selectedIds.isEmpty ? "Выберите сообщения" : "Выбрано: \(selectedIds.count)")
                .font(.system(size: 14)).foregroundColor(Theme.text3)
            Spacer()
            Button { deleteSelected() } label: {
                Label("Удалить", systemImage: "trash").foregroundColor(Theme.accent)
            }
            .disabled(selectedIds.isEmpty).opacity(selectedIds.isEmpty ? 0.4 : 1)
        }
        .font(.system(size: 16, weight: .semibold))
        .padding(.horizontal, 16).padding(.vertical, 12).background(Theme.bg)
    }

    private func enterSelection(_ m: ChatMessage) {
        selecting = true
        selectedIds = [m.id]
    }
    private func toggleSelect(_ m: ChatMessage) {
        if selectedIds.contains(m.id) { selectedIds.remove(m.id) } else { selectedIds.insert(m.id) }
    }
    private func deleteSelected() {
        let ids = selectedIds
        messages.removeAll { ids.contains($0.id) }
        selecting = false; selectedIds = []
        Haptics.tap(.medium)
        Task { for id in ids { try? await API.shared.deleteMessage(id) } }
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
    var onTapSender: (() -> Void)? = nil     // тап на имя отправителя (в группе)
    var onReply: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onReact: ((String) -> Void)? = nil
    var onSelectMode: (() -> Void)? = nil    // «Выбрать» из меню → включить мультивыбор
    // Режим множественного выбора (для удаления нескольких сообщений сразу).
    var selecting = false
    var selected = false
    var onToggleSelect: (() -> Void)? = nil

    @State private var zoomPhoto = false
    @State private var menuShown = false
    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        // В режиме выбора весь ряд — одна кнопка-переключатель, жесты пузыря выключены.
        if selecting {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundColor(selected ? Theme.accent : Theme.text3)
                content.allowsHitTesting(false)   // внутренние жесты выключены в режиме выбора
            }
            .padding(.vertical, 2).contentShape(Rectangle())
            .onTapGesture { onToggleSelect?() }
            .background(selected ? Theme.accent.opacity(0.08) : .clear)
        } else {
            content
        }
    }

    private var content: some View {
        HStack {
            if mine { Spacer(minLength: 44) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                bubble
                if !reactions.isEmpty { reactionChips }
            }
            if !mine { Spacer(minLength: 44) }
        }
        // Свайп вбок → ответить (как в Telegram). Иконка проявляется по мере тяги.
        .overlay(alignment: mine ? .trailing : .leading) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 15)).foregroundColor(Theme.accent)
                .opacity(Double(min(abs(swipeOffset) / 55, 1)))
                .padding(mine ? .trailing : .leading, 8)
        }
        .offset(x: swipeOffset)
        .gesture(
            DragGesture(minimumDistance: 18)
                .onChanged { v in
                    // Только преимущественно горизонтальный жест — чтобы не мешать
                    // вертикальному скроллу ленты сообщений.
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    let dx = v.translation.width
                    // Свайп к центру: свои тянем влево, чужие вправо.
                    swipeOffset = mine ? min(0, max(-70, dx)) : max(0, min(70, dx))
                }
                .onEnded { _ in
                    if abs(swipeOffset) > 48 { onReply?(); Haptics.tap() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { swipeOffset = 0 }
                }
        )
        .fullScreenCover(isPresented: $zoomPhoto) {
            ImageLightbox(src: image) { zoomPhoto = false }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let s = senderName, !mine {
                Button { onTapSender?() } label: {
                    Text(s).font(.system(size: 12, weight: .bold)).foregroundColor(Color(hexString: senderColor))
                }
                .buttonStyle(.plain).disabled(onTapSender == nil)
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
            // Текст и время в одной строке (Telegram-стиль): время с галочками
            // прижато к правому нижнему углу пузыря, на уровне последней строки.
            if !text.isEmpty {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(text).font(.system(size: 15.5)).foregroundColor(mine ? .white : Theme.text)
                    timeRow
                }
            } else {
                // Только фото/пересланное — время отдельной строкой справа.
                timeRow.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        // Пузырь по содержимому, но не шире экрана; выше HStack со Spacer
        // прижимает его к своей стороне (свои — справа, чужие — слева).
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(mine ? Theme.accent : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        // Двойной тап — быстрая реакция сердцем (как лайк в Instagram).
        .onTapGesture(count: 2) { onReact?("❤️") }
        // Долгое нажатие — меню с лентой реакций и действиями.
        .onLongPressGesture(minimumDuration: 0.3) {
            Haptics.tap(.medium)
            menuShown = true
        }
        .popover(isPresented: $menuShown) {
            reactionMenu.presentationCompactAdaptation(.popover)
        }
    }

    // Время + галочки прочтения (у своих). ✓ — отправлено, ✓✓ — прочитано.
    private var timeRow: some View {
        HStack(spacing: 3) {
            Text(time + (edited ? " · изм." : ""))
                .font(.system(size: 11)).foregroundColor(mine ? .white.opacity(0.7) : Theme.text3)
            if mine { readTicks }
        }
        .fixedSize()
    }

    // Кастомное меню (поповер): горизонтальная лента реакций + действия.
    private var reactionMenu: some View {
        VStack(spacing: 0) {
            if onReact != nil {
                HStack(spacing: 6) {
                    ForEach(REACTION_EMOJIS, id: \.self) { e in
                        Button { onReact?(e); menuShown = false } label: {
                            Text(e).font(.system(size: 28))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                Divider()
            }
            VStack(spacing: 0) {
                if let onReply {
                    menuButton("Ответить", "arrowshape.turn.up.left") { onReply(); menuShown = false }
                }
                if !text.isEmpty {
                    menuButton("Копировать", "doc.on.doc") { UIPasteboard.general.string = text; menuShown = false }
                }
                if let onEdit {
                    menuButton("Изменить", "pencil") { onEdit(); menuShown = false }
                }
                if let onSelectMode {
                    menuButton("Выбрать", "checkmark.circle") { onSelectMode(); menuShown = false }
                }
                if let onDelete {
                    menuButton("Удалить", "trash", destructive: true) { onDelete(); menuShown = false }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func menuButton(_ title: String, _ icon: String, destructive: Bool = false,
                            _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15)).frame(width: 22)
                Text(title).font(.system(size: 16))
                Spacer()
            }
            .foregroundColor(destructive ? Theme.accent : Theme.text)
            .padding(.horizontal, 16).padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
