import SwiftUI

// Карусель фотографий с пейджингом (фото прилипает к краям).
// Переиспользуется в карточке места, карточке метки и постах ленты.
// Пустая строка в photos = градиент-заглушка с номером.
struct PhotoCarousel: View {
    let photos: [String]
    var height: CGFloat = 190
    var corner: CGFloat = 16
    var tint: Color = .gray            // цвет категории для заглушек/фолбэка
    var icon: String = "photo"         // иконка категории для фолбэка
    var allowsFullscreen = true

    @State private var page = 0
    @State private var fullscreen = false

    private var isEmpty: Bool { photos.isEmpty }
    private var single: Bool { photos.count <= 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isEmpty {
                fallback
            } else if single {
                slide(photos[0], index: 0)
                    .onTapGesture { if allowsFullscreen { fullscreen = true } }
            } else {
                TabView(selection: $page) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, src in
                        slide(src, index: i)
                            .onTapGesture { if allowsFullscreen { fullscreen = true } }
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))   // пейджинг без своих точек

                // Индикаторы: до 5 фото — точки, больше — счётчик
                if photos.count <= 5 {
                    HStack(spacing: 6) {
                        ForEach(0..<photos.count, id: \.self) { i in
                            Circle()
                                .fill(i == page ? Color.white : Color.white.opacity(0.45))
                                .frame(width: i == page ? 7 : 6, height: i == page ? 7 : 6)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.28)).clipShape(Capsule())
                    .padding(.bottom, 10)
                } else {
                    Text("\(page + 1)/\(photos.count)")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.black.opacity(0.45)).clipShape(Capsule())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 10).padding(.bottom, 10)
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .fullScreenCover(isPresented: $fullscreen) {
            PhotoViewer(photos: photos, start: page, tint: tint, icon: icon)
        }
    }

    // Один слайд: реальное фото или градиент-заглушка с номером
    @ViewBuilder private func slide(_ src: String, index: Int) -> some View {
        if src.isEmpty {
            ZStack {
                LinearGradient(colors: [tint.opacity(0.75), tint.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text("\(index + 1)").font(.system(size: 44, weight: .heavy))
                    .foregroundColor(.white.opacity(0.85))
            }
        } else {
            NetImage(src: src) {
                LinearGradient(colors: [tint.opacity(0.7), tint.opacity(0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .scaledToFill()
        }
    }

    // Фото нет вообще — градиент категории + её иконка
    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.8), tint.opacity(0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon).font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// Полноэкранный просмотр с тем же листанием. Закрытие — свайп вниз или «×».
struct PhotoViewer: View {
    let photos: [String]
    var start = 0
    var tint: Color = .gray
    var icon: String = "photo"
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var dragY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, src in
                    Group {
                        if src.isEmpty {
                            ZStack {
                                LinearGradient(colors: [tint.opacity(0.75), tint.opacity(0.35)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                Text("\(i + 1)").font(.system(size: 80, weight: .heavy))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        } else {
                            NetImage(src: src) { ProgressView().tint(.white) }.scaledToFit()
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))

            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                    .padding(12).background(.white.opacity(0.16)).clipShape(Circle())
            }
            .padding(16)
        }
        .offset(y: dragY)
        .gesture(
            DragGesture()
                .onChanged { v in if v.translation.height > 0 { dragY = v.translation.height } }
                .onEnded { v in
                    if v.translation.height > 120 { dismiss() } else { withAnimation(.spring) { dragY = 0 } }
                }
        )
        .onAppear { page = start }
    }
}
