import SwiftUI

// Внешний вид объектов на карте. Сами вьюхи Яндекс SDK не принимает — он умеет
// только UIImage, поэтому YandexMap.swift растеризует их через ImageRenderer.

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

// Здесь раньше жили ручная кластеризация (clusterPlaces/regionFor) и
// LocationManager. После перехода на Яндекс.Карты всё это делает сам SDK —
// см. YandexMap.swift: clusterPlacemarks склеивает точки, cameraPositionWithGeometry
// подбирает зум, а разрешение на геопозицию запрашивает координатор карты.
