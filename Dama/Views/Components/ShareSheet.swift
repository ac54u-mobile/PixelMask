import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum ShareableImage {
    /// 写入临时 JPEG 文件再分享，确保接收方拿到的是无元数据的全新文件。
    static func temporaryFileURL(for data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DAMA-\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
