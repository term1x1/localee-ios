import SwiftUI

// Шторка снизу в стиле Apple Maps / Яндекс.Карт:
// свёрнута — виден только «peek», тянешь вверх — плавно раскрывается,
// карта за ней затемняется (скрим), снап учитывает скорость жеста (флик),
// тап по затемнению — закрыть.
struct BottomSheet<Content: View>: View {
    @Binding var expanded: Bool
    let peekHeight: CGFloat
    @ViewBuilder let content: () -> Content

    @GestureState private var drag: CGFloat = 0
    private let anim = Animation.spring(response: 0.4, dampingFraction: 0.85)

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.height
            let sheetHeight = full * 0.92
            let collapsedShift = sheetHeight - peekHeight
            let base = expanded ? 0 : collapsedShift
            let y = min(max(base + drag, 0), collapsedShift)
            // 0 — свёрнута, 1 — раскрыта (плавно во время перетаскивания)
            let openFraction = collapsedShift > 0 ? 1 - (y / collapsedShift) : 0

            ZStack(alignment: .bottom) {
                // Затемнение карты по мере раскрытия (в пределах области карты)
                Color.black.opacity(0.30 * openFraction)
                    .allowsHitTesting(expanded)
                    .onTapGesture { withAnimation(anim) { expanded = false } }

                // Слой 1 — фон шторки: тянется до самого низа экрана (под таб-бар),
                // чтобы низ был единой поверхностью без шва вокруг кнопок.
                RoundedCorners(radius: 28, corners: [.topLeft, .topRight])
                    .fill(Theme.bg)
                    .frame(width: geo.size.width, height: sheetHeight)
                    .shadow(color: .black.opacity(0.28), radius: 20, y: -2)
                    .offset(y: y)
                    .ignoresSafeArea(edges: .bottom)

                // Слой 2 — содержимое: обрезано по видимой области карты (не лезет
                // под таб-бар при раскрытии).
                VStack(spacing: 0) {
                    Capsule().fill(Theme.text3.opacity(0.5))
                        .frame(width: 38, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                    content()
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 24)
                                .onEnded { v in
                                    if v.translation.height > 110,
                                       abs(v.translation.width) < 80 {
                                        withAnimation(anim) { expanded = false }
                                    }
                                }
                        )
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: sheetHeight, alignment: .top)
                .offset(y: y)
                .frame(width: geo.size.width, height: full, alignment: .bottom)
                // Плавное затухание содержимого в цвет фона у нижней границы —
                // контент не «режется полоской» об таб-бар, а мягко уходит в фон.
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 40)
                        .allowsHitTesting(false)
                }
                .clipped()
            }
            .animation(anim, value: expanded)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($drag) { v, s, _ in s = v.translation.height }
            .onEnded { v in
                // Учитываем скорость: резкий флик вверх/вниз переключает состояние
                let projected = v.translation.height + v.predictedEndTranslation.height * 0.35
                withAnimation(anim) {
                    if projected < -50 { expanded = true }
                    else if projected > 50 { expanded = false }
                }
            }
    }
}

// Скругление только выбранных углов.
struct RoundedCorners: Shape {
    var radius: CGFloat = 20
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}
