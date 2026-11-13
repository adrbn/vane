#if os(macOS)
import AppKit

/// Two-finger horizontal swipe = back / forward between screens, with the system's own swipe tracking
/// (same feel and same System Settings switch as Safari's "Swipe between pages").
@MainActor enum SwipeNavigation {
    private static var monitor: Any?
    private static var deciding = false

    static func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            if e.phase == .began { deciding = true }
            // Decide on the first event of a trackpad gesture that moves; vertical ones stay ordinary scrolling.
            guard deciding, e.phase == .began || e.phase == .changed,
                  e.scrollingDeltaX != 0 || e.scrollingDeltaY != 0 else { return e }
            deciding = false
            guard NSEvent.isSwipeTrackingFromScrollEventsEnabled, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) * 1.5,
                  !model.settingsOpen, model.canGoBack || model.canGoForward else { return e }
            // Fingers moving right (positive amount) go back, as in Safari.
            e.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                              dampenAmountThresholdMin: model.canGoForward ? -1 : 0,
                              max: model.canGoBack ? 1 : 0) { amount, phase, complete, _ in
                switch phase {
                case .ended:
                    if amount > 0 { model.goBack() } else if amount < 0 { model.goForward() }
                    model.swipeProgress = 0
                case .cancelled: model.swipeProgress = 0
                default: if !complete { model.swipeProgress = amount }
                }
            }
            return nil
        }
    }
}
#endif
