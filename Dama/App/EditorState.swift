import SwiftUI

@MainActor
final class EditorState: ObservableObject {
    @Published var image: UIImage?
    /// 实时打码预览图，区域/样式变化后自动刷新
    @Published var previewImage: UIImage?
    @Published var regions: [RedactionRegion] = []
    @Published var textLines: [TextLine] = []
    @Published var style: RedactionStyle = .pixelate {
        didSet { schedulePreview() }
    }
    @Published var solidColor: Color = Color(red: 0.18, green: 0.78, blue: 0.4) {
        didSet { schedulePreview() }
    }
    @Published var isDetecting = false
    @Published var detectionFailed = false

    private let engine = DetectionEngine()
    private let redactor = ImageRedactor()
    private var renderGeneration = 0

    var enabledCount: Int { regions.filter(\.isEnabled).count }

    func load(image: UIImage) {
        // 统一转为 orientation up、scale 1 的图，后续所有坐标基于其像素尺寸
        let normalized = Self.normalized(image)
        self.image = normalized
        previewImage = normalized
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
            self.schedulePreview()
        }
    }

    /// 点按：优先切换已有区域，否则命中文字行则整行打码。
    func handleTap(at imagePoint: CGPoint) {
        if let index = regions.lastIndex(where: { $0.rect.insetBy(dx: -8, dy: -8).contains(imagePoint) }) {
            regions[index].isEnabled.toggle()
            schedulePreview()
            return
        }
        if let line = textLines.first(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(imagePoint) }) {
            regions.append(RedactionRegion(rect: line.rect, kind: .textLine, text: line.text))
            schedulePreview()
        }
    }

    func addManualRegion(_ imageRect: CGRect) {
        guard let image else { return }
        let bounds = CGRect(origin: .zero, size: image.size)
        let clamped = imageRect.standardized.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 4, clamped.height >= 4 else { return }
        regions.append(RedactionRegion(rect: clamped, kind: .manual))
        schedulePreview()
    }

    func removeRegion(id: UUID) {
        regions.removeAll { $0.id == id }
        schedulePreview()
    }

    /// 后台渲染预览，只采纳最新一次结果，避免连续点按时旧渲染覆盖新渲染。
    private func schedulePreview() {
        guard let image else {
            previewImage = nil
            return
        }
        renderGeneration += 1
        let generation = renderGeneration
        let regions = regions
        let style = style
        let color = UIColor(solidColor)
        let redactor = redactor

        Task.detached(priority: .userInitiated) {
            let rendered = redactor.render(image: image, regions: regions, style: style, solidColor: color)
            await MainActor.run {
                guard self.renderGeneration == generation else { return }
                self.previewImage = rendered
            }
        }
    }

    /// 导出最终图片。通过重绘导出，EXIF/GPS 等元数据不会保留。
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
