import SwiftUI
import CoreLocation
import YandexMapsMobile

// Обёртка Яндекс.Карт для SwiftUI.
//
// YMKMapView — обычная UIKit-вьюха, поэтому заворачиваем её в UIViewRepresentable.
// Правило SDK: слушатели событий должны наследоваться от NSObject и жить, пока жива
// карта (SDK держит на них слабые ссылки) — поэтому все они лежат в Coordinator.
//
// Кластеризация здесь родная, от Яндекса (в MapKit её собирали руками по сетке):
// SDK сам решает, что слипается на текущем зуме. Внешний вид пинов и кластеров
// остаётся прежним — SwiftUI-вьюхи MapPinView/ClusterBadge превращаются в картинки
// через ImageRenderer, потому что Яндекс принимает иконку только как UIImage.

// Куда должна смотреть камера.
// `token` — счётчик: увеличиваем его каждый раз, когда нужно переехать. Без него
// SwiftUI не отличит повторную установку той же точки и карта не сдвинется.
struct MapCameraRequest: Equatable {
    var token: Int = 0
    var mode: Mode = .point(lat: 55.7558, lng: 37.6173, zoom: 11.2)   // центр Москвы

    enum Mode: Equatable {
        case point(lat: Double, lng: Double, zoom: Float)
        case fit([MapCoord])          // вписать все точки в экран (маршрут, кластер)
        case userLocation             // на геопозицию пользователя
    }
}

struct MapCoord: Equatable {
    let lat: Double
    let lng: Double
}

// Высота плавающего таб-бара — учитываем при подъёме логотипа Яндекса.
private let TAB_BAR_HEIGHT: CGFloat = 64

struct YandexMap: UIViewRepresentable {
    var places: [Place]
    var pins: [MapPin]
    var route: [Place]
    var selectedId: Int?
    var camera: MapCameraRequest
    // Высота шторки: поднимаем над ней логотип Яндекса (этого требует лицензия).
    var bottomInset: CGFloat = 0
    var onPlaceTap: (Place) -> Void = { _ in }
    var onPinTap: (MapPin) -> Void = { _ in }
    var onMapTap: (CLLocationCoordinate2D) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        // Без ключа SDK падает при первом же обращении — показываем понятную заглушку.
        guard MapConfig.hasKey else { return MapKeyMissingView() }

        // vulkanPreferred: true — обязательно для симулятора на Apple Silicon,
        // иначе карта не рисуется.
        let mapView = YMKMapView(frame: .zero, vulkanPreferred: true, transparencySupport: false)!
        let map = mapView.mapWindow.map
        map.mapType = .vectorMap
        map.isNightModeEnabled = scheme == .dark
        map.addInputListener(with: context.coordinator)

        context.coordinator.attach(to: mapView)
        context.coordinator.apply(camera: camera, animated: false)
        context.coordinator.rebuild(places: places, pins: pins, route: route,
                                    selectedId: selectedId, dark: scheme == .dark)
        context.coordinator.placeLogo(bottomInset: bottomInset)
        return mapView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard uiView is YMKMapView else { return }
        // Держим у координатора свежие замыкания — иначе тап отработает по старому состоянию.
        context.coordinator.parent = self

