#if os(iOS)
import BackgroundTasks
import Foundation
import os

/// The refresh the user starts on iPhone: iOS keeps it running after they leave the app and shows its progress
/// (iOS 26 continued processing). Without it, iOS gives a backgrounded app about 30 seconds.
@MainActor
final class ContinuedSync {
    static let prefix = "com.adrbn.vane.sync"   // Info.plist allows "com.adrbn.vane.sync.*"
    private static let log = Logger(subsystem: "com.adrbn.vane", category: "sync")

    private var task: BGContinuedProcessingTask?
    private var total: Int64 = 1
    private var done = false
    /// iOS stopped the task (low battery, the user swiped it away…): the sync is treated as cut short.
    var onExpire: () -> Void = {}

    /// Asks iOS to run the sync as a visible task. Returns false if iOS refused (the 30-second grace still applies).
    @discardableResult
    func start(steps: Int, title: String) -> Bool {
        done = false; total = Int64(max(1, steps))
        // One identifier per run: registering the same identifier twice is an error.
        let id = "\(Self.prefix).\(UUID().uuidString.prefix(8))"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.attach(t) }
        }
        guard registered else { Self.log.error("register refused for \(id)"); return false }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: "")
        request.strategy = .fail   // now or not at all: a refresh queued for later makes no sense
        do { try BGTaskScheduler.shared.submit(request) } catch {
            Self.log.error("submit failed: \(error.localizedDescription)")
            return false
        }
        return true
    }

    private func attach(_ t: BGTask) {
        guard let t = t as? BGContinuedProcessingTask, !done else { t.setTaskCompleted(success: true); return }
        task = t
        t.progress.totalUnitCount = total
        t.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, let task = self.task else { return }
                self.task = nil
                self.onExpire()
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// One sync step done; its name is the subtitle under the progress.
    func step(_ name: String) {
        guard let task else { return }
        task.progress.completedUnitCount = min(total - 1, task.progress.completedUnitCount + 1)
        task.updateTitle(task.title, subtitle: name)
    }

    func finish(success: Bool) {
        done = true
        guard let task else { return }
        self.task = nil
        task.progress.completedUnitCount = total
        task.setTaskCompleted(success: success)
    }
}
#endif
