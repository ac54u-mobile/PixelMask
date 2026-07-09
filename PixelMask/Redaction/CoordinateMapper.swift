import CoreGraphics

/// 图片像素坐标与 aspect-fit 显示容器坐标的互转。
enum CoordinateMapper {

    static func fittedImageFrame(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func toView(_ point: CGPoint, imageSize: CGSize, containerSize: CGSize) -> CGPoint {
        let frame = fittedImageFrame(imageSize: imageSize, containerSize: containerSize)
        guard frame.width > 0 else { return .zero }
        let scale = frame.width / imageSize.width
        return CGPoint(
            x: frame.minX + point.x * scale,
            y: frame.minY + point.y * scale
        )
    }

    static func toView(_ rect: CGRect, imageSize: CGSize, containerSize: CGSize) -> CGRect {
        let frame = fittedImageFrame(imageSize: imageSize, containerSize: containerSize)
        guard frame.width > 0 else { return .zero }
        let scale = frame.width / imageSize.width
        return CGRect(
            x: frame.minX + rect.minX * scale,
            y: frame.minY + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    static func toImage(_ point: CGPoint, imageSize: CGSize, containerSize: CGSize) -> CGPoint {
        let frame = fittedImageFrame(imageSize: imageSize, containerSize: containerSize)
        guard frame.width > 0 else { return .zero }
        let scale = imageSize.width / frame.width
        return CGPoint(
            x: (point.x - frame.minX) * scale,
            y: (point.y - frame.minY) * scale
        )
    }

    static func toImage(_ rect: CGRect, imageSize: CGSize, containerSize: CGSize) -> CGRect {
        let origin = toImage(rect.origin, imageSize: imageSize, containerSize: containerSize)
        let frame = fittedImageFrame(imageSize: imageSize, containerSize: containerSize)
        guard frame.width > 0 else { return .zero }
        let scale = imageSize.width / frame.width
        return CGRect(x: origin.x, y: origin.y, width: rect.width * scale, height: rect.height * scale)
    }
}