        let dark = scheme == .dark
        context.coordinator.setNightMode(dark)
        context.coordinator.rebuild(places: places, pins: pins, route: route,
                                    selectedId: selectedId, dark: dark)
        context.coordinator.apply(camera: camera, animated: true)
        context.coordinator.placeLogo(bottomInset: bottomInset)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, YMKMapInputListener, YMKMapObjectTapListener,
                             YMKClusterListener, YMKClusterTapListener,
                             CLLocationManagerDelegate {
        var parent: YandexMap
        private weak var mapView: YMKMapView?
        private var placesCollection: YMKClusterizedPlacemarkCollection?
        private var extrasCollection: YMKMapObjectCollection?
        private var userLayer: YMKUserLocationLayer?
        private let locator = CLLocationManager()
        // Ждём координату пользователя, чтобы доехать до неё, когда она придёт.
        private var awaitingUserLocation = false

        private var appliedCameraToken = -1
        private var renderedSignature = ""
        private var appliedLogoInset: CGFloat = -1
        private var isDark = false
        // Держим ссылки, чтобы объекты меток жили ровно столько же, сколько сами метки.
        private var markerRefs: [MarkerRef] = []

        init(_ parent: YandexMap) {
            self.parent = parent
            super.init()
            locator.delegate = self
        }

        func attach(to mapView: YMKMapView) {
            self.mapView = mapView
            let objects = mapView.mapWindow.map.mapObjects
            // Две коллекции: места кластеризуются, остальное (метки, маршрут) — нет.
            placesCollection = objects.addClusterizedPlacemarkCollection(with: self)
            extrasCollection = objects.add()

            // Слой геопозиции: синяя точка пользователя, если разрешение выдано.
            let layer = YMKMapKit.sharedInstance().createUserLocationLayer(with: mapView.mapWindow)
            layer.setVisibleWithOn(true)
            layer.isHeadingModeActive = false   // не крутим карту по компасу
            userLayer = layer
        }

        func setNightMode(_ dark: Bool) {
            mapView?.mapWindow.map.isNightModeEnabled = dark
        }

        // Перерисовываем только когда реально изменился состав — иначе карта
        // моргала бы на каждом обновлении SwiftUI.
        func rebuild(places: [Place], pins: [MapPin], route: [Place],
                     selectedId: Int?, dark: Bool) {
            // Собираем по частям: одна длинная цепочка «+» валила тайп-чекер Swift.
            let placesSig = places.map { String($0.id) }.joined(separator: ",")
            let pinsSig = pins.map { String($0.id) }.joined(separator: ",")
            let routeSig = route.map { String($0.id) }.joined(separator: ",")
            let selSig = selectedId.map(String.init) ?? "-"
            let themeSig = dark ? "d" : "l"
            let signature = [placesSig, pinsSig, routeSig, selSig, themeSig].joined(separator: "|")
            guard signature != renderedSignature,
                  let placesCollection, let extrasCollection else { return }
            renderedSignature = signature
            isDark = dark

            placesCollection.clear()
            extrasCollection.clear()
            markerRefs.removeAll()

            // Линия маршрута — под метками.
            if route.count > 1 {
                let line = extrasCollection.addPolyline(with: YMKPolyline(points: route.map {
                    YMKPoint(latitude: $0.lat, longitude: $0.lng)
                }))
                line.setStrokeColorWith(UIColor(Theme.accent))
                let style = line.style
                style.strokeWidth = 4
                line.style = style
                line.zIndex = 10
            }

            // Места — в кластерную коллекцию.
            for place in places {
                let mark = placesCollection.addPlacemark()
                mark.geometry = YMKPoint(latitude: place.lat, longitude: place.lng)
                let icon = MarkerIcon.placePin(color: UIColor(place.category.color),
                                               symbol: place.categoryIcon,
                                               selected: place.id == selectedId,
                                               dark: dark)
                mark.setIconWith(icon.image, style: icon.style(zIndex: place.id == selectedId ? 40 : 20))
                let ref = MarkerRef(.place(place))
                mark.userData = ref
                markerRefs.append(ref)
                mark.addTapListener(with: self)
            }
            // clusterRadius — в точках экрана, minZoom — дальше него кластеры не собираются.
            placesCollection.clusterPlacemarks(withClusterRadius: 60, minZoom: 16)

            // Пользовательские метки — поверх, без кластеризации.
            for pin in pins {
                let mark = extrasCollection.addPlacemark()
                mark.geometry = YMKPoint(latitude: pin.lat, longitude: pin.lng)
                let icon = MarkerIcon.userPin(emoji: pin.emoji, dark: dark)
                mark.setIconWith(icon.image, style: icon.style(zIndex: 30))
                let ref = MarkerRef(.pin(pin))
                mark.userData = ref
                markerRefs.append(ref)
                mark.addTapListener(with: self)
            }
        }

        func apply(camera: MapCameraRequest, animated: Bool) {
            guard camera.token != appliedCameraToken, let mapView else { return }
            appliedCameraToken = camera.token
            let map = mapView.mapWindow.map
            let animation = YMKAnimation(type: .smooth, duration: animated ? 0.45 : 0)

            switch camera.mode {
            case .point(let lat, let lng, let zoom):
                map.move(with: YMKCameraPosition(target: YMKPoint(latitude: lat, longitude: lng),
                                                 zoom: zoom, azimuth: 0, tilt: 0),
                         animation: animation, cameraCallback: nil)

            case .fit(let coords):
                move(map: map, fitting: coords, animation: animation)

            case .userLocation:
                if let here = locator.location?.coordinate {
                    moveTo(here, on: map, animation: animation)
                } else if locator.authorizationStatus == .notDetermined {
                    // Разрешения ещё нет: спрашиваем и ждём ответа (см. делегат ниже).
                    awaitingUserLocation = true
                    locator.requestWhenInUseAuthorization()
                } else {
                    // Разрешение есть, но координаты пока нет — запрашиваем разово.
                    awaitingUserLocation = true
                    locator.requestLocation()
                }
            }
        }

        private func moveTo(_ coord: CLLocationCoordinate2D, on map: YMKMap, animation: YMKAnimation) {
            map.move(with: YMKCameraPosition(
                target: YMKPoint(latitude: coord.latitude, longitude: coord.longitude),
                zoom: 14, azimuth: 0, tilt: 0),
                     animation: animation, cameraCallback: nil)
        }

        // MARK: геопозиция

        nonisolated func locationManager(_ manager: CLLocationManager,
                                         didUpdateLocations locations: [CLLocation]) {
            guard let coord = locations.last?.coordinate else { return }
            Task { @MainActor in
                guard self.awaitingUserLocation, let map = self.mapView?.mapWindow.map else { return }
                self.awaitingUserLocation = false
                self.moveTo(coord, on: map, animation: YMKAnimation(type: .smooth, duration: 0.45))
            }
        }

        nonisolated func locationManager(_ manager: CLLocationManager,
                                         didFailWithError error: Error) {
            Task { @MainActor in self.awaitingUserLocation = false }
        }

        // Разрешение только что выдали — доводим до конца тап по кнопке «моя локация».
        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let allowed = [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
            Task { @MainActor in
                guard self.awaitingUserLocation else { return }
                if allowed { self.locator.requestLocation() } else { self.awaitingUserLocation = false }
            }
        }

        private func move(map: YMKMap, fitting coords: [MapCoord], animation: YMKAnimation) {
            guard !coords.isEmpty else { return }
            let lats = coords.map(\.lat), lngs = coords.map(\.lng)
            let box = YMKBoundingBox(
                southWest: YMKPoint(latitude: lats.min()!, longitude: lngs.min()!),
                northEast: YMKPoint(latitude: lats.max()!, longitude: lngs.max()!))
            let fitted = map.cameraPosition(with: YMKGeometry(boundingBox: box))
            // Немного отъезжаем, чтобы крайние метки не липли к краям экрана.
            let position = YMKCameraPosition(target: fitted.target,
                                             zoom: max(fitted.zoom - 0.7, 3),
                                             azimuth: fitted.azimuth,
                                             tilt: fitted.tilt)
            map.move(with: position, animation: animation, cameraCallback: nil)
        }

        // Логотип Яндекса обязан быть виден — это условие лицензии. Поднимаем его над
        // шторкой и плавающим таб-баром, иначе он окажется под ними.
        func placeLogo(bottomInset: CGFloat) {
            guard let mapView else { return }
            let map = mapView.mapWindow.map
            let total = bottomInset + TAB_BAR_HEIGHT + mapView.safeAreaInsets.bottom
            guard total != appliedLogoInset else { return }
            appliedLogoInset = total
            map.logo.setAlignmentWith(YMKLogoAlignment(horizontalAlignment: .left,
                                                       verticalAlignment: .bottom))
            map.logo.setPaddingWith(YMKLogoPadding(horizontalPadding: 12,
                                                   verticalPadding: UInt(max(total, 8))))
        }

        // MARK: события карты

        nonisolated func onMapTap(with map: YMKMap, point: YMKPoint) {
            let coord = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            Task { @MainActor in self.parent.onMapTap(coord) }
        }

        nonisolated func onMapLongTap(with map: YMKMap, point: YMKPoint) {}

        nonisolated func onMapObjectTap(with mapObject: YMKMapObject, point: YMKPoint) -> Bool {
            guard let ref = mapObject.userData as? MarkerRef else { return false }
            Task { @MainActor in
                switch ref.kind {
                case .place(let place): self.parent.onPlaceTap(place)
                case .pin(let pin): self.parent.onPinTap(pin)
                }
            }
            return true   // событие обработали — дальше в onMapTap не уходит
        }

        // Кластер создан — рисуем на нём бейдж с числом и вешаем тап.
        nonisolated func onClusterAdded(with cluster: YMKCluster) {
            Task { @MainActor in
                let icon = MarkerIcon.cluster(count: Int(cluster.size), dark: self.isDark)
                cluster.appearance.setIconWith(icon.image, style: icon.style(zIndex: 25))
                cluster.addClusterTapListener(with: self)
            }
        }

        // Тап по кластеру — вписываем в экран всё, что внутри него.
        nonisolated func onClusterTap(with cluster: YMKCluster) -> Bool {
            let coords = cluster.placemarks.map {
                MapCoord(lat: $0.geometry.latitude, lng: $0.geometry.longitude)
            }
            Task { @MainActor in
                guard let map = self.mapView?.mapWindow.map else { return }
                self.move(map: map, fitting: coords,
                          animation: YMKAnimation(type: .smooth, duration: 0.45))
            }
            return true
        }
    }
}

