import SwiftUI

struct ResultView: View {
    @ObservedObject var state: EditorState

    @State private var result: UIImage?
    @State private var showShareSheet = false
    @State private var savedToAlbum = false

    var body: some View {
        VStack(spacing: 16) {
            if let result {
                Image(uiImage: result)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)

                HStack(spacing: 12) {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
                        savedToAlbum = true
                    } label: {
                        Label(savedToAlbum ? "已保存" : "保存到相册", systemImage: savedToAlbum ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(savedToAlbum)

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)

                Text("导出的图片已移除 EXIF/GPS 等元数据")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            } else {
                ProgressView("正在生成…")
            }
        }
        .navigationTitle("结果")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if result == nil {
                result = state.renderResult()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let result, let data = result.jpegData(compressionQuality: 0.92) {
                ShareSheet(items: [ShareableImage.temporaryFileURL(for: data) ?? data])
            }
        }
    }
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
