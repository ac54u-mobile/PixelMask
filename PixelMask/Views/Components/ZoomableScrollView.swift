import SwiftUI
import UIKit

enum CanvasRotationPhase {
    /// 双指捻转开始，附带手势中心点（内容坐标系）。返回 true 表示命中区域、开始旋转
    case began(CGPoint)
    /// 累计旋转弧度与当前中心点
    case changed(CGFloat, CGPoint)
    case ended
}

/// 用 UIScrollView 包裹 SwiftUI 内容实现缩放：
/// 双指捏合缩放、放大后双指平移；单指手势（点按/框选/长按）不受影响。
/// 双指捻转经 onRotate 回调交给内容处理；命中区域时临时冻结缩放/平移。
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private let content: Content
    private let onRotate: ((CanvasRotationPhase) -> Bool)?

    init(onRotate: ((CanvasRotationPhase) -> Bool)? = nil, @ViewBuilder content: () -> Content) {
        self.onRotate = onRotate
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        // 平移需要两指，把单指手势留给画布上的点按/框选
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2

        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        scrollView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        let rotation = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRotation(_:))
        )
        rotation.delegate = context.coordinator
        scrollView.addGestureRecognizer(rotation)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        context.coordinator.onRotate = onRotate
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content), onRotate: onRotate)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let hostingController: UIHostingController<Content>
        var onRotate: ((CanvasRotationPhase) -> Bool)?
        private var isRotatingRegion = false

        init(hostingController: UIHostingController<Content>, onRotate: ((CanvasRotationPhase) -> Bool)?) {
            self.hostingController = hostingController
            self.onRotate = onRotate
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        // 允许捻转与捏合/平移同时识别，否则捏合会独占双指触摸
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let location = gesture.location(in: hostingController.view)

            switch gesture.state {
            case .began:
                isRotatingRegion = onRotate?(.began(location)) ?? false
                if isRotatingRegion {
                    // 命中区域：冻结缩放/平移，双指专注于旋转
                    scrollView.isScrollEnabled = false
                    scrollView.pinchGestureRecognizer?.isEnabled = false
                }
            case .changed:
                if isRotatingRegion {
                    _ = onRotate?(.changed(gesture.rotation, location))
                }
            case .ended, .cancelled, .failed:
                if isRotatingRegion {
                    _ = onRotate?(.ended)
                    scrollView.isScrollEnabled = true
                    scrollView.pinchGestureRecognizer?.isEnabled = true
                    isRotatingRegion = false
                }
            default:
                break
            }
        }
    }
}