// Чем является метка на карте — чтобы понять, что открыть при тапе.
final class MarkerRef: NSObject {
    enum Kind {
        case place(Place)
        case pin(MapPin)
    }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }
}

// MARK: - Картинки меток
//
// Яндекс принимает иконку только как UIImage (в MapKit можно было вставить
// SwiftUI-вью напрямую). Чтобы не рисовать пины заново, берём те же вьюхи из
// MapExtras.swift и растеризуем их через ImageRenderer — вид остаётся прежним.
@MainActor
enum MarkerIcon {
    // Картинка + куда у неё «остриё»: у пина с хвостиком якорь снизу, у круга — по центру.
    struct Icon {
        let image: UIImage
        let anchor: CGPoint

        func style(zIndex: Float) -> YMKIconStyle {
            let style = YMKIconStyle()
            style.anchor = NSValue(cgPoint: anchor)
            style.zIndex = NSNumber(value: zIndex)
            style.scale = NSNumber(value: 1.0)
            return style
        }
    }

    private static var cache: [String: Icon] = [:]
    // Запас вокруг вьюхи, чтобы ImageRenderer не срезал тень.
    private static let pad: CGFloat = 8

    static func placePin(color: UIColor, symbol: String, selected: Bool, dark: Bool) -> Icon {
        let key = "place-\(symbol)-\(color.description)-\(selected)-\(dark)"
        if let hit = cache[key] { return hit }
        let view = MapPinView(color: Color(uiColor: color), icon: symbol, selected: selected)
            .padding(pad)
        // У пина есть «хвостик» — якорь ставим на его кончик (низ картинки минус запас).
        let icon = render(view, dark: dark, anchorAtTail: true)
        cache[key] = icon
        return icon
    }

