import SwiftUI
import MapKit

private let ALL_CATS: [PlaceCategory] = [.landmark, .park, .museum, .restaurant, .entertainment]
let BUDGET_ANY = 10000   // верх слайдера бюджета = «без лимита»

struct MapScreen: View {
    @State private var show18 = false
    @State private var ageAsk = false
    @State private var selected: Place?
    @State private var sheetExpanded = false
    @State private var activeCats: Set<PlaceCategory> = Set(ALL_CATS + [.nightlife])
    @State private var camera = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)))

    // Пользовательские метки
    @State private var pins: [MapPin] = []
    @State private var placing = false                 // режим постановки
    @State private var draftCoord: CLLocationCoordinate2D?
    @State private var draftKind = "crowd"
    @State private var draftNote = ""
    @State private var viewPin: MapPin?

    // Конструктор маршрута — точные значения, а не пресеты
    @State private var people = 2                 // человек
    @State private var hours = 4                  // часов на прогулку
    @State private var budget = BUDGET_ANY        // ₽ на человека; BUDGET_ANY = без лимита
    @State private var activeTags: Set<String> = []
    @State private var route: [Place] = []

    // Карта: текущий зум (для кластеризации), геолокация, режим списка
    @State private var mapSpan = MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
    @State private var listMode = false
    @StateObject private var loc = LocationManager()

    private var clusters: [PlaceCluster] { clusterPlaces(places, span: mapSpan) }

    // Топ-теги для доп. предпочтений (из данных мест)
    private let tagOpts = ["история", "архитектура", "прогулка", "природа",
                           "культура", "вид", "еда", "отдых", "шопинг", "искусство"]

    private var budgetMax: Int? { budget >= BUDGET_ANY ? nil : budget }

    // Места после фильтров категорий/18+ (для карты)
    private var places: [Place] {
        PLACES.filter { p in
            (show18 || p.category != .nightlife) && activeCats.contains(p.category)
        }
    }
    // + бюджет и тематика (для списка и маршрута)
    private var filteredPlaces: [Place] {
        places.filter { p in
            let okBudget = budgetMax == nil || p.price <= budgetMax!
            let okTags = activeTags.isEmpty || !activeTags.isDisjoint(with: Set(p.tags))
            return okBudget && okTags
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()   // точка пользователя

                    // Места: одиночные — пины с иконкой категории, слипшиеся — кластер
                    ForEach(clusters) { c in
                        Annotation("", coordinate: c.coordinate) {
                            if c.count == 1, let p = c.places.first {
                                Button { select(p) } label: {
                                    MapPinView(color: p.category.color, icon: p.categoryIcon,
                                               selected: selected?.id == p.id)
                                }
                            } else {
                                Button { zoomTo(c) } label: { ClusterBadge(count: c.count) }
                            }
                        }
                    }
                    // Пользовательские метки
                    ForEach(pins) { pin in
                        Annotation(pin.title, coordinate:
                            CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)) {
                            Button { viewPin = pin } label: {
                                Text(pin.emoji).font(.system(size: 22))
                                    .frame(width: 40, height: 40)
                                    .background(Theme.card).clipShape(Circle())
                                    .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    // Линия построенного маршрута
                    if route.count > 1 {
                        MapPolyline(coordinates: route.map {
                            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                        })
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                .ignoresSafeArea(edges: .top)
                .onMapCameraChange(frequency: .continuous) { ctx in mapSpan = ctx.region.span }
                // В режиме постановки — тап по карте ставит метку
                .onTapGesture { screenPt in
                    guard placing, let c = proxy.convert(screenPt, from: .local) else { return }
                    draftCoord = c
                    placing = false
                }
            }

            // 18+
            Button {
                if show18 { show18 = false } else { ageAsk = true }
            } label: {
                Text("18+")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(show18 ? .white : Theme.text)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(show18 ? Theme.nightlife : Theme.card)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .padding(.leading, 14).padding(.top, 8)

            // Кнопки справа: «Отметить» и «моя локация»
            VStack(alignment: .trailing, spacing: 10) {
                Button { placing.toggle(); sheetExpanded = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: placing ? "xmark" : "mappin.and.ellipse")
                        Text(placing ? "Отмена" : "Отметить").fontWeight(.semibold)
                    }
                    .font(.system(size: 15))
                    .foregroundColor(placing ? Theme.text : .white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(placing ? Theme.card : Theme.accent)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                Button { goToMyLocation() } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                        .frame(width: 44, height: 44)
                        .background(Theme.card).clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 14).padding(.top, 8)

            // Подсказка в режиме постановки
            if placing {
                Text("Нажмите на карте, где это происходит")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.accent).clipShape(Capsule())
                    .shadow(radius: 6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            }

            // Подложка в цвет шторки под плавающим таб-баром, чтобы вокруг
            // него не просвечивала карта. Отдельный слой снизу; на safe-area
            // шторки не влияет (у неё своя раскладка).
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Theme.bg.frame(height: 56)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)

            // Шторка снизу (Яндекс-стиль) — в свёрнутом виде только строка AI + фильтр.
            // peek = грабер(34) + строка AI/фильтр(46) + нижний отступ(14) = 94:
            // строка целиком над таб-баром, ничего лишнего не проглядывает.
            BottomSheet(expanded: $sheetExpanded, peekHeight: 94) {
                sheetContent
            }
        }
        .alert("Вам есть 18 лет?", isPresented: $ageAsk) {
            Button("Мне есть 18") { show18 = true }
            Button("Мне нет 18", role: .cancel) {}
        } message: {
            Text("Раздел показывает бары, клубы и кальянные — контент для взрослых.")
        }
        .onChange(of: sheetExpanded) { _, isOpen in
            if !isOpen { selected = nil }
        }
        .sheet(isPresented: Binding(get: { draftCoord != nil }, set: { if !$0 { draftCoord = nil } })) {
            pinDraftSheet
        }
        .sheet(item: $viewPin) { pin in pinViewSheet(pin) }
        .task { await loadPins() }
    }

    // Форма новой метки
    private var pinDraftSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Что здесь происходит?").font(.system(size: 20, weight: .heavy)).foregroundColor(Theme.text)
            HStack(spacing: 10) {
                pinKindButton("crowd", "👥", "Скопление")
                pinKindButton("meetup", "📣", "Сходка")
                pinKindButton("drift", "🏎️", "Дрифт")
            }
            TextField("", text: $draftNote, prompt: Text("Заметка (необязательно)").foregroundColor(Theme.text3), axis: .vertical)
                .foregroundColor(Theme.text).lineLimit(2...4)
                .padding(12).background(Theme.inputBg).clipShape(RoundedRectangle(cornerRadius: 12))
            Button { Task { await submitPin() } } label: {
                Text("Поставить метку").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Spacer()
        }
        .padding(20).background(Theme.bg)
        .presentationDetents([.height(300)])
    }

    private func pinKindButton(_ kind: String, _ emoji: String, _ label: String) -> some View {
        Button { draftKind = kind } label: {
            VStack(spacing: 4) {
                Text(emoji).font(.system(size: 26))
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(draftKind == kind ? Theme.accent.opacity(0.15) : Theme.bg2)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(draftKind == kind ? Theme.accent : Theme.border, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // Просмотр метки
    private func pinViewSheet(_ pin: MapPin) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(pin.emoji).font(.system(size: 30))
                VStack(alignment: .leading) {
                    Text(pin.title).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                    Text("\(pin.author?.name ?? "Аноним") · \(timeAgo(pin.createdAt))")
                        .font(.system(size: 13)).foregroundColor(Theme.text3)
                }
            }
            if !pin.note.isEmpty {
                Text(pin.note).font(.system(size: 15)).foregroundColor(Theme.text2)
            }
            if pin.mine {
                Button(role: .destructive) { Task { await removePin(pin) } } label: {
                    Text("Удалить метку").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Spacer()
        }
        .padding(20).background(Theme.bg)
        .presentationDetents([.height(pin.mine ? 240 : 180)])
    }

    private func loadPins() async {
        if let p = try? await API.shared.pins() { pins = p }
    }
    private func submitPin() async {
        guard let c = draftCoord else { return }
        if let pin = try? await API.shared.createPin(
            kind: draftKind, lat: c.latitude, lng: c.longitude, note: draftNote.trimmed) {
            pins.insert(pin, at: 0)
        }
        draftCoord = nil; draftNote = ""; draftKind = "crowd"
    }
    private func removePin(_ pin: MapPin) async {
        try? await API.shared.deletePin(id: pin.id)
        pins.removeAll { $0.id == pin.id }
        viewPin = nil
    }

    private let sheetAnim = Animation.spring(response: 0.4, dampingFraction: 0.85)

    @ViewBuilder private var sheetContent: some View {
        // Верх (peek): строка AI-помощника + фильтр — только они видны в свёрнутом виде
        HStack(spacing: 10) {
            Button { withAnimation(sheetAnim) { sheetExpanded = true } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundColor(Theme.accent).font(.system(size: 15))
                    Text("Спроси AI-помощника")
                        .font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text2)
                    Spacer()
                }
                .padding(.horizontal, 15).padding(.vertical, 12)
                .background(Theme.inputBg).clipShape(Capsule())
            }
            Button { withAnimation(sheetAnim) { sheetExpanded.toggle() } } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(sheetExpanded ? .white : Theme.text)
                    .frame(width: 46, height: 46)
                    .background(sheetExpanded ? Theme.accent : Theme.inputBg).clipShape(Circle())
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 14)

        if let place = selected {
            // Возврат к фильтрам/списку без сворачивания шторки
            HStack(spacing: 10) {
                Button { withAnimation(sheetAnim) { selected = nil } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                        Text("Назад").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.chip).clipShape(Capsule())
                }
                Spacer()
                Button { withAnimation(sheetAnim) { selected = nil; sheetExpanded = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.text2)
                        .frame(width: 34, height: 34).background(Theme.chip).clipShape(Circle())
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 10)

            PlaceDetail(
                place: place,
                inRoute: route.contains { $0.id == place.id },
                onAddToRoute: { p in
                    withAnimation(sheetAnim) {
                        if let i = route.firstIndex(where: { $0.id == p.id }) { route.remove(at: i) }
                        else { route.append(p) }
                    }
                },
                onOpenPlace: { p in select(p) }
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // В режиме списка фильтры скрыты — список занимает всю шторку
                    if !listMode {
                        aiIntro
                        paramsCard
                        prefsChips
                        tagChips
                        buildButton
                    }
                    resultsSection
                }
                .padding(.bottom, 24)
            }
        }
    }

    // Карточка AI-агента в раскрытом виде
    private var aiIntro: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [Theme.accent, Theme.nightlife],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("AI-помощник").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                Text("Опишите, что хотите, — подберу места и маршрут по Москве.")
                    .font(.system(size: 13)).foregroundColor(Theme.text2).lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.accent.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    // Карточка параметров: точное число людей, часов и бюджет
    private var paramsCard: some View {
        VStack(spacing: 0) {
            stepperRow(icon: "person.2.fill", tint: Color(hex: 0x3B82F6), title: "Компания",
                       value: "\(people) чел.",
                       minus: { if people > 1 { people -= 1; route = [] } },
                       plus: { if people < 20 { people += 1; route = [] } })
            divider
            stepperRow(icon: "clock.fill", tint: Color(hex: 0xF59E0B), title: "Время",
                       value: "\(hours) \(pluralHours(hours))",
                       minus: { if hours > 1 { hours -= 1; route = [] } },
                       plus: { if hours < 12 { hours += 1; route = [] } })
            divider
            // Бюджет — слайдер с точным значением
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    paramIcon("banknote.fill", Color(hex: 0x22C55E))
                    Text("Бюджет").font(.system(size: 15)).foregroundColor(Theme.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(budget >= BUDGET_ANY ? "Не важно" : "до \(budget) ₽")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
                Slider(value: Binding(get: { Double(budget) },
                                      set: { budget = Int($0 / 500) * 500; route = [] }),
                       in: 0...Double(BUDGET_ANY), step: 500)
                    .tint(Theme.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 56)
    }

    // Иконка параметра в мягком цветном контейнере (как в iOS Settings)
    private func paramIcon(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold)).foregroundColor(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func stepperRow(icon: String, tint: Color, title: String, value: String,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            paramIcon(icon, tint)
            Text(title).font(.system(size: 15)).foregroundColor(Theme.text).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                stepBtn("minus", minus)
                Text(value).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 62)
                stepBtn("plus", plus)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func stepBtn(_ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                .frame(width: 30, height: 30).background(Theme.chip).clipShape(Circle())
        }
    }

    // Предпочтения — категории мест (мультивыбор)
    private var prefsChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Куда пойти")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(show18 ? ALL_CATS + [.nightlife] : ALL_CATS, id: \.self) { cat in
                        let on = activeCats.contains(cat)
                        Button {
                            if on { activeCats.remove(cat) } else { activeCats.insert(cat) }
                            route = []
                        } label: {
                            HStack(spacing: 7) {
                                // Явный selected: галочка + заливка + обводка цветом типа
                                if on {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                                } else {
                                    Circle().fill(cat.color).frame(width: 9, height: 9)
                                }
                                Text(shortLabel(cat)).font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(on ? .white : Theme.text)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(on ? cat.color : Theme.chip)
                            .overlay(Capsule().stroke(on ? .white.opacity(0.35) : cat.color.opacity(0.55),
                                                      lineWidth: on ? 1.5 : 1.2))
                            .clipShape(Capsule())
                        }
                    }
                }.padding(.horizontal, 16)
            }
        }
    }

    // Тематика — теги мест (мультивыбор)
    private var tagChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Что интересно")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tagOpts, id: \.self) { tag in
                        let on = activeTags.contains(tag)
                        Button {
                            if on { activeTags.remove(tag) } else { activeTags.insert(tag) }
                            route = []
                        } label: {
                            Text(tag.capitalized).font(.system(size: 14, weight: .semibold))
                                .foregroundColor(on ? .white : Theme.text)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(on ? Theme.accent : Theme.chip)
                                .clipShape(Capsule())
                        }
                    }
                }.padding(.horizontal, 16)
            }
        }
    }

    // Переключатель карта / список
    private var mapListToggle: some View {
        HStack(spacing: 0) {
            toggleBtn("Карта", "map.fill", active: !listMode) {
                withAnimation(sheetAnim) { listMode = false; sheetExpanded = false }
            }
            toggleBtn("Список", "list.bullet", active: listMode) {
                withAnimation(sheetAnim) { listMode = true; sheetExpanded = true }
            }
        }
        .padding(3).background(Theme.chip).clipShape(Capsule())
    }

    private func toggleBtn(_ title: String, _ icon: String, active: Bool,
                           _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(active ? .white : Theme.text2)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(active ? Theme.accent : Color.clear)
            .clipShape(Capsule())
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
            .padding(.horizontal, 16)
    }

    private var buildButton: some View {
        Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { buildRoute() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                Text(route.isEmpty ? "Построить маршрут" : "Обновить маршрут").fontWeight(.bold)
            }
            .font(.system(size: 16)).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var resultsSection: some View {
        if route.isEmpty {
            // Заголовок результатов — тапабельный, + переключатель карта/список
            HStack {
                Button {
                    withAnimation(sheetAnim) { listMode = true; sheetExpanded = true }
                } label: {
                    HStack(spacing: 6) {
                        Text("Места · \(filteredPlaces.count)")
                            .font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            .foregroundColor(Theme.text3)
                    }
                }
                Spacer()
                mapListToggle
            }
            .padding(.horizontal, 16)

            if filteredPlaces.isEmpty {
                Text("Под фильтры ничего не нашлось").foregroundColor(Theme.text3)
                    .font(.system(size: 14)).padding(.horizontal, 16).padding(.top, 8)
            }
            LazyVStack(spacing: 0) {
                ForEach(filteredPlaces) { place in
                    Button { select(place) } label: { listRow(place) }
                    Divider().overlay(Theme.border).padding(.leading, 16)
                }
            }
        } else {
            HStack {
                Text("Ваш маршрут · \(route.count)").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                Button("Сбросить") { withAnimation { route = [] } }
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.accent)
            }.padding(.horizontal, 16)
            LazyVStack(spacing: 0) {
                ForEach(Array(route.enumerated()), id: \.element.id) { idx, place in
                    Button { select(place) } label: { routeRow(idx + 1, place) }
                    Divider().overlay(Theme.border).padding(.leading, 54)
                }
            }
        }
    }

    private func routeRow(_ n: Int, _ place: Place) -> some View {
        HStack(spacing: 12) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                .frame(width: 26, height: 26).background(place.category.color).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                Text(place.category.label).font(.system(size: 13)).foregroundColor(Theme.text3)
            }
            Spacer()
            Text("★ \(place.rating, specifier: "%.1f")")
                .font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: 0xE8A33D))
        }
        .padding(.horizontal, 16).padding(.vertical, 11).contentShape(Rectangle())
    }

    // Призум по тапу на кластер
    private func zoomTo(_ c: PlaceCluster) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            camera = .region(regionFor(c.places))
        }
    }

    // Центрирование на пользователе (спросим разрешение при первом тапе)
    private func goToMyLocation() {
        loc.request()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            camera = .userLocation(fallback: .region(
                MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
                                   span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))))
        }
    }

    private func buildRoute() {
        // Примерно 1.5 часа на место, минимум 2 точки
        let n = max(2, Int((Double(hours) / 1.5).rounded()))
        route = Array(filteredPlaces.sorted { $0.rating > $1.rating }.prefix(n))
        guard route.count > 0 else { return }
        let lats = route.map { $0.lat }, lngs = route.map { $0.lng }
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.04, (lats.max()! - lats.min()!) * 1.5),
                                    longitudeDelta: max(0.04, (lngs.max()! - lngs.min()!) * 1.5))
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func listRow(_ place: Place) -> some View {
        HStack(spacing: 12) {
            Circle().fill(place.category.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                Text(place.category.label).font(.system(size: 13)).foregroundColor(Theme.text3)
            }
            Spacer()
            Text("★ \(place.rating, specifier: "%.1f")")
                .font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: 0xE8A33D))
        }
        .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
    }

    private func select(_ place: Place) {
        selected = place
        sheetExpanded = true
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
        }
    }

    private func shortLabel(_ c: PlaceCategory) -> String {
        switch c {
        case .landmark: return "Достопримечательности"
        case .park: return "Парки"
        case .museum: return "Музеи"
        case .restaurant: return "Рестораны"
        case .entertainment: return "Развлечения"
        case .nightlife: return "18+"
        }
    }
}

