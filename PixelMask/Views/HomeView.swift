import PhotosUI
import SwiftUI

struct HomeView: View {
    @StateObject private var state = EditorState()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "checkerboard.rectangle")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("PixelMask")
                        .font(.largeTitle.bold())
                    Text("自动识别图片中的隐私信息并打码\n完全离线，图片不会离开您的设备")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("选择图片", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)

                Spacer()

                Text("可检测：电话 · 邮箱 · 证件号 · 人脸 · 二维码\n车牌 · IP · 长数字 · 姓名/地名（实验）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
            .navigationDestination(isPresented: $showEditor) {
                EditorView(state: state)
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        state.load(image: image)
                        showEditor = true
                    }
                    pickerItem = nil
                }
            }
        }
    }
}
