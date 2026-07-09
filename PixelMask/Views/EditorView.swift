import SwiftUI

struct EditorView: View {
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss

    @State private var dragRect: CGRect?
    @State private var showShareSheet = false
    @State private var showSettings = false
    @State private var justSaved = false
    @State private var showOriginal = false

    private enum CanvasDragMode {
        case select
        case move(id: UUID, base: RedactionRegion)
    }
    @State private var dragMode: CanvasDragMode?

    var body: some View {
        VStack(spacing: 0) {
            canvas
            toolbar
        }
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
        // 隐藏系统返回键以禁用左边缘右滑返回手势，否则从左边缘开始框选会误触返回
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    guard let result = state.renderResult() else { return }
                    UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
                    justSaved = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        justSaved = false
                    }
                } label: {
                    Image(systemName: justSaved ? "checkmark" : "square.and.arrow.down")
                }
                .disabled(state.image == nil)

                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(state.image == nil)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let export = state.exportData() {
                ShareSheet(items: [
                    ShareableImage.temporaryFileURL(for: export.data, fileExtension: export.fileExtension) ?? export.data,
                ])
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(state: state)
        }
    }

    private var canvas: some View {
        ZoomableScrollView {
            canvasContent
        }
    }

    private var canvasContent: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            ZStack {
                Color(.systemGroupedBackground)

                if let displayed = showOriginal ? state.image : (state.previewImage ?? state.image) {
                    Image(uiImage: displayed)
                        .resizable()
                        .scaledToFit()
                        .frame(width: containerSize.width, height: containerSize.height)

                    regionOverlays(imageSize: displayed.size, containerSize: containerSize)

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

                    if showOriginal {
                        VStack {
                            Text("原图")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.regularMaterial, in: Capsule())
                            Spacer()
                        }
                        .padding(.top, 12)
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
            .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 10) {
            } onPressingChanged: { pressing in
                showOriginal = pressing && state.image != nil
            }
        }
    }

    /// 打码效果实时显示在图上，这里只画细边框提示可点按：
    /// 实线 = 已打码（点按取消），虚线 = 检测到但未启用（点按开启）。
    /// 斜向区域按四边形描边，水平区域用圆角矩形。
    private func regionOverlays(imageSize: CGSize, containerSize: CGSize) -> some View {
        ForEach(state.regions) { region in
            let strokeColor = region.isEnabled ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.7)
            let strokeStyle = StrokeStyle(lineWidth: 1.5, dash: [4, 3])

            if let quad = region.quad {
                Path { path in
                    let points = quad.points.map {
                        CoordinateMapper.toView($0, imageSize: imageSize, containerSize: containerSize)
                    }
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.closeSubpath()
                }
                .stroke(strokeColor, style: strokeStyle)
                .allowsHitTesting(false)
            } else {
                let viewRect = CoordinateMapper.toView(region.rect, imageSize: imageSize, containerSize: containerSize)
                if viewRect.width > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(strokeColor, style: strokeStyle)
                        .frame(width: max(viewRect.width, 10), height: max(viewRect.height, 10))
                        .position(x: viewRect.midX, y: viewRect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// 拖动起点落在已打码区域内 = 移动该区域，落在空白处 = 框选新区域。
    private func dragGesture(imageSize: CGSize, containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard imageSize != .zero else { return }

                if dragMode == nil {
                    let startPoint = CoordinateMapper.toImage(value.startLocation, imageSize: imageSize, containerSize: containerSize)
                    if let region = state.enabledRegion(at: startPoint) {
                        dragMode = .move(id: region.id, base: region)
                        state.beginRegionDrag()
                    } else {
                        dragMode = .select
                    }
                }

                switch dragMode {
                case .move(let id, let base):
                    let frame = CoordinateMapper.fittedImageFrame(imageSize: imageSize, containerSize: containerSize)
                    guard frame.width > 0 else { return }
                    let scale = imageSize.width / frame.width
                    state.moveRegion(
                        id: id,
                        base: base,
                        dx: value.translation.width * scale,
                        dy: value.translation.height * scale
                    )
                case .select:
                    let start = value.startLocation
                    dragRect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )
                case nil:
                    break
                }
            }
            .onEnded { _ in
                if case .select = dragMode, let dragRect, imageSize != .zero {
                    let imageRect = CoordinateMapper.toImage(dragRect, imageSize: imageSize, containerSize: containerSize)
                    state.addManualRegion(imageRect)
                }
                dragMode = nil
                dragRect = nil
            }
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button {
                    state.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!state.canUndo)

                Button {
                    state.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!state.canRedo)

                Text("已选 \(state.enabledCount) 处")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("全选") { state.enableAll() }
                    .font(.footnote)
                Button("清空") { state.disableAll() }
                    .font(.footnote)

                if state.style == .solid {
                    ColorPicker("", selection: $state.solidColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 32)
                }

                Button {
                    state.detect()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.isDetecting)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            .font(.system(size: 16))
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

            Text("轻点整行打码 · 空白处框选 · 拖动区域移动 · 双指缩放")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .background(.bar)
    }
}
