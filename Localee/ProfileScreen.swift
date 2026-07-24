import SwiftUI
import PhotosUI
import CoreImage.CIFilterBuiltins

// Смещение контента при скролле — чтобы плавно сворачивать шапку в навбар.
private struct ProfileScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ProfileScreen: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gam: Gamification
    @EnvironmentObject var postStore: PostStore
    @State private var photos: [PhotoItem] = []
    @State private var friends: [ChatUser] = []
    @State private var editing = false
    @State private var editFocusBio = false
    @State private var showFriends = false
    @State private var showAchievements = false
    @State private var showSettings = false
    @State private var sharing = false
    @State private var showEarlyInfo = false
    @State private var avatarZoom = false
    @State private var photoZoom: String?
    @State private var commentsFor: Post?
    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?
    @State private var uploading = false
    // Композер стены
    @State private var wallText = ""
    @State private var wallPhoto: PhotosPickerItem?
    @State private var wallPhotoURL = ""
    @State private var posting = false
    // Коллапс шапки при скролле
    @State private var scrollY: CGFloat = 0
    private let collapseDistance: CGFloat = 120

    // 0 — шапка раскрыта, 1 — свёрнута (имя и аватар «въехали» в навбар).
    private var collapse: CGFloat { min(max(-scrollY / collapseDistance, 0), 1) }
    // Первые пользователи Localee — по порядковому номеру регистрации (id).
    private func isEarlyAdopter(_ u: ApiUser) -> Bool { u.id > 0 && u.id <= 500 }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if let u = store.user {
                        VStack(spacing: 0) {
                            GeometryReader { g in
                                Color.clear.preference(key: ProfileScrollKey.self,
                                                       value: g.frame(in: .named("profileScroll")).minY)
                            }.frame(height: 0)

                            header(u)
                            statsRow(u, proxy)
                            editButton
                            aboutSection(u)
                            if !photos.isEmpty { photosSection }
                            wallSection(u).id("posts")
                            // Запас снизу: контент не должен уезжать под плавающий таб-бар
                            Color.clear.frame(height: 96)
                        }
                    }
                }
                .coordinateSpace(name: "profileScroll")
                .onPreferenceChange(ProfileScrollKey.self) { scrollY = $0 }
            }
            .frame(maxWidth: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let u = store.user {
                        HStack(spacing: 8) {
                            AvatarView(avatar: u.avatar, color: u.color, letter: u.letter, handle: u.handle, name: u.name, size: 28)
                            Text(u.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                        }
                        .opacity(collapse)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        Button { sharing = true } label: {
                            Image(systemName: "square.and.arrow.up").foregroundColor(Theme.text)
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape").foregroundColor(Theme.text)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $editing) { EditProfileSheet(focusBio: editFocusBio) }
        .sheet(isPresented: $showFriends) { FriendsSheet(friends: friends) }
        .sheet(isPresented: $showAchievements) { AchievementsSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $sharing) { if let u = store.user { ShareProfileSheet(user: u) } }
        .sheet(item: $commentsFor) { post in
            CommentsSheet(post: post) { newCount in postStore.setCommentCount(post.id, newCount) }
        }
        .alert("Один из первых", isPresented: $showEarlyInfo) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Вы зарегистрировались одним из первых пользователей Localee. Спасибо, что с нами с самого начала!")
        }
        .fullScreenCover(isPresented: $avatarZoom) {
            if let u = store.user { ImageLightbox(src: u.avatar, fallbackColor: u.color, letter: u.letter) { avatarZoom = false } }
        }
        .fullScreenCover(item: Binding(get: { photoZoom.map { Zoomed(src: $0) } }, set: { photoZoom = $0?.src })) { z in
            ImageLightbox(src: z.src) { photoZoom = nil }
        }
        .onChange(of: avatarItem) { _, i in Task { await upload(i, isCover: false) } }
        .onChange(of: coverItem) { _, i in Task { await upload(i, isCover: true) } }
        .onChange(of: wallPhoto) { _, i in Task { await pickWallPhoto(i) } }
    }

    // MARK: Шапка
    private func header(_ u: ApiUser) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if !u.cover.isEmpty { NetImage(src: u.cover) { coverGradient }.scaledToFill() }
                    else { coverGradient }
                }
                .frame(height: 150).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20))
                PhotosPicker(selection: $coverItem, matching: .images) {
                    Image(systemName: "camera.fill").font(.system(size: 14)).foregroundColor(.white)
                        .padding(9).background(.black.opacity(0.45)).clipShape(Circle())
                }.padding(12)
            }
            .padding(.horizontal, 16)
            // Обложка растворяется по мере сворачивания шапки
            .opacity(1 - collapse)

            ZStack(alignment: .bottomTrailing) {
                Button { if !u.avatar.isEmpty { avatarZoom = true } } label: {
                    AvatarView(avatar: u.avatar, color: u.color, letter: u.letter, handle: u.handle, name: u.name, size: 92)
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 4))
                }
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Image(systemName: "camera.fill").font(.system(size: 12)).foregroundColor(.white)
                        .padding(7).background(Theme.accent).clipShape(Circle())
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                }
            }
            .offset(y: -46).padding(.bottom, -46)
            // Аватар уменьшается и тает — его роль перехватывает копия в навбаре
            .scaleEffect(1 - 0.4 * collapse, anchor: .center)
            .opacity(1 - collapse)

            if uploading { ProgressView().tint(Theme.accent).padding(.top, 12) }

            Text(u.name).font(.system(size: 24, weight: .heavy)).foregroundColor(Theme.text).padding(.top, 10)
                .opacity(1 - collapse)
            HStack(spacing: 8) {
                Text("@\(u.handle)").font(.system(size: 15)).foregroundColor(Theme.text2)
                if isEarlyAdopter(u) {
                    Button { showEarlyInfo = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.system(size: 10))
                            Text("Один из первых").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.15)).clipShape(Capsule())
                    }
                }
            }
            .opacity(1 - collapse)
            if u.role == "admin" {
                Text("Администратор").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.15)).clipShape(Capsule()).padding(.top, 6)
                    .opacity(1 - collapse)
            }
        }
    }

    private var coverGradient: some View {
        LinearGradient(colors: [Theme.accent, Theme.nightlife], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Статистика
    private func statsRow(_ u: ApiUser, _ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            Button { withAnimation { proxy.scrollTo("posts", anchor: .top) } } label: {
                stat("\(postStore.countByAuthor(u.id))", "Посты")
            }
            Button { showAchievements = true } label: { stat("\(gam.unlockedCount)", "Достижения") }
            Button { showFriends = true } label: { stat("\(friends.count)", "Друзья") }
        }
        .padding(.horizontal, 16).padding(.top, 16)
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.text)
            Text(label).font(.system(size: 12)).foregroundColor(Theme.text3)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var editButton: some View {
        Button { editFocusBio = false; editing = true } label: {
            Label("Редактировать профиль", systemImage: "pencil")
                .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }.padding(.horizontal, 16).padding(.top, 12)
    }

    // MARK: О себе
    private func aboutSection(_ u: ApiUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("О себе")
            VStack(alignment: .leading, spacing: 12) {
                if u.bio.isEmpty {
                    // На своём профиле — приглашение заполнить, ведёт сразу в поле «О себе»
                    Button { editFocusBio = true; editing = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 16))
                            Text("Рассказать о себе").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(u.bio)
                        .font(.system(size: 15)).foregroundColor(Theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading).lineSpacing(3)
                }
                let rows = infoRows(u)
                if !rows.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(rows, id: \.label) { r in
                            HStack(spacing: 10) {
                                Image(systemName: r.icon).font(.system(size: 14))
                                    .foregroundColor(Theme.accent).frame(width: 22)
                                Text(r.label).font(.system(size: 14)).foregroundColor(Theme.text3)
                                Spacer()
                                Text(r.value).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                            }
                        }
                    }
                }
                if !u.interestList.isEmpty { FlowChips(items: u.interestList) }
            }
            .padding(16).background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16).padding(.top, 18)
    }

    private func infoRows(_ u: ApiUser) -> [(icon: String, label: String, value: String)] {
        var r: [(String, String, String)] = []
        if let b = formatBirthday(u.birthdate) { r.append(("gift.fill", "День рождения", b)) }
        if let g = genderLabel(u.gender) { r.append(("person.fill", "Пол", g)) }
        if !u.city.isEmpty { r.append(("mappin.circle.fill", "Город", u.city)) }
        if let s = joinedText(u.createdAt) { r.append(("calendar", "С нами", s)) }
        return r.map { (icon: $0.0, label: $0.1, value: $0.2) }
    }

    // MARK: Фото
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { sectionLabel("Фотографии"); Spacer()
                Text("\(photos.count)").foregroundColor(Theme.text3).font(.system(size: 14, weight: .bold)) }
            let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(photos.prefix(9)) { ph in
                    Button { photoZoom = ph.image } label: {
                        NetImage(src: ph.image) { Theme.bg2 }.scaledToFill()
                            .frame(height: 108).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 20)
    }

    // MARK: Стена
    private func wallSection(_ u: ApiUser) -> some View {
        // Посты берём из общего хранилища, отфильтрованные по автору.
        // Тот же массив, что видит Лента, — пост появляется сразу в обоих местах.
        let mine = postStore.byAuthor(u.id)
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Мои записи")
            wallComposer(u)
            if !postStore.loaded {
                ProgressView().tint(Theme.accent).padding(.top, 16)
            } else if mine.isEmpty {
                Text("Постов пока нет").foregroundColor(Theme.text3)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ForEach(mine) { post in
                    PostCard(post: post, onLike: { like(post) }, onComment: { commentsFor = post })
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 20)
    }

    private func wallComposer(_ u: ApiUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(avatar: u.avatar, color: u.color, letter: u.letter, handle: u.handle, name: u.name, size: 36)
                TextField("", text: $wallText, prompt: Text("Что нового?").foregroundColor(Theme.text3), axis: .vertical)
                    .foregroundColor(Theme.text).lineLimit(1...5)
            }
            if !wallPhotoURL.isEmpty {
                NetImage(src: wallPhotoURL) { Theme.bg2 }.scaledToFill()
                    .frame(height: 140).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                PhotosPicker(selection: $wallPhoto, matching: .images) {
                    Image(systemName: "photo").font(.system(size: 19)).foregroundColor(Theme.accent)
                }
                Spacer()
                Button { post() } label: {
                    Text(posting ? "…" : "Опубликовать").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .opacity((wallText.trimmed.isEmpty && wallPhotoURL.isEmpty) || posting ? 0.45 : 1)
            }
        }
        .padding(12).background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Логика
    private func load() async {
        guard let u = store.user else { return }
        // Посты — из общего хранилища (единый источник для Ленты и профиля).
        async let feed: Void = postStore.loadIfNeeded()
        async let ph = try? await API.shared.userPhotos(u.id)
        async let f = try? await API.shared.friends()
        photos = (await ph) ?? []
        friends = (await f)?.friends ?? []
        await feed
    }
    private func like(_ post: Post) {
        postStore.toggleLike(post.id)
        Task {
            if let r = try? await API.shared.like(postId: post.id) {
                postStore.applyLike(post.id, liked: r.liked, count: r.likeCount)
            }
        }
    }
    private func upload(_ item: PhotosPickerItem?, isCover: Bool) async {
        guard let item else { return }
        uploading = true; defer { uploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data),
              let url = imageToDataURL(img, maxDimension: isCover ? 1200 : 400) else { return }
        if let updated = try? await API.shared.updateMe([isCover ? "cover" : "avatar": url]) { store.user = updated }
    }
    private func pickWallPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data), let url = imageToDataURL(img, maxDimension: 1200) else { return }
        wallPhotoURL = url
    }
    private func post() {
        let t = wallText.trimmed
        guard (!t.isEmpty || !wallPhotoURL.isEmpty), !posting else { return }
        posting = true
        Task {
            if let p = try? await API.shared.createPost(text: t, image: wallPhotoURL) {
                // В общее хранилище — и профиль, и Лента увидят пост сразу.
                postStore.prepend(p)
                if !p.image.isEmpty { photos.insert(PhotoItem(postId: p.id, image: p.image, createdAt: p.createdAt), at: 0) }
                wallText = ""; wallPhotoURL = ""; wallPhoto = nil
            }
            posting = false
        }
    }
}

