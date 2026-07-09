import Foundation
import NaturalLanguage

struct SensitiveMatch {
    let range: Range<String.Index>
    let kind: DetectionKind
}

/// 基于规则的敏感信息分类器，识别一行文字中的隐私片段。
enum SensitiveTextClassifier {

    private static let patterns: [(DetectionKind, NSRegularExpression)] = {
        let raw: [(DetectionKind, String)] = [
            // 中国大陆手机号
            (.phone, #"(?<!\d)1[3-9]\d{9}(?!\d)"#),
            // 带分隔符的电话（座机/横线分隔手机号）
            (.phone, #"(?<!\d)(?:\d{3,4}[- ]\d{7,8}|\d{3}[- ]\d{4}[- ]\d{4})(?!\d)"#),
            (.email, #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
            // 18 位身份证
            (.idNumber, #"(?<!\d)\d{17}[\dXx](?!\d)"#),
            (.ipAddress, #"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)"#),
            // 中国车牌：普通 5 位 / 新能源 6 位，容忍 OCR 识别出的间隔符（·、•、.、-、空格）
            (.carPlate, #"[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼使领][A-HJ-NP-Z][·•\.\-\s]?[A-HJ-NP-Z0-9]{4,6}[挂学警港澳]?"#),
            // 可能暴露信息的长数字（卡号、订单号、ID 等）
            (.longNumber, #"(?<!\d)\d{6,}(?!\d)"#),
        ]
        return raw.compactMap { kind, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (kind, regex)
        }
    }()

    static func matches(in text: String) -> [SensitiveMatch] {
        var results: [SensitiveMatch] = []
        let nsRange = NSRange(text.startIndex..., in: text)

        for (kind, regex) in patterns {
            for match in regex.matches(in: text, range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                // 长数字与更具体的类型（手机号/身份证）重叠时跳过
                let overlapped = results.contains { $0.range.overlaps(range) }
                if !overlapped {
                    results.append(SensitiveMatch(range: range, kind: kind))
                }
            }
        }

        results.append(contentsOf: nameEntityMatches(in: text, excluding: results))
        return results
    }

    /// 姓名、地名、机构名（实验性质），使用系统 NLTagger。
    private static func nameEntityMatches(
        in text: String,
        excluding existing: [SensitiveMatch]
    ) -> [SensitiveMatch] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var results: [SensitiveMatch] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            guard let tag else { return true }
            let kind: DetectionKind?
            switch tag {
            case .personalName: kind = .personName
            case .placeName, .organizationName: kind = .placeName
            default: kind = nil
            }
            if let kind, !existing.contains(where: { $0.range.overlaps(range) }) {
                results.append(SensitiveMatch(range: range, kind: kind))
            }
            return true
        }
        return results
    }
}
