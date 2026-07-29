import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Показ вложений (в посте и сообщении)

// Фото — галереей (1 крупно, 2+ сеткой), файлы — карточками со скачиванием.
struct AttachmentsView: View {
    let attachments: [Attachment]
    var maxWidth: CGFloat = 250
    @State private var zoom: Zoomed?

    private var images: [Attachment] { attachments.filter(\.isImage) }
    private var files: [Attachment] { attachments.filter { !$0.isImage } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if images.count == 1 {
                photo(images[0], height: 230)
            } else if images.count > 1 {
                let cols = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(images) { photo($0, height: 120) }
                }
                .frame(maxWidth: maxWidth)
            }
            ForEach(files) { fileCard($0) }
        }
        .fullScreenCover(item: $zoom) { z in ImageLightbox(src: z.src) { zoom = nil } }
    }

    private func photo(_ a: Attachment, height: CGFloat) -> some View {
        Button { zoom = Zoomed(src: a.data) } label: {
            // Размер задаёт пустой контейнер, картинка лишь заполняет его через
            // overlay. Если вешать scaledToFill прямо на картинку, широкое фото
            // требует ширину больше, чем есть: .frame(maxWidth: .infinity) её не
            // ограничивает (бесконечность — не потолок, а «занимай всё, что
            // дают»). Карточка становилась шире экрана и уводила вбок всю ленту.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(NetImage(src: a.data) { Theme.bg2 }.scaledToFill())
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func fileCard(_ a: Attachment) -> some View {
        Button { AttachmentSaver.open(a) } label: {
            HStack(spacing: 10) {
                Image(systemName: fileIcon(a.mime, a.name)).font(.system(size: 20))
                    .foregroundColor(.white).frame(width: 40, height: 40)
                    .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name.isEmpty ? "Файл" : a.name)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text).lineLimit(1)
                    Text("Открыть").font(.system(size: 12)).foregroundColor(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(8).frame(maxWidth: maxWidth)
            .background(Theme.bg2).clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct Zoomed: Identifiable { let src: String; var id: String { src } }

func fileIcon(_ mime: String, _ name: String) -> String {
    let n = name.lowercased()
    if mime.contains("pdf") || n.hasSuffix(".pdf") { return "doc.richtext" }
    if mime.contains("zip") || n.hasSuffix(".zip") { return "doc.zipper" }
    if mime.hasPrefix("audio") { return "music.note" }
    if mime.hasPrefix("video") { return "film" }
    if mime.contains("word") || n.hasSuffix(".doc") || n.hasSuffix(".docx") { return "doc.text" }
    return "doc.fill"
}

// Кладёт файл во временную папку и открывает системным «Поделиться».
//
// Данные приходят двумя способами: у новых записей это ссылка на хранилище
// (файл надо скачать), у старых — data-URL с base64 прямо в записи.
enum AttachmentSaver {
    static func open(_ a: Attachment) {
        if a.data.hasPrefix("http") {
            guard let src = URL(string: a.data) else { return }
            Task {
                guard let (bytes, _) = try? await URLSession.shared.data(from: src) else { return }
                await present(bytes, name: a.name)
            }
        } else {
            guard let comma = a.data.firstIndex(of: ","),
                  let bytes = Data(base64Encoded: String(a.data[a.data.index(after: comma)...]))
            else { return }
            Task { await present(bytes, name: a.name) }
        }
    }

    @MainActor
    private static func present(_ bytes: Data, name: String) {
        let file = name.isEmpty ? "file" : name
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        try? bytes.write(to: url)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController?.present(vc, animated: true)
    }
}

// MARK: - Выбор вложений (композер)

// Горизонтальный ряд превью выбранных вложений с удалением.
struct AttachmentPreviewRow: View {
    @Binding var items: [Attachment]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { a in
                    ZStack(alignment: .topTrailing) {
                        if a.isImage {
                            NetImage(src: a.data) { Theme.bg2 }.scaledToFill()
                                .frame(width: 72, height: 72).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: fileIcon(a.mime, a.name)).font(.system(size: 20)).foregroundColor(Theme.accent)
                                Text(a.name).font(.system(size: 9)).foregroundColor(Theme.text3).lineLimit(1)
                            }
                            .frame(width: 72, height: 72).background(Theme.bg2)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button { items.removeAll { $0.id == a.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                                .padding(5).background(.black.opacity(0.55)).clipShape(Circle())
                        }
                        .padding(3)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

// Загрузка выбранных из PhotosPicker фото в attachments.
func loadPickedPhotos(_ items: [PhotosPickerItem], limit: Int = 10) async -> [Attachment] {
    var result: [Attachment] = []
    for item in items.prefix(limit) {
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data), let url = imageToDataURL(img, maxDimension: 1400) {
            result.append(Attachment(type: "image", data: url))
        }
    }
    return result
}

// Прочитать файл из fileImporter в attachment (data-URL).
func fileToAttachment(_ url: URL, maxBytes: Int = 8 * 1024 * 1024) -> Attachment? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url), data.count <= maxBytes else { return nil }
    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    let b64 = "data:\(mime);base64," + data.base64EncodedString()
    return Attachment(type: "file", data: b64, name: url.lastPathComponent, mime: mime)
}
