import Foundation

/// Every setting key, its default, and the rules derived from them.
enum Pref {
    // Feed
    static let blockReels = "blockReels"
    static let blockExplore = "blockExplore"
    static let hideSuggested = "hideSuggested"
    static let hideFeedReels = "hideFeedReels"
    static let followingOnly = "followingOnly"
    static let feedCap = "feedCap"            // 0 = off
    static let stopAtSeen = "stopAtSeen"
    static let hideLikes = "hideLikes"
    static let hideStories = "hideStories"
    // Messages
    static let messagesOnly = "messagesOnly"
    static let quietHours = "quietHours"
    static let quietStart = "quietStart"      // hour 0-23
    static let quietEnd = "quietEnd"          // hour 0-23
    // Opening
    static let pauseOnOpen = "pauseOnOpen"
    static let dailyLimit = "dailyLimit"      // minutes, 0 = off
    static let faceID = "faceIDLock"
    // Look
    static let grayscale = "grayscale"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            blockReels: true, blockExplore: true, hideSuggested: true, hideFeedReels: true,
            followingOnly: false, feedCap: 0, stopAtSeen: false, hideLikes: false, hideStories: false,
            messagesOnly: false, quietHours: false, quietStart: 22, quietEnd: 7,
            pauseOnOpen: false, dailyLimit: 0, faceID: false,
            grayscale: false,
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }

    /// True inside the quiet-hours window. The window may cross midnight, e.g. 22 to 7.
    static func inQuietHours(at date: Date = Date()) -> Bool {
        guard bool(quietHours) else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        let start = int(quietStart), end = int(quietEnd)
        if start == end { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    /// Messages-only applies when it is switched on, or during quiet hours.
    static var messagesOnlyNow: Bool { bool(messagesOnly) || inQuietHours() }
}

/// The settings the injected script needs, passed to it as JSON.
struct ScriptConfig: Codable, Equatable {
    var blockReels: Bool
    var blockExplore: Bool
    var hideSuggested: Bool
    var hideFeedReels: Bool
    var followingOnly: Bool
    var feedCap: Int
    var stopAtSeen: Bool
    var hideLikes: Bool
    var hideStories: Bool
    var messagesOnly: Bool
    var grayscale: Bool

    static func current() -> ScriptConfig {
        ScriptConfig(
            blockReels: Pref.bool(Pref.blockReels),
            blockExplore: Pref.bool(Pref.blockExplore),
            hideSuggested: Pref.bool(Pref.hideSuggested),
            hideFeedReels: Pref.bool(Pref.hideFeedReels),
            followingOnly: Pref.bool(Pref.followingOnly),
            feedCap: Pref.int(Pref.feedCap),
            stopAtSeen: Pref.bool(Pref.stopAtSeen),
            hideLikes: Pref.bool(Pref.hideLikes),
            hideStories: Pref.bool(Pref.hideStories),
            messagesOnly: Pref.messagesOnlyNow,
            grayscale: Pref.bool(Pref.grayscale)
        )
    }

    /// Where the app opens for these settings.
    var startPath: String {
        if messagesOnly { return "/direct/inbox/" }
        if followingOnly { return "/?variant=following" }
        return "/"
    }
}
