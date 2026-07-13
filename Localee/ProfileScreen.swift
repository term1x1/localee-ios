import SwiftUI
import PhotosUI

struct ProfileScreen: View {
    @EnvironmentObject var store: AppStore
    @State private var posts: [Post] = []
    @State private var friendsCount = 0
    @State private var loading = true
    @State private var editing = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?
    @State private var uploading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let u = store.user {
                    VStack(spacing: 0) {
                        header(u)

                        HStack(spacing: 10) {
                            stat("\(posts.count)", "Посты")
                            stat("\(friendsCount)", "Друзья")
                            stat(u.city.isEmpty ? "—" : u.city, "Город")
                        }
                        .padding(.horizontal, 16).padding(.top, 16)

                        if !u.bio.isEmpty {
                            Text(u.bio)
                                .font(.system(size: 15)).foregroundColor(Theme.text2)
                                .frame(maxWidth: .infinity, alignment: .leading).lineSpacing(3)
                                .padding(16).background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal, 16).padding(.top, 12)
                        }

                        // Кнопка редактирования
                        Button { editing = true } label: {
                            Label("Редактировать профиль", systemImage: "pencil")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 16).padding(.top, 12)

                        // Стена записей
                        HStack {
                            Text("Мои записи").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 8)

                        if loading {
                            ProgressView().tint(Theme.accent).padding(.top, 20)
                        } else if posts.isEmpty {
                            Text("Пока нет записей").foregroundColor(Theme.text3).padding(.top, 16)
                        } else {
                            VStack(spacing: 12) { ForEach(posts) { PostCard(post: $0, onLike: {}) } }
                                .padding(.horizontal, 14)
                        }

                        Button { store.signOut() } label: {
                            Text("Выйти")
                                .font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.accent)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
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
        .onChange(of: avatarItem) { _, item in Task { await upload(item, isCover: false) } }
        .onChange(of: coverItem) { _, item in Task { await upload(item, isCover: true) } }
    }

    private func header(_ u: ApiUser) -> some View {
        VStack(spacing: 0) {
            // Обложка — закруглённая, с отступами
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if !u.cover.isEmpty {
                        NetImage(src: u.cover) { coverGradient }.scaledToFill()
                    } else {
                        coverGradient
                    }
                }
                .frame(height: 150).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20))

                PhotosPicker(selection: $coverItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14)).foregroundColor(.white)
                        .padding(9).background(.black.opacity(0.45)).clipShape(Circle())
                }
                .padding(12)
            }
            .padding(.horizontal, 16)

            // Аватар с кнопкой смены
            ZStack(alignment: .bottomTrailing) {
                AvatarView(avatar: u.avatar, color: u.color, letter: u.letter, size: 92)
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 4))
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12)).foregroundColor(.white)
                        .padding(7).background(Theme.accent).clipShape(Circle())
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                }
            }
            .offset(y: -46).padding(.bottom, -46)

            if uploading {
                ProgressView().tint(Theme.accent).padding(.top, 12)
            }

            Text(u.name).font(.system(size: 24, weight: .heavy)).foregroundColor(Theme.text).padding(.top, 10)
            Text("@\(u.handle)").font(.system(size: 15)).foregroundColor(Theme.text2)
            if u.role == "admin" {
                Text("Администратор")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.15)).clipShape(Capsule()).padding(.top, 6)
            }
        }
    }

    private var coverGradient: some View {
        LinearGradient(colors: [Theme.accent, Theme.nightlife],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.text).lineLimit(1)
            Text(label).font(.system(size: 12)).foregroundColor(Theme.text3)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func load() async {
        guard let u = store.user else { return }
        async let p = try? await API.shared.userPosts(u.id)
        async let f = try? await API.shared.friends()
        posts = (await p) ?? []
        friendsCount = (await f)?.friends.count ?? 0
        loading = false
    }

    private func upload(_ item: PhotosPickerItem?, isCover: Bool) async {
        guard let item else { return }
        uploading = true; defer { uploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data),
              let url = imageToDataURL(img, maxDimension: isCover ? 1200 : 400) else { return }
        if let updated = try? await API.shared.updateMe([isCover ? "cover" : "avatar": url]) {
            store.user = updated
        }
    }
}

// Форма редактирования имени / города / «о себе».
struct EditProfileSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var bio = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Имя", text: $name)
                    field("Город", text: $city)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("О СЕБЕ").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.text3).kerning(0.8)
                        TextField("", text: $bio, prompt: Text("Пару слов о себе").foregroundColor(Theme.text3), axis: .vertical)
                            .foregroundColor(Theme.text).lineLimit(3...6)
                            .padding(12).background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.tint(Theme.text2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }.tint(Theme.accent).fontWeight(.semibold).disabled(saving)
                }
            }
        }
        .onAppear {
            name = store.user?.name ?? ""
            city = store.user?.city ?? ""
            bio = store.user?.bio ?? ""
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.text3).kerning(0.8)
            TextField("", text: text)
                .foregroundColor(Theme.text)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func save() {
        saving = true
        Task {
            if let u = try? await API.shared.updateMe([
                "name": name.trimmed, "city": city.trimmed, "bio": bio.trimmed,
            ]) {
                store.user = u
            }
            saving = false
            dismiss()
        }
    }
}
