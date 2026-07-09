import SwiftUI

@MainActor
final class EditorState: ObservableObject {
    @Published var image: UIImage?
    @Published var regions: [RedactionRegion] = []
    @Published var textLines: [TextLine] = []
    @Published var style: RedactionStyle = .pixelate
    @Published var solidColor: Color = Color(red: 0.18, green: 0.78, blue: 0.4)
    @Published var isDetecting = false
    @Published var detectionFailed = false

    private let engine = DetectionEngine()
    private let redactor = ImageRedactor()

    var enabledCount: Int { regions.filter(\.isEnabled).count }

    func load(image: UIImage) {
        // 统一转为 orientation up、scale 1 的图，后续所有坐标基于其像素尺寸
        let normalized = Self.normalized(image)
        self.image = normalized
        regions = []
        textLines = []
        detect()
    }

    func detect() {
        guard let image else { return }
        isDetecting = true
        detectionFailed = false
        Task {
            do {
                let output = try await engine.detect(in: image)
                self.regions = output.sensitiveRegions
                self.textLines = output.textLines
            } catch {
                self.detectionFailed = true
            }
            self.isDetecting = false
        }
    }

    /// 点按：优先切换已有区域，否则命中文字行则整行打码。
    func handleTap(at imagePoint: CGPoint) {
        if let index = regions.lastIndex(where: { $0.rect.insetBy(dx: -8, dy: -8).contains(imagePoint) }) {
            regions[index].isEnabled.toggle()
            return
        }
        if let line = textLines.first(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(imagePoint) }) {
            regions.append(RedactionRegion(rect: line.rect, kind: .textLine, text: line.text))
        }
    }

    func addManualRegion(_ imageRect: CGRect) {
        guard let image else { return }
        let bounds = CGRect(origin: .zero, size: image.size)
        let clamped = imageRect.standardized.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 4, clamped.height >= 4 else { return }
        regions.append(RedactionRegion(rect: clamped, kind: .manual))
    }

    func removeRegion(id: UUID) {
        regions.removeAll { $0.id == id }
    }

    /// 渲染最终图片。通过重绘导出，EXIF/GPS 等元数据不会保留。
    func renderResult() -> UIImage? {
        guard let image else { return nil }
        return redactor.render(
            image: image,
            regions: regions,
            style: style,
            solidColor: UIColor(solidColor)
        )
    }

    private static func normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.scale == 1 {
            return image
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
