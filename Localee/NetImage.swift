import SwiftUI

// Картинка из строки сервера: поддерживает и data:base64 (аватары/обложки/фото),
// и обычные http(s)-ссылки. AsyncImage сам по себе data-URL не умеет.
struct NetImage<Placeholder: View>: View {
    let src: String
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        if src.hasPrefix("data:"), let img = decodeDataURL(src) {
            Image(uiImage: img).resizable()
        } else if let url = URL(string: src), src.hasPrefix("http") {
            AsyncImage(url: url) { $0.resizable() } placeholder: { placeholder() }
        } else {
            placeholder()
        }
    }

    private func decodeDataURL(_ s: String) -> UIImage? {
        guard let comma = s.firstIndex(of: ","),
              let data = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }
}

func hasImage(_ s: String) -> Bool { !s.isEmpty }
