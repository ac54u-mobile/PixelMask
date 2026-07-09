import PhotosUI
import SwiftUI
import UIKit

struct HomeView: View {
    @State private var sessionStates: [EditorState] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showEditor = false
    @State private var showCamera = false
    @State private var isLoading = false

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

                VStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                        Label("选择图片（可多选）", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("拍照打码", systemImage: "camera")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 40)
                .disabled(isLoading)

                if isLoading {
                    ProgressView("载入图片…")
                }

                Spacer()

                Text("可检测：电话 · 邮箱 · 证件号 · 人脸 · 二维码\n车牌 · IP · 长数字 · 姓名/地名（实验）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
            .navigationDestination(isPresented: $showEditor) {
                BatchEditorView(states: sessionStates)
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                isLoading = true
                Task {
                    var states: [EditorState] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            let state = EditorState()
                            state.load(image: image)
                            states.append(state)
                        }
                    }
                    isLoading = false
                    pickerItems = []
                    if !states.isEmpty {
                        sessionStates = states
                        showEditor = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    let state = EditorState()
                    state.load(image: image)
                    sessionStates = [state]
                    showEditor = true
                }
                .ignoresSafeArea()
            }
        }
    }
}
