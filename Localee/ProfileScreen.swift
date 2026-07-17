import SwiftUI
import PhotosUI

struct ProfileScreen: View {
    @EnvironmentObject var store: AppStore
    @State private var posts: [Post] = []
    @State private var photos: [PhotoItem] = []
    @State private var friends: [ChatUser] = []
    @State private var loading = true
    @State private var editing = false
    @State private var showFriends = false
    @State private var avatarZoom = false
    @State private var photoZoom: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?
    @State private var uploading = false
    // Композер стены
    @State private var wallText = ""
    @State private var wallPhoto: PhotosPickerItem?
    @State private var wallPhotoURL = ""
    @State private var posting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let u = store.user {
                    VStack(spacing: 0) {
                        header(u)
                        statsRow
                        editButton
                        aboutSection(u)
                        if !photos.isEmpty { photosSection }
                        wallSection(u)
                        logoutButton
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
        }
        .task { await load() }
        .sheet(isPresented: $editing) { EditProfileSheet() }
        .sheet(isPresented: $showFriends) { FriendsSheet(friends: friends) }
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

            ZStack(alignment: .bottomTrailing) {
                Button { if !u.avatar.isEmpty { avatarZoom = true } } label: {
                    AvatarView(avatar: u.avatar, color: u.color, letter: u.letter, size: 92)
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 4))
                }
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Image(systemName: "camera.fill").font(.system(size: 12)).foregroundColor(.white)
                        .padding(7).background(Theme.accent).clipShape(Circle())
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                }
            }
            .offset(y: -46).padding(.bottom, -46)

            if uploading { ProgressView().tint(Theme.accent).padding(.top, 12) }

            Text(u.name).font(.system(size: 24, weight: .heavy)).foregroundColor(Theme.text).padding(.top, 10)
            Text("@\(u.handle) · #\(u.id)").font(.system(size: 15)).foregroundColor(Theme.text2)
            if u.role == "admin" {
                Text("Администратор").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.15)).clipShape(Capsule()).padding(.top, 6)
            }
        }
    }

    private var coverGradient: some View {
        LinearGradient(colors: [Theme.accent, Theme.nightlife], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Статистика
    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("\(posts.count)", "Посты")
            stat("\(photos.count)", "Фото")
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
        Button { editing = true } label: {
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
                Text(u.bio.isEmpty ? "Пользователь пока не рассказал о себе" : u.bio)
                    .font(.system(size: 15)).foregroundColor(u.bio.isEmpty ? Theme.text3 : Theme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading).lineSpacing(3)
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
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Мои записи")
            wallComposer(u)
            if loading {
                ProgressView().tint(Theme.accent).padding(.top, 16)
            } else if posts.isEmpty {
                Text("Пока нет записей").foregroundColor(Theme.text3).padding(.top, 8)
            } else {
                ForEach(posts) { PostCard(post: $0, onLike: {}) }
            }
        }
        .padding(.horizontal, 16).padding(.top, 20)
    }

    private func wallComposer(_ u: ApiUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(avatar: u.avatar, color: u.color, letter: u.letter, size: 36)
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

    private var logoutButton: some View {
        Button { store.signOut() } label: {
            Text("Выйти").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.accent)
                .frame(maxWidth: .infinity).padding(.vertical, 14).background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }.padding(16).padding(.bottom, 12)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Логика
    private func load() async {
        guard let u = store.user else { return }
        async let p = try? await API.shared.userPosts(u.id)
        async let ph = try? await API.shared.userPhotos(u.id)
        async let f = try? await API.shared.friends()
        posts = (await p) ?? []
        photos = (await ph) ?? []
        friends = (await f)?.friends ?? []
        loading = false
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
                posts.insert(p, at: 0)
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

// Список друзей.
struct FriendsSheet: View {
    let friends: [ChatUser]
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                if friends.isEmpty {
                    Text("Пока нет друзей").foregroundColor(Theme.text3).padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(friends) { f in
                            HStack(spacing: 12) {
                                AvatarView(avatar: f.avatar, color: f.color, letter: f.letter, size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                                    Text("@\(f.handle)").font(.system(size: 13)).foregroundColor(Theme.text3)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            Divider().overlay(Theme.border).padding(.leading, 74)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Друзья")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.tint(Theme.accent) } }
        }
    }
}

// Форма редактирования: имя, город, о себе, дата рождения, пол, интересы.
struct EditProfileSheet: View {
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Имя", text: $name)
                    field("Город", text: $city)
                    labeled("О СЕБЕ") {
                        TextField("", text: $bio, prompt: Text("Пару слов о себе").foregroundColor(Theme.text3), axis: .vertical)
                            .foregroundColor(Theme.text).lineLimit(3...6)
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
