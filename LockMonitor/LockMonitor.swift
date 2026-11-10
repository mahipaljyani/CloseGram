import DeviceActivity

/// Runs in the background when a timed unlock ends, and puts the lock back.
final class LockMonitor: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == LockStore.unlockActivity else { return }
        LockStore.unlockedUntil = nil
        LockStore.sync()
    }
}
