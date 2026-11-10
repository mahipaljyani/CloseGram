import SwiftUI

extension Color {
    // The app icon's colours.
    static let cgNavy = Color(red: 34 / 255, green: 38 / 255, blue: 92 / 255)
    static let cgNavyDeep = Color(red: 14 / 255, green: 16 / 255, blue: 48 / 255)
    static let cgGold = Color(red: 232 / 255, green: 190 / 255, blue: 104 / 255)
}

/// What happened on one day. Time on screen is kept by UsageTracker.
struct DayStats: Codable {
    var opens = 0
    var firstOpen: Date?
    var hours = [Int](repeating: 0, count: 24)  // opens per hour of the day
    var first: [String: Int] = [:]             // where each visit went first
    var blocked: [String: Int] = [:]           // things CloseGram kept out of the way
}

/// Counts opens, where each visit goes first, and what got hidden. Stored only on this iPhone.
/// Not @Published on purpose: recording happens while you scroll, and redrawing the main
/// screen mid-touch crashed UIKit's touch handling. The stats screen reads it when it opens.
final class StatsStore: ObservableObject {
    private(set) var days: [String: DayStats] = [:]

    /// Reads the page the web view is on, for visits that don't navigate anywhere.
    var currentPath: () -> String = { "/" }

    private let defaults = UserDefaults.standard
    private static let key = "stats.v1"
    private static let newVisitAfter: TimeInterval = 30
    private var backgroundedAt: Date?
    private var hasOpened = false
    private var awaitingFirstStop = false
    private var pendingSave: DispatchWorkItem?

    init() {
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: DayStats].self, from: data) {
            days = saved
        }
        #if DEBUG
        if CommandLine.arguments.contains("-seedStats") { seedSample() }
        #endif
    }

    #if DEBUG
    /// Debug builds only: fills a week of sample numbers, for checking the stats screen.
    func seedSample() {
        for (offset, date) in lastDays(7).enumerated() {
            var day = DayStats()
            day.opens = 4 + offset * 2
            day.firstOpen = date.addingTimeInterval(8 * 3600)
            for hour in [8, 9, 13, 21, 22, 22, 23] { day.hours[hour] += 1 + offset % 3 }
            day.first = ["Messages": 3 + offset, "Feed": 2, "Profiles": 1 + offset % 2, "Search": offset % 3]
            day.blocked = ["suggested": 9 + offset * 3, "feedReel": 5 + offset, "reelsTab": offset % 4, "explore": 2, "feedStop": 1]
            days[UsageTracker.dayKey(date)] = day
            UserDefaults.standard.set(Double([42, 55, 31, 48, 26, 37, 0][offset] * 60), forKey: "usage-" + UsageTracker.dayKey(date))
        }
    }
    #endif

    // MARK: Recording

    func appBecameActive() {
        let away = backgroundedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        backgroundedAt = nil
        guard !hasOpened || away > Self.newVisitAfter else { return }
        hasOpened = true

        let now = Date()
        update(now) { day in
            day.opens += 1
            if day.firstOpen == nil { day.firstOpen = now }
            day.hours[Calendar.current.component(.hour, from: now)] += 1
        }
        // The first page opened in the next few seconds is where this visit went first.
        // If nothing opens, the visit stayed on the page it was already on.
        awaitingFirstStop = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.awaitingFirstStop else { return }
            self.recordFirstStop(self.currentPath())
        }
    }

    func appWentBackground() {
        backgroundedAt = Date()
    }

    func noteRoute(_ path: String) {
        guard awaitingFirstStop, path != "/accounts/login/" else { return }
        recordFirstStop(path)
    }

    func recordBlocked(_ kind: String) {
        update(Date()) { $0.blocked[kind, default: 0] += 1 }
    }

    private func recordFirstStop(_ path: String) {
        awaitingFirstStop = false
        let place = Self.place(for: path)
        update(Date()) { $0.first[place, default: 0] += 1 }
    }

    private func update(_ date: Date, _ change: (inout DayStats) -> Void) {
        let key = UsageTracker.dayKey(date)
        var day = days[key] ?? DayStats()
        change(&day)
        days[key] = day
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Keep about two months.
            let cutoff = UsageTracker.dayKey(Date().addingTimeInterval(-60 * 86_400))
            self.days = self.days.filter { $0.key >= cutoff }
            if let data = try? JSONEncoder().encode(self.days) { self.defaults.set(data, forKey: Self.key) }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: Reading

    static func place(for path: String) -> String {
        if path.hasPrefix("/direct") { return "Messages" }
        if path == "/" { return "Feed" }
        if path.hasPrefix("/explore") { return "Search" }
        if path.hasPrefix("/reel") { return "Reels" }
        if path.hasPrefix("/stories") { return "Stories" }
        if path.hasPrefix("/p/") { return "Posts" }
        if path.hasPrefix("/accounts") || path.hasPrefix("/notifications") { return "Activity" }
        return "Profiles"
    }

    /// The last `count` days, oldest first, ending today.
    func lastDays(_ count: Int) -> [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }

    func day(_ date: Date) -> DayStats { days[UsageTracker.dayKey(date)] ?? DayStats() }

    func blockedTotal(_ kind: String, days count: Int) -> Int {
        lastDays(count).reduce(0) { $0 + day($1).blocked[kind, default: 0] }
    }

    func firstStops(days count: Int) -> [(place: String, count: Int)] {
        var totals: [String: Int] = [:]
        for date in lastDays(count) {
            for (place, n) in day(date).first { totals[place, default: 0] += n }
        }
        return totals.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    func opensByHour(days count: Int) -> [Int] {
        lastDays(count).reduce(into: [Int](repeating: 0, count: 24)) { sum, date in
            for (hour, n) in day(date).hours.enumerated() { sum[hour] += n }
        }
    }
}