private struct Zoomed: Identifiable { let src: String; var id: String { src } }

// Русские подписи/форматирование профиля.
func genderLabel(_ g: String) -> String? {
    switch g { case "male": return "Мужской"; case "female": return "Женский"; case "other": return "Другой"; default: return nil }
}
func formatBirthday(_ s: String) -> String? {
    let parts = s.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), m >= 1, m <= 12 else { return nil }
    let months = ["января","февраля","марта","апреля","мая","июня","июля","августа","сентября","октября","ноября","декабря"]
    var age = 0
    if let bd = DateComponents(calendar: .current, year: y, month: m, day: d).date {
        age = max(0, Calendar.current.dateComponents([.year], from: bd, to: Date()).year ?? 0)
    }
    return "\(d) \(months[m-1]) \(y) · \(age) \(pluralYears(age))"
}
func pluralYears(_ n: Int) -> String {
    let a = n % 100, b = n % 10
    if a >= 11 && a <= 14 { return "лет" }
    if b == 1 { return "год" }
    if b >= 2 && b <= 4 { return "года" }
    return "лет"
}
func joinedText(_ iso: String) -> String? {
    guard !iso.isEmpty else { return nil }
    let s = iso.contains("T") ? iso : iso.replacingOccurrences(of: " ", with: "T") + "Z"
    guard let d = ISO8601DateFormatter().date(from: s) else { return nil }
    let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "LLLL yyyy"
    return f.string(from: d)
}

