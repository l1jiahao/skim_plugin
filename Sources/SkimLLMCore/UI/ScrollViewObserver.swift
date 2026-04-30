import AppKit
import SwiftUI

struct ScrollViewObserver: NSViewRepresentable {
    @Binding var isNearBottom: Bool
    var threshold: CGFloat = 96

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.threshold = threshold
        view.onNearBottomChange = { isNearBottom = $0 }
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.threshold = threshold
        nsView.onNearBottomChange = { isNearBottom = $0 }
        nsView.installIfNeeded()
    }

    final class ObserverView: NSView {
        var threshold: CGFloat = 96
        var onNearBottomChange: ((Bool) -> Void)?

        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.installIfNeeded()
            }
        }

        func installIfNeeded() {
            guard scrollView == nil else {
                updateNearBottom()
                return
            }

            guard let found = enclosingScrollView() else { return }
            scrollView = found
            found.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: found.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateNearBottom()
            }
            updateNearBottom()
        }

        private func enclosingScrollView() -> NSScrollView? {
            var view: NSView? = self
            while let current = view {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return nil
        }

        private func updateNearBottom() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let visible = scrollView.documentVisibleRect
            let bounds = documentView.bounds

            let distanceToBottom: CGFloat
            if documentView.isFlipped {
                distanceToBottom = bounds.maxY - visible.maxY
            } else {
                distanceToBottom = visible.minY - bounds.minY
            }

            onNearBottomChange?(distanceToBottom <= threshold)
        }
    }
}
