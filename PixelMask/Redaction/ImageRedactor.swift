import CoreImage
import UIKit

/// 将启用的区域按所选样式渲染进图片。
final class ImageRedactor {
    private let ciContext = CIContext(options: nil)

    func render(
        image: UIImage,
        regions: [RedactionRegion],
        style: RedactionStyle,
        solidColor: UIColor,
        watermark: String? = nil
    ) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let bounds = CGRect(origin: .zero, size: imageSize)

        let activeRects = regions
            .filter(\.isEnabled)
            .map { $0.rect.insetBy(dx: -2, dy: -2).intersection(bounds) }
            .filter { !$0.isNull && $0.width >= 1 && $0.height >= 1 }

        guard !activeRects.isEmpty || watermark != nil else { return image }

        var output = CIImage(cgImage: cgImage)

        switch style {
        case .pixelate:
            for rect in activeRects {
                output = pixelate(output, in: ciRect(rect, imageHeight: imageSize.height))
            }
        case .blur:
            for rect in activeRects {
                output = blur(output, in: ciRect(rect, imageHeight: imageSize.height))
            }
        case .solid, .marker, .hideText:
            break
        }

        guard let filtered = ciContext.createCGImage(output, from: CGRect(origin: .zero, size: imageSize)) else {
            return image
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            UIImage(cgImage: filtered).draw(in: CGRect(origin: .zero, size: imageSize))

            switch style {
            case .solid:
                solidColor.setFill()
                for rect in activeRects {
                    context.fill(rect)
                }
            case .marker:
                for rect in activeRects {
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
                    UIColor.black.withAlphaComponent(0.92).setFill()
                    path.fill()
                }
            case .hideText:
                for rect in activeRects {
                    hideText(rect: rect, cgImage: filtered, imageSize: imageSize, context: context)
                }
            case .pixelate, .blur:
                break
            }

            if let watermark {
                drawTiledWatermark(watermark, imageSize: imageSize, cgContext: context.cgContext)
            }
        }
    }

    /// 斜向平铺的半透明文字水印。
    private func drawTiledWatermark(_ text: String, imageSize: CGSize, cgContext: CGContext) {
        let fontSize = max(20, min(imageSize.width, imageSize.height) / 18)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.30),
        ]
        let shadowAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.black.withAlphaComponent(0.18),
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let stepX = textSize.width + fontSize * 3
        let stepY = textSize.height + fontSize * 3.5

        cgContext.saveGState()
        cgContext.translateBy(x: imageSize.width / 2, y: imageSize.height / 2)
        cgContext.rotate(by: -.pi / 6)

        // 旋转后需要覆盖对角线范围
        let radius = hypot(imageSize.width, imageSize.height) / 2 + max(stepX, stepY)
        var y = -radius
        var rowIndex = 0
        while y < radius {
            // 隔行错位，避免整齐网格
            var x = -radius + (rowIndex % 2 == 0 ? 0 : stepX / 2)
            while x < radius {
                let point = CGPoint(x: x, y: y)
                (text as NSString).draw(at: CGPoint(x: point.x + 1, y: point.y + 1), withAttributes: shadowAttributes)
                (text as NSString).draw(at: point, withAttributes: attributes)
                x += stepX
            }
            y += stepY
            rowIndex += 1
        }
        cgContext.restoreGState()
    }

    private func pixelate(_ image: CIImage, in rect: CGRect) -> CIImage {
        // 像素块大小随区域尺寸自适应，保证小区域也被充分遮盖
        let scale = max(10, min(rect.width, rect.height) / 4)
        guard let filter = CIFilter(name: "CIPixellate") else { return image }
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: rect.midX, y: rect.midY), forKey: kCIInputCenterKey)
        guard let result = filter.outputImage?.cropped(to: rect) else { return image }
        return result.composited(over: image)
    }

    private func blur(_ image: CIImage, in rect: CGRect) -> CIImage {
        let radius = max(12, min(rect.width, rect.height) / 5)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let result = filter.outputImage?.cropped(to: rect) else { return image }
        return result.composited(over: image)
    }

    /// 隐藏文字：取区域边缘的平均色填充，适合近纯色背景。
    private func hideText(rect: CGRect, cgImage: CGImage, imageSize: CGSize, context: UIGraphicsImageRendererContext) {
        let color = averageEdgeColor(of: rect, cgImage: cgImage, imageSize: imageSize) ?? .white
        color.setFill()
        context.fill(rect.insetBy(dx: -1, dy: -1))
    }

    private func averageEdgeColor(of rect: CGRect, cgImage: CGImage, imageSize: CGSize) -> UIColor? {
        // 在区域上方取一条细带求平均色（上边缘通常是背景）
        let band = CGRect(
            x: rect.minX,
            y: max(0, rect.minY - 3),
            width: rect.width,
            height: 2
        ).intersection(CGRect(origin: .zero, size: imageSize))
        guard !band.isNull, band.width >= 1, band.height >= 1 else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let ciBand = ciRect(band, imageHeight: imageSize.height)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciBand), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    /// UIKit 坐标（原点左上）转 CoreImage 坐标（原点左下）。
    private func ciRect(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: imageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
