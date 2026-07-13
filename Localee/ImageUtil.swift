import UIKit

// Сжимает картинку и кодирует в data-URL (как хранит сайт: "data:image/jpeg;base64,...").
func imageToDataURL(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat = 0.8) -> String? {
    let longest = max(image.size.width, image.size.height)
    let scale = longest > maxDimension ? maxDimension / longest : 1
    let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
    return "data:image/jpeg;base64," + data.base64EncodedString()
}
