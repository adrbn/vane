#if os(macOS)
import AppKit

/// Two-finger horizontal swipe = back / forward between screens, with the system's own swipe tracking
/// (same feel and same System Settings switch as Safari's "Swipe between pages").
@MainActor enum SwipeNavigation {
    private static var monitor: Any?
    private static var deciding = false
    private static var swallowing = false   // horizontal gesture with nowhere to go: eat it, momentum included

    static func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            if e.phase == .began { deciding = true; swallowing = false }
            if swallowing {
                // A mouse wheel event (no phases) ends it; so does the end of the gesture's momentum.
                if e.phase.isEmpty && e.momentumPhase.isEmpty { swallowing = false; return e }
                if e.momentumPhase == .ended || e.momentumPhase == .cancelled { swallowing = false }
                return nil
            }
            // Decide on the first event of a trackpad gesture that moves; vertical ones stay ordinary scrolling.
            guard deciding, e.phase == .began || e.phase == .changed,
                  e.scrollingDeltaX != 0 || e.scrollingDeltaY != 0 else { return e }
            deciding = false
            // Fingers moving right = back. Only track toward a screen that exists: otherwise the system's
            // rubber-band nudges the screen and snaps it back on every movement, which reads as jitter.
            let fingersRight = e.isDirectionInvertedFromDevice ? e.scrollingDeltaX > 0 : e.scrollingDeltaX < 0
            guard NSEvent.isSwipeTrackingFromScrollEventsEnabled, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) * 1.5,
                  !model.settingsOpen else { return e }
            guard fingersRight ? model.canGoBack : model.canGoForward else { swallowing = true; return nil }
            // Fingers moving right (positive amount) go back, as in Safari.
            e.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                              dampenAmountThresholdMin: fingersRight ? 0 : -1,
                              max: fingersRight ? 1 : 0) { amount, phase, complete, _ in
                // The handler keeps firing while the system animates the end of the swipe; only live finger
                // movement drives the slide, and the screen always ends back at rest.
                switch phase {
                case .began, .changed: model.swipeProgress = fingersRight ? max(0, amount) : min(0, amount)
                case .ended:
                    model.swipeProgress = 0
                    if fingersRight, amount > 0 { model.goBack() } else if !fingersRight, amount < 0 { model.goForward() }
                default: model.swipeProgress = 0
                }
                if complete { model.swipeProgress = 0 }
            }
            return nil
        }
    }
}
#endif