// Карточка места внутри шторки.
struct PlaceDetail: View {
    let place: Place
    var inRoute: Bool = false
    var onAddToRoute: (Place) -> Void = { _ in }
    var onOpenPlace: (Place) -> Void = { _ in }

    @EnvironmentObject var gam: Gamification
    @State private var booking = false
    // Бронируемые категории: рестораны, ночные заведения, развлечения
    private var bookable: Bool { [.restaurant, .nightlife, .entertainment].contains(place.category) }

    // 3 ближайших места (по координатам) — блок «Рядом»
    private var nearby: [Place] {
        PLACES.filter { $0.id != place.id }
            .sorted {
                let d1 = pow($0.lat - place.lat, 2) + pow($0.lng - place.lng, 2)
                let d2 = pow($1.lat - place.lat, 2) + pow($1.lng - place.lng, 2)
                return d1 < d2
            }
            .prefix(3).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Галерея фотографий
                PhotoCarousel(photos: place.photos, height: 190, corner: 16,
                              tint: place.category.color, icon: place.categoryIcon)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(place.category.color).frame(width: 10, height: 10)
                        Text(place.category.label).font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.text2)
                        Spacer()
                        // Рейтинг с числом оценок
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.system(size: 12))
                            Text("\(place.rating, specifier: "%.1f")").font(.system(size: 14, weight: .bold))
                            Text("(\(place.ratingCount))").font(.system(size: 13)).foregroundColor(Theme.text3)
                        }
                        .foregroundColor(Color(hex: 0xE8A33D))
                    }
                    Text(place.name).font(.system(size: 22, weight: .heavy)).foregroundColor(Theme.text)
                    Text(place.address).font(.system(size: 14)).foregroundColor(Theme.text3)
                    Text(place.description).font(.system(size: 15)).foregroundColor(Theme.text2)
                        .lineSpacing(4).padding(.top, 6)

                    // Мета: цена · длительность · часы работы
                    HStack(spacing: 16) {
                        Label(place.price == 0 ? "Бесплатно" : "от \(place.price) ₽", systemImage: "banknote")
                        Label("~\(place.duration / 60) ч", systemImage: "clock")
                        Label(place.hoursText, systemImage: place.isOpenNow ? "door.left.hand.open" : "door.left.hand.closed")
                            .foregroundColor(place.isOpenNow ? Color(hex: 0x22C55E) : Theme.text3)
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    .padding(.top, 8)

                    // CTA: основное действие + вторичное
                    VStack(spacing: 10) {
                        Button { onAddToRoute(place) } label: {
                            Label(inRoute ? "В маршруте" : "Добавить в маршрут",
                                  systemImage: inRoute ? "checkmark" : "plus")
                                .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button { withAnimation { gam.toggleVisit(place.id) } } label: {
                            let done = gam.isVisited(place.id)
                            Label(done ? "Вы были здесь" : "Я был здесь",
                                  systemImage: done ? "checkmark.circle.fill" : "mappin.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(done ? Theme.accent : Theme.text)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(done ? Theme.accent : Theme.border, lineWidth: 1.5))
                        }
                        if bookable {
                            Button { booking = true } label: {
                                Label("Забронировать стол", systemImage: "calendar.badge.plus")
                                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1.5))
                            }
                        }
                    }
                    .padding(.top, 14)
                }
                .padding(16)

                // Рядом
                if !nearby.isEmpty {
                    Text("Рядом").font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text)
                        .padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(nearby) { p in
                                Button { onOpenPlace(p) } label: { nearbyCard(p) }
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 10)
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .sheet(isPresented: $booking) { BookingSheet(place: place) }
    }

    private func nearbyCard(_ p: Place) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoCarousel(photos: Array(p.photos.prefix(1)), height: 84, corner: 12,
                          tint: p.category.color, icon: p.categoryIcon, allowsFullscreen: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle().fill(p.category.color).frame(width: 7, height: 7)
                    Text(p.category.label).font(.system(size: 11)).foregroundColor(Theme.text3).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
        }
        .frame(width: 156)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// Бронирование места: дата, время, число гостей → заявка.
