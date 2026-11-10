import SwiftUI
import LocalAuthentication

@main
struct CloseGramApp: App {
    @StateObject private var web: WebModel
    @StateObject private var usage = UsageTracker()
    @StateObject private var gate = Gate()
    @StateObject private var stats: StatsStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Pref.registerDefaults() // before WebModel reads any setting
        // Lift the Instagram lock before the web view loads instagram.com.
        LockStore.appActive = true
        LockStore.sync()
        // Created lazily by SwiftUI once the app is running. Building the web view here, in the
        // App's init before UIKit has finished launching, broke touch handling and crashed the
        // app on the first swipe (UIGestureRecognizer _delayTouchesForEvent inserting nil).
        _web = StateObject(wrappedValue: WebModel())
        _stats = StateObject(wrappedValue: StatsStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(web)
                .environmentObject(usage)
                .environmentObject(gate)
                .environmentObject(stats)
                .onAppear { connectStats() }
        }
        .onChange(of: scenePhase) { _, phase in
            usage.setActive(phase == .active)
            gate.scenePhaseChanged(phase)
            if phase == .active { stats.appBecameActive() }
            if phase == .background { stats.appWentBackground() }
            if phase == .active {
                LockStore.appActive = true
                LockStore.sync()
                web.refreshTimeBasedMode()
                web.reloadIfBlocked()
            }
            if phase == .background {
                LockStore.appActive = false
                LockStore.sync() // locks the Instagram app again while you're away
            }
        }
    }
}

extension CloseGramApp {
    /// Lets the stats store hear about pages and hidden posts. Runs after both objects exist.
    func connectStats() {
        guard web.onStat == nil else { return }
        let stats = stats
        web.onRoute = { [weak stats] path in stats?.noteRoute(path) }
        web.onStat = { [weak stats] kind in stats?.recordBlocked(kind) }
        stats.currentPath = { [weak web] in web?.path ?? "/" }
    }
}

/// Counts how long the app is on screen each day, and any extra time unlocked past the daily limit.
/// Stored only on the device.
final class UsageTracker: ObservableObject {
    private var activeSince: Date?
    private let defaults = UserDefaults.standard

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
    private static func day(_ date: Date) -> String { dayKey(date) }

    /// Seconds on screen on any day; today includes the visit in progress.
    func seconds(on date: Date) -> TimeInterval {
        Calendar.current.isDateInToday(date) ? secondsToday : defaults.double(forKey: "usage-" + Self.day(date))
    }

    func setActive(_ active: Bool) {
        if active {
            if activeSince == nil { activeSince = Date() }
        } else if let start = activeSince {
            let key = "usage-" + Self.day(start)
            defaults.set(defaults.double(forKey: key) + Date().timeIntervalSince(start), forKey: key)
            activeSince = nil
        }
        objectWillChange.send()
    }

    var secondsToday: TimeInterval {
        let stored = defaults.double(forKey: "usage-" + Self.day(Date()))
        guard let start = activeSince else { return stored }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return stored + Date().timeIntervalSince(max(start, startOfToday))
    }

    /// Seconds allowed today: the daily limit plus any extra time unlocked today.
    func allowanceToday(limitMinutes: Int) -> TimeInterval {
        TimeInterval(limitMinutes * 60) + defaults.double(forKey: "bonus-" + Self.day(Date()))
    }

    func addBonus(minutes: Int) {
        let key = "bonus-" + Self.day(Date())
        // Extra time counts from now, not from when the limit was hit.
        let limit = TimeInterval(Pref.int(Pref.dailyLimit) * 60)
        let overBy = max(0, secondsToday - limit - defaults.double(forKey: key))
        defaults.set(defaults.double(forKey: key) + overBy + TimeInterval(minutes * 60), forKey: key)
        objectWillChange.send()
    }
}

/// Decides when to show the Face ID lock and the pause screen.
final class Gate: ObservableObject {
    @Published var needsUnlock: Bool { didSet { if needsUnlock { autoTried = false } } }
    @Published var needsPause: Bool
    var autoTried = false
    private var backgroundedAt: Date?

    /// How long the app must be in the background before each screen comes back.
    private static let lockAfter: TimeInterval = 10
    private static let pauseAfter: TimeInterval = 120

    init() {
        Pref.registerDefaults()
        needsUnlock = Pref.bool(Pref.faceID)
        needsPause = Pref.bool(Pref.pauseOnOpen)
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            guard let since = backgroundedAt else { return }
            backgroundedAt = nil
            let away = Date().timeIntervalSince(since)
            if Pref.bool(Pref.faceID) && away > Self.lockAfter { needsUnlock = true }
            if Pref.bool(Pref.pauseOnOpen) && away > Self.pauseAfter { needsPause = true }
        default:
            break
        }
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?
        // Falls back to the passcode. With no passcode set, there is nothing to lock with.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            needsUnlock = false
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock CloseGram") { success, _ in
            DispatchQueue.main.async { if success { self.needsUnlock = false } }
        }
    }
}
