//
//  ZoomableContainer.swift
//  Manga-Reader
//
//  UIScrollView-backed zoom for a single reader page. Hosts SwiftUI content
//  inside a UIScrollView so pinch / pan / double-tap get native scroll-view
//  physics (velocity, deceleration, rubber-band, pinch anchored at the
//  fingers) — the "zooming a photo in Photos" feel that SwiftUI gesture
//  state-updates can't reproduce.
//
//  Contract with the paged reader:
//    • At 1× the hosted view exactly fits the page (contentSize == bounds)
//      and `alwaysBounce*` is off, so the scroll view's pan recognizer fails
//      and the TabView pager owns the swipe.
//    • While zoomed the pan owns the touch; at a content edge it rubber-bands.
//      (The pager is a SwiftUI-native gesture, so a UIKit mid-gesture handoff
//      to it is not possible — rubber-banding is the deliberate fallback.)
//    • Taps are handled by SwiftUI *inside* the hosted content: the single
//      tap (chrome toggle) waits for double-tap failure, and buttons in the
//      content (the page-retry affordance) win over the background tap,
//      exactly as they did in the pure-SwiftUI implementation. The double
//      tap's `.local` location is in the hosted view's unscaled coordinate
//      space — precisely what `UIScrollView.zoom(to:animated:)` expects.
//    • When `isActive` flips false (the page stops being the pager's
//      selection) zoom resets to 1× without animation.
//
//  This container assumes it fills its page and that the whole reader is in
//  an identity coordinate space — the paged reader must never mirror it with
//  `scaleEffect(x: -1)` (RTL is done by reversing page order instead).
//

import SwiftUI
import UIKit

struct ZoomableContainer<Content: View>: UIViewRepresentable {
    /// Whether this page is the pager's current selection. Zoom resets the
    /// moment this turns false, so a page is always back at 1× on return.
    let isActive: Bool
    let onSingleTap: () -> Void
    @ViewBuilder let content: () -> Content

    private static var maximumZoom: CGFloat { 4 }
    private static var doubleTapZoom: CGFloat { 2.5 }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let coordinator = context.coordinator

        let hosting = UIHostingController(rootView: hostedRoot(coordinator))
        hosting.view.backgroundColor = .clear
        // The page sits edge-to-edge under an `ignoresSafeArea` pager; without
        // this the hosting view would re-apply the screen's safe-area insets,
        // shifting both the content layout and the tap coordinates.
        hosting.safeAreaRegions = []
        coordinator.hostingController = hosting

        let scrollView = ZoomHostScrollView()
        scrollView.hostedView = hosting.view
        scrollView.delegate = coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = Self.maximumZoom
        scrollView.bouncesZoom = true                // native pinch overshoot
        scrollView.bounces = true                    // rubber-band while zoomed…
        scrollView.alwaysBounceHorizontal = false    // …but never at 1×, so the
        scrollView.alwaysBounceVertical = false      // pan fails → pager swipes
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.scrollsToTop = false
        scrollView.backgroundColor = .clear
        scrollView.addSubview(hosting.view)

        coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSingleTap = onSingleTap
        // Re-assign the root so content-identity changes made by the parent
        // (e.g. the reader's reload token) propagate into the hosted tree.
        coordinator.hostingController?.rootView = hostedRoot(coordinator)
        if !isActive { coordinator.resetZoom() }
    }

    private func hostedRoot(_ coordinator: Coordinator) -> ZoomableContent<Content> {
        ZoomableContent(
            onSingleTap: { [weak coordinator] in coordinator?.onSingleTap() },
            onDoubleTap: { [weak coordinator] point in coordinator?.toggleZoom(at: point) },
            content: content
        )
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        fileprivate var hostingController: UIHostingController<ZoomableContent<Content>>?
        weak var scrollView: UIScrollView?
        var onSingleTap: () -> Void = {}

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController?.view
        }

        /// Double-tap: zoom into the tapped point (Photos-style) or, if
        /// already zoomed, back out to 1×. `point` is in the hosted view's
        /// unscaled coordinate space — the space `zoom(to:)` expects.
        func toggleZoom(at point: CGPoint) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let size = CGSize(width: scrollView.bounds.width / ZoomableContainer.doubleTapZoom,
                                  height: scrollView.bounds.height / ZoomableContainer.doubleTapZoom)
                let rect = CGRect(x: point.x - size.width / 2,
                                  y: point.y - size.height / 2,
                                  width: size.width,
                                  height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }

        /// Instant reset, used when the page stops being the pager's selection.
        func resetZoom() {
            guard let scrollView, scrollView.zoomScale != scrollView.minimumZoomScale else { return }
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
            scrollView.contentOffset = .zero
        }
    }
}

// MARK: - Hosted wrapper

/// The SwiftUI tree hosted inside the scroll view: fills the page, catches
/// taps, and renders the caller's content (image / placeholder / retry).
private struct ZoomableContent<Content: View>: View {
    let onSingleTap: () -> Void
    let onDoubleTap: (CGPoint) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Order matters: declaring the double tap first makes the single
            // tap wait for double-tap failure (the same arbitration the old
            // SwiftUI gesture stack relied on), and buttons inside `content`
            // still win over both.
            .onTapGesture(count: 2) { (point: CGPoint) in onDoubleTap(point) }
            .onTapGesture(perform: onSingleTap)
    }
}

// MARK: - Scroll view subclass

/// Keeps the hosted view sized to the page. A representable gets no layout
/// callback of its own, so sizing happens in `layoutSubviews`: whenever the
/// bounds *size* actually changes (first layout, rotation) the zoom resets
/// and the hosted view is re-fitted, making contentSize == bounds at 1×.
private final class ZoomHostScrollView: UIScrollView {
    weak var hostedView: UIView?
    private var lastLayoutSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let hostedView, bounds.size != lastLayoutSize, bounds.size != .zero else { return }
        lastLayoutSize = bounds.size
        zoomScale = minimumZoomScale   // clear any zoom transform before re-fitting
        hostedView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
        contentOffset = .zero
    }
}
