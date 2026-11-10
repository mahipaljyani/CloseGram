import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

/// The Screen Time lock on the real Instagram app. Shared by the app and the
/// LockMonitor extension, which puts the lock back when a timed unlock ends.
enum LockStore {
    static let groupID = Bundle.main.object(forInfoDictionaryKey: "CloseGramAppGroup") as? String ?? ""
    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("closegram.lock"))
    static let unlockActivity = DeviceActivityName("closegram.unlock")
    static let unlockMinutes = 15 // Screen Time schedules can't be shorter than 15 minutes

    static var isOn: Bool {
        get { defaults.bool(forKey: "lockOn") }
        set { defaults.set(newValue, forKey: "lockOn") }
    }

    /// The apps the user picked. Screen Time only gives us opaque tokens for them.
    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: "lockSelection"),
                  let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "lockSelection") }
    }

    static var unlockedUntil: Date? {
        get { defaults.object(forKey: "unlockedUntil") as? Date }
        set { defaults.set(newValue, forKey: "unlockedUntil") }
    }

    static var isTemporarilyUnlocked: Bool { (unlockedUntil ?? .distantPast) > Date() }

    /// True while CloseGram is on screen. Shielding the Instagram app also blocks instagram.com
    /// everywhere, CloseGram's own web view included, so the shield is only up while CloseGram
    /// is in the background. You can't use both apps at once, so the native app stays locked.
    static var appActive: Bool {
        get { defaults.bool(forKey: "appActive") }
        set { defaults.set(newValue, forKey: "appActive") }
    }

    /// Puts the shield in the state the settings ask for.
    static func sync() {
        let apps = selection.applicationTokens
        if isOn && !isTemporarilyUnlocked && !apps.isEmpty && !appActive {
            store.shield.applications = apps
        } else {
            store.clearAllSettings()
        }
    }

    /// Lifts the lock for 15 minutes. The extension locks again when the time is up.
    static func unlockForAWhile() throws {
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(unlockMinutes * 60))
        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: now),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
        let center = DeviceActivityCenter()
        center.stopMonitoring([unlockActivity])
        try center.startMonitoring(unlockActivity, during: schedule)
        unlockedUntil = end
        sync()
    }

    static func lockAgainNow() {
        DeviceActivityCenter().stopMonitoring([unlockActivity])
        unlockedUntil = nil
        sync()
    }
}
