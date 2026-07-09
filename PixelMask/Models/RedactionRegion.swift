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

struct RedactionRegion: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect
    let kind: DetectionKind
    let text: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        rect: CGRect,
        kind: DetectionKind,
        text: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.rect = rect
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
