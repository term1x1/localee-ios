import SwiftUI
import MapKit
import CoreLocation

// MARK: - Пин с иконкой категории (вместо простого кружка)
struct MapPinView: View {
    let color: Color
    let icon: String
    var selected = false

    var body: some View {
        VStack(spacing: -3) {
            ZStack {
                Circle().fill(color)
                    .frame(width: selected ? 38 : 32, height: selected ? 38 : 32)
                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                Image(systemName: icon)
                    .font(.system(size: selected ? 16 : 13, weight: .bold))
                    .foregroundColor(.white)
            }
            // «Хвостик» пина
            Triangle().fill(color)
                .frame(width: 10, height: 7)
                .overlay(Triangle().stroke(.white, lineWidth: 0).opacity(0))
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Кластер слипшихся точек
struct ClusterBadge: View {
    let count: Int
    var body: some View {
        ZStack {
            Circle().fill(Theme.accent)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            Text("\(count)").font(.system(size: count > 99 ? 13 : 15, weight: .heavy))
                .foregroundColor(.white)
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
    private var size: CGFloat { count < 10 ? 38 : (count < 100 ? 44 : 50) }
}

// MARK: - Кластеризация по сетке (размер ячейки зависит от зума)
struct PlaceCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let places: [Place]
    var count: Int { places.count }
}

func clusterPlaces(_ places: [Place], span: MKCoordinateSpan) -> [PlaceCluster] {
    // Чем сильнее приближение, тем мельче ячейка — точки «расклеиваются»
    let cell = max(span.latitudeDelta / 9, 0.0004)
    var buckets: [String: [Place]] = [:]
    for p in places {
        let key = "\(Int((p.lat / cell).rounded(.down)))_\(Int((p.lng / cell).rounded(.down)))"
        buckets[key, default: []].append(p)
    }
    return buckets.map { key, ps in
        PlaceCluster(
            id: key,
            coordinate: CLLocationCoordinate2D(
                latitude: ps.map(\.lat).reduce(0, +) / Double(ps.count),
                longitude: ps.map(\.lng).reduce(0, +) / Double(ps.count)),
            places: ps)
    }
}

// Регион, охватывающий точки кластера (для призума по тапу)
func regionFor(_ places: [Place]) -> MKCoordinateRegion {
    let lats = places.map(\.lat), lngs = places.map(\.lng)
    let center = CLLocationCoordinate2D(
        latitude: (lats.min()! + lats.max()!) / 2,
        longitude: (lngs.min()! + lngs.max()!) / 2)
    let span = MKCoordinateSpan(
        latitudeDelta: max((lats.max()! - lats.min()!) * 2.2, 0.006),
        longitudeDelta: max((lngs.max()! - lngs.min()!) * 2.2, 0.006))
    return MKCoordinateRegion(center: center, span: span)
}

// MARK: - Геолокация для кнопки «моя локация»
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var authorized = false

    override init() {
        super.init()
        manager.delegate = self
        authorized = [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }
    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let ok = [.authorizedWhenInUse, .authorizedAlways].contains(m.authorizationStatus)
        Task { @MainActor in self.authorized = ok }
    }
}