struct BookingSheet: View {
    let place: Place
    @Environment(\.dismiss) var dismiss
    @State private var date = Date()
    @State private var guests = 2
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if sent {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundColor(Theme.accent)
                            Text("Заявка отправлена!").font(.system(size: 20, weight: .heavy)).foregroundColor(Theme.text)
                            Text("«\(place.name)» свяжется с вами для подтверждения брони.")
                                .font(.system(size: 15)).foregroundColor(Theme.text2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        Text(place.name).font(.system(size: 22, weight: .heavy)).foregroundColor(Theme.text)
                        Text(place.address).font(.system(size: 14)).foregroundColor(Theme.text3)

                        label("ДАТА И ВРЕМЯ")
                        DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact).labelsHidden().tint(Theme.accent)

                        label("ГОСТЕЙ")
                        Stepper(value: $guests, in: 1...20) {
                            Text("\(guests) чел.").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                        }

                        Button { withAnimation { sent = true } } label: {
                            Text("Отправить заявку").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 14))
                        }.padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Бронирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(sent ? "Готово" : "Закрыть") { dismiss() }.tint(Theme.accent) } }
        }
        .presentationDetents([.medium, .large])
    }
    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text3).kerning(0.6)
    }
}

// Склонения для точных значений фильтров.
func pluralPeople(_ n: Int) -> String {
    let a = n % 100, b = n % 10
    if a >= 11 && a <= 14 { return "человек" }
    if b == 1 { return "человек" }
    if b >= 2 && b <= 4 { return "человека" }
    return "человек"
}
func pluralHours(_ n: Int) -> String {
    let a = n % 100, b = n % 10
    if a >= 11 && a <= 14 { return "часов" }
    if b == 1 { return "час" }
    if b >= 2 && b <= 4 { return "часа" }
    return "часов"
}
