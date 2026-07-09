import CoreGraphics
import Foundation

enum DetectionKind: String {
    case phone
    case email
    case idNumber
    case longNumber
    case ipAddress
    case carPlate
    case personName
    case placeName
    case face
    case qrCode
    case textLine
    case manual

    var label: String {
        switch self {
        case .phone: return "电话"
        case .email: return "邮箱"
        case .idNumber: return "证件号"
        case .longNumber: return "长数字"
        case .ipAddress: return "IP地址"
        case .carPlate: return "车牌"
        case .personName: return "姓名"
        case .placeName: return "地名/机构"
        case .face: return "人脸"
        case .qrCode: return "二维码"
        case .textLine: return "文字"
        case .manual: return "手动"
        }
    }
}

/// 任意四边形区域（图片像素坐标），用于斜向文字/二维码的精确打码。
struct Quad: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    var boundingRect: CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    init(rect: CGRect) {
        topLeft = CGPoint(x: rect.minX, y: rect.minY)
        topRight = CGPoint(x: rect.maxX, y: rect.minY)
        bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
    }

    /// 绕重心旋转。
    func rotated(by angle: CGFloat) -> Quad {
        let cx = points.map(\.x).reduce(0, +) / 4
        let cy = points.map(\.y).reduce(0, +) / 4
        func rotate(_ p: CGPoint) -> CGPoint {
            let dx = p.x - cx
            let dy = p.y - cy
            return CGPoint(
                x: cx + dx * cos(angle) - dy * sin(angle),
                y: cy + dx * sin(angle) + dy * cos(angle)
            )
        }
        return Quad(
            topLeft: rotate(topLeft),
            topRight: rotate(topRight),
            bottomRight: rotate(bottomRight),
            bottomLeft: rotate(bottomLeft)
        )
    }

    /// 整体平移。
    func offset(dx: CGFloat, dy: CGFloat) -> Quad {
        Quad(
            topLeft: CGPoint(x: topLeft.x + dx, y: topLeft.y + dy),
            topRight: CGPoint(x: topRight.x + dx, y: topRight.y + dy),
            bottomRight: CGPoint(x: bottomRight.x + dx, y: bottomRight.y + dy),
            bottomLeft: CGPoint(x: bottomLeft.x + dx, y: bottomLeft.y + dy)
        )
    }

    /// 各顶点沿远离重心方向外扩，等价于矩形的负 inset。
    func expanded(by amount: CGFloat) -> Quad {
        let cx = points.map(\.x).reduce(0, +) / 4
        let cy = points.map(\.y).reduce(0, +) / 4
        func push(_ p: CGPoint) -> CGPoint {
            let dx = p.x - cx
            let dy = p.y - cy
            let length = max(hypot(dx, dy), 0.001)
            return CGPoint(x: p.x + dx / length * amount, y: p.y + dy / length * amount)
        }
        return Quad(
            topLeft: push(topLeft),
            topRight: push(topRight),
            bottomRight: push(bottomRight),
            bottomLeft: push(bottomLeft)
        )
    }
}

struct RedactionRegion: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect
    /// 非空时表示斜向区域；自动检测区域 rect 为其外接矩形，手动区域 rect 为旋转前的原始矩形
    var quad: Quad?
    let kind: DetectionKind
    let text: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        rect: CGRect,
        quad: Quad? = nil,
        kind: DetectionKind,
        text: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.rect = rect
        self.quad = quad
        self.kind = kind
        self.text = text
        self.isEnabled = isEnabled
    }
}

enum RedactionStyle: String, CaseIterable, Identifiable {
    case solid
    case pixelate
    case blur
    case marker
    case hideText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "色块"
        case .pixelate: return "像素化"
        case .blur: return "模糊"
        case .marker: return "马克笔"
        case .hideText: return "隐藏文字"
        }
    }

    var symbolName: String {
        switch self {
        case .solid: return "rectangle.fill"
        case .pixelate: return "squareshape.split.3x3"
        case .blur: return "drop.halffull"
        case .marker: return "highlighter"
        case .hideText: return "eye.slash"
        }
    }
}
