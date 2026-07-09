import CoreImage
import UIKit

/// 将启用的区域按所选样式渲染进图片，支持水平矩形与任意四边形（斜向文字）。
final class ImageRedactor {
    private let ciContext = CIContext(options: nil)

    private struct Target {
        let path: UIBezierPath
        /// path 的外接矩形（已裁剪到图内），像素化/模糊在此范围内计算
        let rect: CGRect
        let quad: Quad?
    }

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

        let targets: [Target] = regions.filter(\.isEnabled).compactMap { region in
            if let quad = region.quad?.expanded(by: 2) {
                let rect = quad.boundingRect.intersection(bounds)
                guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return nil }
                let path = UIBezierPath()
                path.move(to: quad.topLeft)
                path.addLine(to: quad.topRight)
                path.addLine(to: quad.bottomRight)
                path.addLine(to: quad.bottomLeft)
                path.close()
                return Target(path: path, rect: rect, quad: quad)
            }
            let rect = region.rect.insetBy(dx: -2, dy: -2).intersection(bounds)
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return nil }
            return Target(path: UIBezierPath(rect: rect), rect: rect, quad: nil)
        }

        guard !targets.isEmpty || watermark != nil else { return image }

        let sourceCI = CIImage(cgImage: cgImage)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: imageSize))

            for target in targets {
                switch style {
                case .solid:
                    solidColor.setFill()
                    target.path.fill()
                case .marker:
                    drawMarker(over: target, in: context.cgContext)
                case .hideText:
                    let color = averageEdgeColor(of: target.rect, source: sourceCI, imageSize: imageSize) ?? .white
                    color.setFill()
                    target.path.fill()
                case .pixelate, .blur:
                    guard let filtered = filteredCrop(source: sourceCI, rect: target.rect, imageHeight: imageSize.height, style: style) else { continue }
                    let cg = context.cgContext
                    cg.saveGState()
                    cg.addPath(target.path.cgPath)
                    cg.clip()
                    UIImage(cgImage: filtered).draw(in: target.rect)
                    cg.restoreGState()
                }
            }

            if let watermark {
                drawTiledWatermark(watermark, imageSize: imageSize, cgContext: context.cgContext)
            }
        }
    }

    /// 马克笔：沿区域中轴画一条圆头粗线，斜向区域自然跟随倾角。
    private func drawMarker(over target: Target, in cg: CGContext) {
        let start: CGPoint
        let end: CGPoint
        let width: CGFloat
        if let quad = target.quad {
            start = CGPoint(x: (quad.topLeft.x + quad.bottomLeft.x) / 2, y: (quad.topLeft.y + quad.bottomLeft.y) / 2)
            end = CGPoint(x: (quad.topRight.x + quad.bottomRight.x) / 2, y: (quad.topRight.y + quad.bottomRight.y) / 2)
            let leftHeight = hypot(quad.bottomLeft.x - quad.topLeft.x, quad.bottomLeft.y - quad.topLeft.y)
            let rightHeight = hypot(quad.bottomRight.x - quad.topRight.x, quad.bottomRight.y - quad.topRight.y)
            width = max((leftHeight + rightHeight) / 2, 4)
        } else {
            start = CGPoint(x: target.rect.minX, y: target.rect.midY)
            end = CGPoint(x: target.rect.maxX, y: target.rect.midY)
            width = max(target.rect.height, 4)
        }
        cg.saveGState()
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.92).cgColor)
        cg.setLineWidth(width)
        cg.setLineCap(.round)
        cg.move(to: start)
        cg.addLine(to: end)
        cg.strokePath()
        cg.restoreGState()
    }

    /// 对外接矩形区域做像素化/模糊，返回该区域的位图（由调用方按路径裁剪绘制）。
    private func filteredCrop(source: CIImage, rect: CGRect, imageHeight: CGFloat, style: RedactionStyle) -> CGImage? {
        let ciRect = ciRect(rect, imageHeight: imageHeight)
        let filter: CIFilter?
        switch style {
        case .pixelate:
            filter = CIFilter(name: "CIPixellate")
            // 像素块大小随区域尺寸自适应，保证小区域也被充分遮盖
            filter?.setValue(max(10, min(rect.width, rect.height) / 4), forKey: kCIInputScaleKey)
            filter?.setValue(CIVector(x: ciRect.midX, y: ciRect.midY), forKey: kCIInputCenterKey)
        case .blur:
            filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(max(12, min(rect.width, rect.height) / 5), forKey: kCIInputRadiusKey)
        default:
            filter = nil
        }
        guard let filter else { return nil }
        filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        guard let output = filter.outputImage?.cropped(to: ciRect) else { return nil }
        return ciContext.createCGImage(output, from: ciRect)
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

    /// 隐藏文字：取区域上边缘的平均色（通常是背景色）。
    private func averageEdgeColor(of rect: CGRect, source: CIImage, imageSize: CGSize) -> UIColor? {
        let band = CGRect(
            x: rect.minX,
            y: max(0, rect.minY - 3),
            width: rect.width,
            height: 2
        ).intersection(CGRect(origin: .zero, size: imageSize))
        guard !band.isNull, band.width >= 1, band.height >= 1 else { return nil }

        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciRect(band, imageHeight: imageSize.height)), forKey: kCIInputExtentKey)
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
