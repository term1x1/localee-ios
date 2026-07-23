import SwiftUI
import CoreLocation

// Экран построенного маршрута: порядок точек, итоги, правка, старт.
struct RouteScreen: View {
    @Binding var route: [Place]
    var onStart: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    // Пешком считаем по 5 км/ч → 12 минут на километр.
    private var distanceKm: Double { routeDistanceKm(route) }
    private var walkMinutes: Int { Int((distanceKm * 12).rounded()) }
    private var visitMinutes: Int { route.reduce(0) { $0 + $1.duration } }
    private var totalMinutes: Int { visitMinutes + walkMinutes }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summary
                list
                startButton
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Ваш маршрут")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }.tint(Theme.text2)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(editing ? "Готово" : "Изменить") {
                        withAnimation { editing.toggle() }
                    }.tint(Theme.accent).fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Итоги
    private var summary: some View {
        HStack(spacing: 0) {
            stat("\(route.count)", "точек", "mappin.and.ellipse", Color(hex: 0x3B82F6))
            divider
            stat(formatDuration(totalMinutes), "всего", "clock.fill", Color(hex: 0xF59E0B))
            divider
            stat(String(format: "%.1f км", distanceKm), "пешком", "figure.walk", Color(hex: 0x22C55E))
        }
        .padding(.vertical, 14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 34)
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(tint)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text).lineLimit(1)
            Text(label).font(.system(size: 11)).foregroundColor(Theme.text3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Список точек
    private var list: some View {
        List {
            ForEach(Array(route.enumerated()), id: \.element.id) { idx, place in
                HStack(spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(place.category.color).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.text)
                        HStack(spacing: 6) {
                            Text(place.category.label)
                            Text("· ~\(formatDuration(place.duration))")
                        }
                        .font(.system(size: 12)).foregroundColor(Theme.text3)
                    }
                    Spacer()
                    // Расстояние до следующей точки
                    if idx < route.count - 1 {
                        let d = distanceKm(route[idx], route[idx + 1])
                        Text(String(format: "%.1f км", d))
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text3)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.border)
            }
            .onDelete { route.remove(atOffsets: $0) }
            .onMove { route.move(fromOffsets: $0, toOffset: $1) }

            if route.isEmpty {
                Text("Все точки удалены — вернитесь и постройте маршрут заново.")
                    .font(.system(size: 14)).foregroundColor(Theme.text3)
                    .listRowBackground(Theme.bg)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
    }

    private var startButton: some View {
        Button { onStart(); dismiss() } label: {
            Label("Начать", systemImage: "figure.walk.motion")
                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .opacity(route.isEmpty ? 0.4 : 1)
        .disabled(route.isEmpty)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    private func distanceKm(_ a: Place, _ b: Place) -> Double {
        CLLocation(latitude: a.lat, longitude: a.lng)
            .distance(from: CLLocation(latitude: b.lat, longitude: b.lng)) / 1000
    }
}

// Суммарная длина маршрута по прямым между точками (км).
func routeDistanceKm(_ route: [Place]) -> Double {
    guard route.count > 1 else { return 0 }
    return zip(route, route.dropFirst()).reduce(0) { sum, pair in
        sum + CLLocation(latitude: pair.0.lat, longitude: pair.0.lng)
            .distance(from: CLLocation(latitude: pair.1.lat, longitude: pair.1.lng)) / 1000
    }
}

// 95 → «1 ч 35 мин», 40 → «40 мин»
func formatDuration(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m) мин" }
    return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
}
