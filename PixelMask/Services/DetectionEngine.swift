import UIKit
import Vision

struct DetectionOutput {
    /// 自动识别出的敏感区域（默认开启打码）
    var sensitiveRegions: [RedactionRegion]
    /// 全部文字行（供“点哪打哪”整行打码使用）
    var textLines: [TextLine]
}

struct TextLine: Identifiable {
    let id = UUID()
    let text: String
    let rect: CGRect
}

/// 端上检测引擎：Vision OCR + 人脸 + 二维码 + 规则分类，全程离线。
final class DetectionEngine {

    func detect(
        in image: UIImage,
        disabledKinds: Set<DetectionKind> = []
    ) async throws -> DetectionOutput {
        guard let cgImage = normalizedCGImage(from: image) else {
            return DetectionOutput(sensitiveRegions: [], textLines: [])
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        textRequest.usesLanguageCorrection = true

        let faceRequest = VNDetectFaceRectanglesRequest()
        let barcodeRequest = VNDetectBarcodesRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([textRequest, faceRequest, barcodeRequest])

        var regions: [RedactionRegion] = []
        var textLines: [TextLine] = []

        for observation in textRequest.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let lineRect = imageRect(from: observation.boundingBox, imageSize: imageSize)
            textLines.append(TextLine(text: text, rect: lineRect))

            for match in SensitiveTextClassifier.matches(in: text) {
                guard !disabledKinds.contains(match.kind) else { continue }
                let rect: CGRect
                if let box = try? candidate.boundingBox(for: match.range) {
                    rect = imageRect(from: box.boundingBox, imageSize: imageSize)
                } else {
                    rect = lineRect
                }
                let matchedText = String(text[match.range])
                regions.append(RedactionRegion(rect: rect, kind: match.kind, text: matchedText))
            }
        }

        if !disabledKinds.contains(.face) {
            for observation in faceRequest.results ?? [] {
                let rect = imageRect(from: observation.boundingBox, imageSize: imageSize)
                regions.append(RedactionRegion(rect: rect, kind: .face))
            }
        }

        if !disabledKinds.contains(.qrCode) {
            for observation in barcodeRequest.results ?? [] {
                let rect = imageRect(from: observation.boundingBox, imageSize: imageSize)
                regions.append(RedactionRegion(rect: rect, kind: .qrCode))
            }
        }

        return DetectionOutput(sensitiveRegions: regions, textLines: textLines)
    }

    /// Vision 归一化坐标（原点左下）转为图片像素坐标（原点左上）。
    private func imageRect(from normalized: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * imageSize.width,
            y: (1 - normalized.maxY) * imageSize.height,
            width: normalized.width * imageSize.width,
            height: normalized.height * imageSize.height
        )
    }

    /// 修正 EXIF 方向，输出像素坐标系与显示一致的 CGImage。
    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return rendered.cgImage
    }
}