// Чипы интересов с переносом.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlexWrap(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { it in
                Text(it).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.bg2).clipShape(Capsule())
            }
        }
    }
}

// Раскладка с переносом на новую строку (для чипов).
struct FlexWrap: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + lineH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}

// Просмотр картинки на весь экран.
struct ImageLightbox: View {
    let src: String
    var fallbackColor: String = ""
    var letter: String = ""
    let onClose: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if src.isEmpty {
                Circle().fill(Color(hexString: fallbackColor)).frame(width: 200, height: 200)
                    .overlay(Text(letter).font(.system(size: 90, weight: .bold)).foregroundColor(.white))
            } else {
                NetImage(src: src) { ProgressView().tint(.white) }.scaledToFit()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            .padding(12).background(.white.opacity(0.15)).clipShape(Circle())
                    }.padding(16)
                }
                Spacer()
            }
        }
        .onTapGesture { onClose() }
    }
}

// Достижения: уровень, очки, значки (открытые/закрытые).
struct AchievementsSheet: View {
    @EnvironmentObject var gam: Gamification
    @Environment(\.dismiss) var dismiss
    var body: some View {
        let lvl = gam.levelInfo
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Карточка уровня
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Уровень \(lvl.level)").font(.system(size: 20, weight: .heavy)).foregroundColor(Theme.text)
                                Text(lvl.name).font(.system(size: 14)).foregroundColor(Theme.text2)
                            }
                            Spacer()
                            Text("\(gam.points) очков").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.accent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.bg2).frame(height: 10)
                                Capsule().fill(Theme.accent).frame(width: geo.size.width * gam.progress, height: 10)
                            }
                        }.frame(height: 10)
                        HStack {
                            Text("\(gam.placesCount) мест · \(gam.unlockedCount) значков").font(.system(size: 12)).foregroundColor(Theme.text3)
                            Spacer()
                            if lvl.next > gam.points {
                                Text("до ур. \(lvl.level + 1): \(lvl.next - gam.points)").font(.system(size: 12)).foregroundColor(Theme.text3)
                            }
                        }
                    }
                    .padding(16).background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 16).padding(.top, 12)

                    // Список значков: полученные — цветные с датой, остальные — серые с прогрессом
                    VStack(spacing: 10) {
                        ForEach(BADGES) { b in
                            AchievementRow(badge: b,
                                           unlocked: gam.unlocked.contains { $0.id == b.id },
                                           date: gam.unlockDate(for: b),
                                           progress: b.progressCount?(gam.visits) ?? 0)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Достижения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.tint(Theme.accent) } }
        }
    }
}

