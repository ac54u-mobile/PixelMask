import SwiftUI

enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png

    var id: String { rawValue }
    var title: String { self == .jpeg ? "JPEG" : "PNG" }
}

@MainActor
final class EditorState: ObservableObject {
    @Published var image: UIImage?
    /// 实时打码预览图，区域/样式变化后自动刷新
    @Published var previewImage: UIImage?
    @Published var regions: [RedactionRegion] = []
    @Published var textLines: [TextLine] = []
    @Published var isDetecting = false
    @Published var detectionFailed = false

    @Published var style: RedactionStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: "defaultStyle")
            schedulePreview()
        }
    }
    @Published var solidColor: Color = Color(red: 0.18, green: 0.78, blue: 0.4) {
        didSet { schedulePreview() }
    }

    /// 关闭的检测类别（不参与自动识别）
    @Published var disabledKinds: Set<DetectionKind> {
        didSet {
            UserDefaults.standard.set(disabledKinds.map(\.rawValue), forKey: "disabledKinds")
        }
    }

    @Published var watermarkEnabled: Bool {
        didSet {
            UserDefaults.standard.set(watermarkEnabled, forKey: "watermarkEnabled")
            schedulePreview()
        }
    }
    @Published var watermarkText: String {
        didSet {
            UserDefaults.standard.set(watermarkText, forKey: "watermarkText")
            schedulePreview()
        }
    }

    @Published var exportFormat: ExportFormat {
        didSet { UserDefaults.standard.set(exportFormat.rawValue, forKey: "exportFormat") }
    }
    @Published var jpegQuality: Double {
        didSet { UserDefaults.standard.set(jpegQuality, forKey: "jpegQuality") }
    }

    private var undoStack: [[RedactionRegion]] = []
    private var redoStack: [[RedactionRegion]] = []

    private let engine = DetectionEngine()
    private let redactor = ImageRedactor()
    private var renderGeneration = 0

    init() {
        let defaults = UserDefaults.standard
        style = RedactionStyle(rawValue: defaults.string(forKey: "defaultStyle") ?? "") ?? .pixelate
        disabledKinds = Set(
            (defaults.stringArray(forKey: "disabledKinds") ?? []).compactMap(DetectionKind.init)
        )
        watermarkEnabled = defaults.bool(forKey: "watermarkEnabled")
        watermarkText = defaults.string(forKey: "watermarkText") ?? "仅供验证使用"
        exportFormat = ExportFormat(rawValue: defaults.string(forKey: "exportFormat") ?? "") ?? .jpeg
        let storedQuality = defaults.double(forKey: "jpegQuality")
        jpegQuality = storedQuality > 0 ? storedQuality : 0.92
    }

    var enabledCount: Int { regions.filter(\.isEnabled).count }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    private var activeWatermark: String? {
        let text = watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        return watermarkEnabled && !text.isEmpty ? text : nil
    }

    func load(image: UIImage) {
        // 统一转为 orientation up、scale 1 的图，后续所有坐标基于其像素尺寸
        let normalized = Self.normalized(image)
        self.image = normalized
        previewImage = normalized
        regions = []
        textLines = []
        undoStack = []
        redoStack = []
        detect()
    }

    func detect() {
        guard let image else { return }
        isDetecting = true
        detectionFailed = false
        let disabled = disabledKinds
        Task {
            do {
                let output = try await engine.detect(in: image, disabledKinds: disabled)
                self.regions = output.sensitiveRegions
                self.textLines = output.textLines
            } catch {
                self.detectionFailed = true
            }
            self.isDetecting = false
            self.undoStack = []
            self.redoStack = []
            self.schedulePreview()
        }
    }

    // MARK: - 区域编辑（均支持撤销）

    /// 点按：优先切换已有区域，否则命中文字行则整行打码。
    func handleTap(at imagePoint: CGPoint) {
        if let index = regions.lastIndex(where: { $0.rect.insetBy(dx: -8, dy: -8).contains(imagePoint) }) {
            snapshot()
            regions[index].isEnabled.toggle()
            schedulePreview()
            return
        }
        if let line = textLines.first(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(imagePoint) }) {
            snapshot()
            regions.append(RedactionRegion(rect: line.rect, quad: line.quad, kind: .textLine, text: line.text))
            schedulePreview()
        }
    }

    func addManualRegion(_ imageRect: CGRect) {
        guard let image else { return }
        let bounds = CGRect(origin: .zero, size: image.size)
        let clamped = imageRect.standardized.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 4, clamped.height >= 4 else { return }
        snapshot()
        regions.append(RedactionRegion(rect: clamped, kind: .manual))
        schedulePreview()
    }

    func enableAll() {
        guard regions.contains(where: { !$0.isEnabled }) else { return }
        snapshot()
        for index in regions.indices {
            regions[index].isEnabled = true
        }
        schedulePreview()
    }

    func disableAll() {
        guard regions.contains(where: \.isEnabled) else { return }
        snapshot()
        for index in regions.indices {
            regions[index].isEnabled = false
        }
        schedulePreview()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(regions)
        regions = previous
        schedulePreview()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(regions)
        regions = next
        schedulePreview()
    }

    private func snapshot() {
        undoStack.append(regions)
        redoStack.removeAll()
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    // MARK: - 渲染

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
        let watermark = activeWatermark
        let redactor = redactor

        Task.detached(priority: .userInitiated) {
            let rendered = redactor.render(
                image: image,
                regions: regions,
                style: style,
                solidColor: color,
                watermark: watermark
            )
            await MainActor.run {
                guard self.renderGeneration == generation else { return }
                self.previewImage = rendered
            }
        }
    }

    /// 按导出设置编码，供分享使用。
    func exportData() -> (data: Data, fileExtension: String)? {
        guard let result = renderResult() else { return nil }
        switch exportFormat {
        case .png:
            return result.pngData().map { ($0, "png") }
        case .jpeg:
            return result.jpegData(compressionQuality: jpegQuality).map { ($0, "jpg") }
        }
    }

    /// 导出最终图片。通过重绘导出，EXIF/GPS 等元数据不会保留。
    func renderResult() -> UIImage? {
        guard let image else { return nil }
        return redactor.render(
            image: image,
            regions: regions,
            style: style,
            solidColor: UIColor(solidColor),
            watermark: activeWatermark
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
