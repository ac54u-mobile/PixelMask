import SwiftUI

struct EditorView: View {
    @ObservedObject var state: EditorState

    @State private var dragStart: CGPoint?
    @State private var dragRect: CGRect?
    @State private var showResult = false

    var body: some View {
        VStack(spacing: 0) {
            canvas
            toolbar
        }
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showResult = true
                } label: {
                    Text("完成").bold()
                }
                .disabled(state.image == nil)
            }
        }
        .navigationDestination(isPresented: $showResult) {
            ResultView(state: state)
        }
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            ZStack {
                Color(.systemGroupedBackground)

                if let image = state.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: containerSize.width, height: containerSize.height)

                    regionOverlays(imageSize: image.size, containerSize: containerSize)

                    if let dragRect {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.25))
                            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                            .frame(width: dragRect.width, height: dragRect.height)
                            .position(x: dragRect.midX, y: dragRect.midY)
                    }

                    if state.isDetecting {
                        ProgressView("识别中…")
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(imageSize: state.image?.size ?? .zero, containerSize: containerSize))
            .onTapGesture { location in
                guard let image = state.image else { return }
                let point = CoordinateMapper.toImage(location, imageSize: image.size, containerSize: containerSize)
                state.handleTap(at: point)
            }
        }
    }

    private func regionOverlays(imageSize: CGSize, containerSize: CGSize) -> some View {
        ForEach(state.regions) { region in
            let viewRect = CoordinateMapper.toView(region.rect, imageSize: imageSize, containerSize: containerSize)
            if viewRect.width > 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(region.isEnabled ? Color.accentColor.opacity(0.45) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(
                                region.isEnabled ? Color.accentColor : Color.secondary.opacity(0.7),
                                style: StrokeStyle(lineWidth: 1.5, dash: region.isEnabled ? [] : [4, 3])
                            )
                    )
                    .frame(width: max(viewRect.width, 10), height: max(viewRect.height, 10))
                    .position(x: viewRect.midX, y: viewRect.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func dragGesture(imageSize: CGSize, containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                let start = dragStart ?? value.startLocation
                dragRect = CGRect(
                    x: min(start.x, value.location.x),
                    y: min(start.y, value.location.y),
                    width: abs(value.location.x - start.x),
                    height: abs(value.location.y - start.y)
                )
            }
            .onEnded { _ in
                if let dragRect, imageSize != .zero {
                    let imageRect = CoordinateMapper.toImage(dragRect, imageSize: imageSize, containerSize: containerSize)
                    state.addManualRegion(imageRect)
                }
                dragStart = nil
                dragRect = nil
            }
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("已选 \(state.enabledCount) 处")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if state.style == .solid {
                    ColorPicker("", selection: $state.solidColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 32)
                }
                Button {
                    state.detect()
                } label: {
                    Label("重新识别", systemImage: "arrow.clockwise")
                        .font(.footnote)
                }
                .disabled(state.isDetecting)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                ForEach(RedactionStyle.allCases) { style in
                    Button {
                        state.style = style
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: style.symbolName)
                                .font(.system(size: 18))
                            Text(style.title)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(state.style == style ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                        .foregroundStyle(state.style == style ? Color.accentColor : Color.primary)
                    }
                }
            }
            .padding(.horizontal, 12)

            Text("轻点文字整行打码 · 轻点色块取消 · 拖动框选任意区域")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .background(.bar)
    }
}