    static func cluster(count: Int, dark: Bool) -> Icon {
        let key = "cluster-\(count)-\(dark)"
        if let hit = cache[key] { return hit }
        let icon = render(ClusterBadge(count: count).padding(pad), dark: dark, anchorAtTail: false)
        cache[key] = icon
        return icon
    }

    static func userPin(emoji: String, dark: Bool) -> Icon {
        let key = "pin-\(emoji)-\(dark)"
        if let hit = cache[key] { return hit }
        let view = Text(emoji).font(.system(size: 22))
            .frame(width: 40, height: 40)
            .background(Theme.card).clipShape(Circle())
            .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
            .shadow(radius: 2)
            .padding(pad)
        let icon = render(view, dark: dark, anchorAtTail: false)
        cache[key] = icon
        return icon
    }

    private static func render<V: View>(_ view: V, dark: Bool, anchorAtTail: Bool) -> Icon {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = UIScreen.main.scale
        let image = renderer.uiImage ?? UIImage()
        let height = max(image.size.height, 1)
        // Кончик хвостика = низ вьюхи, но выше на величину запаса под тень.
        let anchorY = anchorAtTail ? (height - pad) / height : 0.5
        return Icon(image: image, anchor: CGPoint(x: 0.5, y: anchorY))
    }
}

// Заглушка вместо карты, пока не вписан ключ MapKit.
private final class MapKeyMissingView: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(Theme.bg2)
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = UIColor(Theme.text2)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.text = """
            Карта не подключена

            Впишите ключ MapKit Mobile SDK
            в файле MapConfig.swift
            """
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
