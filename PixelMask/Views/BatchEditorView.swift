import SwiftUI

/// 多图编辑容器：缩略图切换当前图片，可一键保存全部。
struct BatchEditorView: View {
    let states: [EditorState]

    @State private var currentIndex = 0
    @State private var savedAll = false

    var body: some View {
        VStack(spacing: 0) {
            if states.indices.contains(currentIndex) {
                EditorView(state: states[currentIndex])
                    .id(currentIndex)
            }
            if states.count > 1 {
                thumbnailStrip
            }
        }
        .toolbar {
            if states.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        for state in states {
                            if let result = state.renderResult() {
                                UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
                            }
                        }
                        savedAll = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            savedAll = false
                        }
                    } label: {
                        Image(systemName: savedAll ? "checkmark" : "square.and.arrow.down.on.square")
                    }
                    .disabled(savedAll)
                }
            }
        }
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(states.indices, id: \.self) { index in
                    if let image = states[index].image {
                        Button {
                            currentIndex = index
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            index == currentIndex ? Color.accentColor : Color.clear,
                                            lineWidth: 2.5
                                        )
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}