// Одна строка достижения: иконка, название, описание и дата/прогресс.
private struct AchievementRow: View {
    let badge: Badge
    let unlocked: Bool
    let date: Date?
    let progress: Int

    var body: some View {
        HStack(spacing: 14) {
            Text(badge.icon).font(.system(size: 28))
                .frame(width: 54, height: 54)
                .background(unlocked ? Theme.accent.opacity(0.12) : Theme.bg2)
                .clipShape(Circle())
                .overlay(Circle().stroke(unlocked ? Theme.accent : Theme.border, lineWidth: 1.5))
                .grayscale(unlocked ? 0 : 1).opacity(unlocked ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 4) {
                Text(badge.title).font(.system(size: 15, weight: .bold))
                    .foregroundColor(unlocked ? Theme.text : Theme.text2)
                Text(badge.description).font(.system(size: 13))
                    .foregroundColor(Theme.text3).fixedSize(horizontal: false, vertical: true)
                if unlocked {
                    Text(date.map { "Получено \(achievementDate($0))" } ?? "Получено")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.accent)
                } else if badge.goal > 0 {
                    let capped = min(progress, badge.goal)
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.bg2).frame(height: 6)
                                Capsule().fill(Theme.text3)
                                    .frame(width: geo.size.width * CGFloat(capped) / CGFloat(badge.goal), height: 6)
                            }
                        }.frame(height: 6)
                        Text("\(capped) / \(badge.goal)").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.text3)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: unlocked ? "checkmark.seal.fill" : "lock.fill")
                .font(.system(size: unlocked ? 18 : 14))
                .foregroundColor(unlocked ? Theme.accent : Theme.text3)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(unlocked ? Theme.accent.opacity(0.3) : Theme.border, lineWidth: unlocked ? 1 : 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// Дата получения значка: «15 июля 2026».
private func achievementDate(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMMM yyyy"
    return f.string(from: d)
}

// Друзья: список, заявки и поиск новых людей.
// Все действия идут на тот же сервер, что и у сайта, — списки совпадают.
struct FriendsSheet: View {
    // Стартовый список приходит из профиля, дальше экран обновляет его сам.
    let friends: [ChatUser]
    @Environment(\.dismiss) var dismiss

    @State private var tab = 0
    @State private var list: [ChatUser] = []
    @State private var incoming: [ChatUser] = []
    @State private var outgoing: [ChatUser] = []
    @State private var query = ""
    @State private var found: [ChatUser] = []
    @State private var searching = false
    // Кого сейчас обрабатываем — чтобы не жать кнопку дважды.
    @State private var busy: Set<Int> = []
    @State private var error = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Друзья (\(list.count))").tag(0)
                    Text(incoming.isEmpty ? "Заявки" : "Заявки (\(incoming.count))").tag(1)
                    Text("Найти").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)

                if !error.isEmpty {
                    Text(error).font(.system(size: 13)).foregroundColor(Theme.accent)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }

                ScrollView {
                    switch tab {
                    case 0: friendsList
                    case 1: requestsList
                    default: searchList
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Друзья")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.tint(Theme.accent) } }
        }
        .task {
            list = friends
            await reload()
        }
    }

    // MARK: списки

    @ViewBuilder private var friendsList: some View {
        if list.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "person.2")
                    .font(.system(size: 40, weight: .light)).foregroundColor(Theme.text3)
                Text("Пока нет друзей")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                Text("Найдите знакомых по имени или нику.")
                    .font(.system(size: 14)).foregroundColor(Theme.text3)
                    .multilineTextAlignment(.center)
                Button { tab = 2 } label: {
                    Label("Найти друзей", systemImage: "magnifyingglass")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Theme.accent).clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity).padding(.top, 50).padding(.horizontal, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(list) { f in
                    row(f) {
                        actionButton("Удалить", filled: false) { await remove(f) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var requestsList: some View {
        LazyVStack(spacing: 0) {
            if !incoming.isEmpty {
                sectionHeader("Входящие")
                ForEach(incoming) { u in
                    row(u) {
                        actionButton("Принять", filled: true) { await accept(u) }
                        actionButton("Отклонить", filled: false) { await remove(u) }
                    }
                }
            }
            if !outgoing.isEmpty {
                sectionHeader("Исходящие")
                ForEach(outgoing) { u in
                    row(u) {
                        actionButton("Отменить", filled: false) { await remove(u) }
                    }
                }
            }
            if incoming.isEmpty && outgoing.isEmpty {
                emptyText("Заявок нет")
            }
        }
    }

    @ViewBuilder private var searchList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(Theme.text3)
                TextField("", text: $query,
                          prompt: Text("Имя или ник").foregroundColor(Theme.text3))
                    .foregroundColor(Theme.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button { query = ""; found = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Theme.text3)
                    }
                }
            }
            .padding(12).background(Theme.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16).padding(.bottom, 12)

            if searching {
                ProgressView().tint(Theme.accent).padding(.top, 20)
            } else if found.isEmpty && !query.isEmpty {
                emptyText("Никого не нашлось")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(found) { u in
                        row(u) { relationButton(u) }
                    }
                }
            }
        }
        // Ищем с задержкой, чтобы не дёргать сервер на каждую букву.
        .onChange(of: query) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                await search()
            }
        }
    }

    // Что предложить в поиске — зависит от того, кем этот человек уже приходится.
    @ViewBuilder private func relationButton(_ u: ChatUser) -> some View {
        if list.contains(where: { $0.id == u.id }) {
            Text("В друзьях").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text3)
        } else if outgoing.contains(where: { $0.id == u.id }) {
            actionButton("Отменить", filled: false) { await remove(u) }
        } else if incoming.contains(where: { $0.id == u.id }) {
            actionButton("Принять", filled: true) { await accept(u) }
        } else {
            actionButton("Добавить", filled: true) { await add(u) }
        }
    }

    // MARK: кирпичики

    private func row<A: View>(_ u: ChatUser, @ViewBuilder actions: () -> A) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AvatarView(avatar: u.avatar, color: u.color, letter: u.letter, handle: u.handle, name: u.name, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(u.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                    Text("@\(u.handle)").font(.system(size: 13)).foregroundColor(Theme.text3)
                }
                Spacer()
                if busy.contains(u.id) {
                    ProgressView().tint(Theme.accent)
                } else {
                    HStack(spacing: 8) { actions() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider().overlay(Theme.border).padding(.leading, 74)
        }
    }

    private func actionButton(_ title: String, filled: Bool,
                              _ act: @escaping () async -> Void) -> some View {
        Button { Task { await act() } } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(filled ? .white : Theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(filled ? Theme.accent : Theme.accent.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func sectionHeader(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.text3).kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
    }

    private func emptyText(_ s: String) -> some View {
        Text(s).font(.system(size: 15)).foregroundColor(Theme.text3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 32)
    }

    // MARK: действия

    private func reload() async {
        guard let r = try? await API.shared.friends() else { return }
        list = r.friends; incoming = r.incoming; outgoing = r.outgoing
    }

    private func search() async {
        let q = query.trimmed
        guard q.count >= 2 else { found = []; return }
        searching = true
        defer { searching = false }
        found = (try? await API.shared.searchUsers(q)) ?? []
    }

    private func add(_ u: ChatUser) async {
        // Статус ('outgoing' или сразу 'friends') не разбираем — списки
        // всё равно перечитываются с сервера сразу после действия.
        await run(u) { _ = try await API.shared.addFriend(u.id) }
    }
    private func accept(_ u: ChatUser) async {
        await run(u) { try await API.shared.acceptFriend(u.id) }
    }
    private func remove(_ u: ChatUser) async {
        await run(u) { try await API.shared.removeFriend(u.id) }
    }

    // Общая обёртка: блокирует кнопку, показывает ошибку, перечитывает списки.
    private func run(_ u: ChatUser, _ act: () async throws -> Void) async {
        busy.insert(u.id)
        error = ""
        do { try await act() } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Не получилось"
        }
        busy.remove(u.id)
        await reload()
    }
}

// Форма редактирования: имя, город, о себе, дата рождения, пол, интересы.
struct EditProfileSheet: View {
    var focusBio: Bool = false
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var bio = ""
    @State private var interests = ""
    @State private var gender = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var saving = false
    @FocusState private var bioFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Имя", text: $name)
                    field("Город", text: $city)
                    labeled("О СЕБЕ") {
                        TextField("", text: $bio, prompt: Text("Пару слов о себе").foregroundColor(Theme.text3), axis: .vertical)
                            .foregroundColor(Theme.text).lineLimit(3...6)
                            .focused($bioFocused)
                            .padding(12).background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    labeled("ПОЛ") {
                        Picker("", selection: $gender) {
                            Text("—").tag("")
                            Text("Муж.").tag("male")
                            Text("Жен.").tag("female")
                            Text("Другой").tag("other")
                        }.pickerStyle(.segmented)
                    }
                    labeled("ДЕНЬ РОЖДЕНИЯ") {
                        Toggle("Указать дату", isOn: $hasBirthday).tint(Theme.accent).foregroundColor(Theme.text)
                        if hasBirthday {
                            DatePicker("", selection: $birthday, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden().tint(Theme.accent)
                        }
                    }
                    field("Интересы (через запятую)", text: $interests)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.tint(Theme.text2) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }.tint(Theme.accent).fontWeight(.semibold).disabled(saving)
                }
            }
        }
        .onAppear(perform: fill)
        .task {
            // Пришли по кнопке «Рассказать о себе» — сразу ставим курсор в поле.
            if focusBio {
                try? await Task.sleep(for: .milliseconds(350))
                bioFocused = true
            }
        }
    }

    private func fill() {
        guard let u = store.user else { return }
        name = u.name; city = u.city; bio = u.bio; interests = u.interests; gender = u.gender
        let p = u.birthdate.split(separator: "-")
        if p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
           let date = DateComponents(calendar: .current, year: y, month: m, day: d).date {
            birthday = date; hasBirthday = true
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text3).kerning(0.8)
            content()
        }
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        labeled(label.uppercased()) {
            TextField("", text: text).foregroundColor(Theme.text)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    private func save() {
        saving = true
        var fields: [String: Any] = [
            "name": name.trimmed, "city": city.trimmed, "bio": bio.trimmed,
            "interests": interests.trimmed, "gender": gender,
        ]
        if hasBirthday {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            fields["birthdate"] = f.string(from: birthday)
        } else {
            fields["birthdate"] = ""
        }
        Task {
            if let u = try? await API.shared.updateMe(fields) { store.user = u }
            saving = false; dismiss()
        }
    }
}

// Поделиться профилем: QR-код и ссылка. Формат ссылки пока заглушка.
struct ShareProfileSheet: View {
    let user: ApiUser
    @Environment(\.dismiss) var dismiss
    @State private var copied = false

    // Ссылка-заглушка: настоящий домен профилей появится позже.
    private var link: String { "https://localee.ru/u/\(user.handle)" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    AvatarView(avatar: user.avatar, color: user.color, letter: user.letter,
                               handle: user.handle, name: user.name, size: 64)
                    VStack(spacing: 2) {
                        Text(user.name).font(.system(size: 20, weight: .heavy)).foregroundColor(Theme.text)
                        Text("@\(user.handle)").font(.system(size: 14)).foregroundColor(Theme.text3)
                    }
                    // QR всегда на белом фоне — так его читают камеры в любой теме
                    Group {
                        if let img = qrImage(from: link) {
                            Image(uiImage: img).interpolation(.none).resizable()
                                .scaledToFit().frame(width: 220, height: 220)
                        } else {
                            RoundedRectangle(cornerRadius: 12).fill(Theme.bg2).frame(width: 220, height: 220)
                        }
                    }
                    .padding(16).background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("Наведите камеру, чтобы открыть профиль")
                        .font(.system(size: 13)).foregroundColor(Theme.text3)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    UIPasteboard.general.string = link
                    withAnimation { copied = true }
                } label: {
                    Label(copied ? "Ссылка скопирована" : "Скопировать ссылку",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Поделиться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.tint(Theme.accent) }
            }
        }
        .presentationDetents([.large])
    }
}

// Генерация QR-кода из строки (CoreImage). Чёрный на прозрачном.
private let qrContext = CIContext()
func qrImage(from string: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
          let cg = qrContext.createCGImage(out, from: out.extent) else { return nil }
    return UIImage(cgImage: cg)
}
