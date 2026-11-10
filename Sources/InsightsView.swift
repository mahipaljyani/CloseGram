import SwiftUI
import Charts

/// "Your week": time, how often you open the app, where you go first, and what was hidden.
struct InsightsView: View {
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var usage: UsageTracker
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.dailyLimit) private var dailyLimit = 0

    @State private var appeared = false
    @State private var shareImage: Image?

    private var week: [Date] { stats.lastDays(7) }
    private var today: DayStats { stats.day(Date()) }
    private var minutesToday: Int { Int(usage.secondsToday) / 60 }

    private var weekMinutes: [(day: Date, minutes: Double)] {
        week.map { ($0, usage.seconds(on: $0) / 60) }
    }

    /// Average over earlier days that had any use, so a new install isn't compared with zeros.
    private var averageMinutes: Double? {
        let earlier = weekMinutes.dropLast().map(\.minutes).filter { $0 > 0 }
        return earlier.isEmpty ? nil : earlier.reduce(0, +) / Double(earlier.count)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    tilesRow
                    weekChart
                    hourChart
                    firstStopCard
                    keptOutCard
                    Label("All of this stays on your iPhone.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 8)
                        .id("bottom")
                }
                .padding(16)
            }
            #if DEBUG
            .onAppear {
                if CommandLine.arguments.contains("-insightsBottom") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("bottom") }
                }
            }
            #endif
            }
            .background(
                LinearGradient(colors: [.cgNavy, .cgNavyDeep], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle("Your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.cgNavy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview("My week on Instagram", image: shareImage)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .tint(.cgGold)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { appeared = true }
            renderShareCard()
        }
    }

    // MARK: Cards

    private var heroCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: appeared ? ringProgress : 0)
                    .stroke(
                        AngularGradient(colors: [.cgGold.opacity(0.6), .cgGold], center: .center),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(appeared ? minutesToday : 0)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                    Text(dailyLimit > 0 ? "of \(dailyLimit) min today" : "min today")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 190, height: 190)

            if let trend = trendText {
                Label(trend.text, systemImage: trend.less ? "arrow.down.right" : "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trend.less ? Color.cgGold : .white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card()
    }

    /// Against the daily limit if there is one, otherwise against the weekly average.
    private var ringProgress: Double {
        let goal = dailyLimit > 0 ? Double(dailyLimit) : max(averageMinutes ?? 30, 1)
        return min(Double(minutesToday) / goal, 1)
    }

    private var trendText: (text: String, less: Bool)? {
        guard let average = averageMinutes else { return nil }
        let diff = Int((Double(minutesToday) - average).rounded())
        if abs(diff) < 1 { return ("Right on your average", true) }
        return diff < 0 ? ("\(-diff) min under your average", true) : ("\(diff) min over your average", false)
    }

    private var tilesRow: some View {
        HStack(spacing: 12) {
            tile(value: "\(today.opens)", label: today.opens == 1 ? "open today" : "opens today", icon: "hand.tap")
            tile(value: frequencyValue, label: "between opens", icon: "clock.arrow.circlepath")
            tile(value: sessionValue, label: "per visit", icon: "timer")
        }
    }

    /// How often you come back: the time from your first open today to now, split across the opens.
    private var frequencyValue: String {
        guard today.opens >= 2, let first = today.firstOpen else { return "–" }
        let minutes = max(0, Int(Date().timeIntervalSince(first) / 60)) / (today.opens - 1)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var sessionValue: String {
        guard today.opens > 0 else { return "–" }
        let seconds = Int(usage.secondsToday) / today.opens
        return seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s"
    }

    private func tile(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.cgGold)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Minutes per day", subtitle: "Last 7 days")
            Chart {
                ForEach(weekMinutes, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Minutes", appeared ? item.minutes : 0)
                    )
                    .foregroundStyle(Calendar.current.isDateInToday(item.day) ? Color.cgGold : .white.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let average = averageMinutes {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.white.opacity(0.5))
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg \(Int(average))m").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(height: 170)
        }
        .padding(16)
        .card()
    }

    private var hourChart: some View {
        let byHour = stats.opensByHour(days: 7)
        let peak = byHour.enumerated().max { $0.element < $1.element }
        return VStack(alignment: .leading, spacing: 12) {
            cardTitle("When you open it", subtitle: peak.map { $0.element > 0 ? "Most often around \(hourLabel($0.offset))" : "No opens yet" } ?? "")
            Chart {
                ForEach(0..<24, id: \.self) { hour in
                    BarMark(
                        x: .value("Hour", hour),
                        y: .value("Opens", appeared ? byHour[hour] : 0)
                    )
                    .foregroundStyle(hour == peak?.offset && byHour[hour] > 0 ? Color.cgGold : .white.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text(hourLabel(hour)) }
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110)
        }
        .padding(16)
        .card()
    }

    private static let placeColors: [String: Color] = [
        "Messages": .cgGold,
        "Feed": Color(red: 0.55, green: 0.6, blue: 1),
        "Search": Color(red: 0.45, green: 0.85, blue: 0.8),
        "Profiles": Color(red: 0.95, green: 0.55, blue: 0.6),
        "Posts": Color(red: 0.75, green: 0.6, blue: 0.95),
        "Reels": Color(red: 1, green: 0.65, blue: 0.4),
        "Stories": Color(red: 0.6, green: 0.85, blue: 0.5),
        "Activity": .white.opacity(0.5),
    ]

    private var firstStopCard: some View {
        let stops = stats.firstStops(days: 7)
        let total = max(stops.reduce(0) { $0 + $1.count }, 1)
        return VStack(alignment: .leading, spacing: 12) {
            cardTitle("Where you go first", subtitle: "Right after opening, last 7 days")
            if stops.isEmpty {
                Text("Open CloseGram a few times and this fills in.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                HStack(spacing: 20) {
                    Chart(stops, id: \.place) { stop in
                        SectorMark(
                            angle: .value("Visits", appeared ? stop.count : 0),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(Self.placeColors[stop.place] ?? .white.opacity(0.4))
                    }
                    .chartLegend(.hidden)
                    .frame(width: 120, height: 120)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(stops[0].count * 100 / total)%")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                            Text(stops[0].place).font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(stops.prefix(5), id: \.place) { stop in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Self.placeColors[stop.place] ?? .white.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                Text(stop.place).font(.subheadline).foregroundStyle(.white)
                                Spacer()
                                Text("\(stop.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .card()
    }

    private static let keptOut: [(kind: String, label: String, icon: String)] = [
        ("suggested", "Ads and suggested posts", "megaphone"),
        ("feedReel", "Reels in your feed", "play.rectangle.on.rectangle"),
        ("reelsTab", "Trips to Reels stopped", "film.stack"),
        ("explore", "Explore grids hidden", "square.grid.3x3"),
        ("feedStop", "Times the feed stopped", "hand.raised"),
        ("messagesOnly", "Kept to messages", "paperplane"),
    ]

    private var keptOutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Kept out of your way", subtitle: "Last 7 days")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(Self.keptOut, id: \.kind) { item in
                    let count = stats.blockedTotal(item.kind, days: 7)
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.footnote)
                            .foregroundStyle(count > 0 ? Color.cgGold : .white.opacity(0.4))
                        Text("\(appeared ? count : 0)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .contentTransition(.numericText())
                            .foregroundStyle(.white)
                        Text(item.label)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(16)
        .card()
    }

    // MARK: Helpers

    private func cardTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).foregroundStyle(.white)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "am" : "pm")"
    }

    // MARK: Share card

    @MainActor
    private func renderShareCard() {
        let weekTotal = Int(weekMinutes.reduce(0) { $0 + $1.minutes })
        let card = ShareCard(
            weekMinutes: weekTotal,
            hidden: stats.blockedTotal("suggested", days: 7) + stats.blockedTotal("feedReel", days: 7),
            reelsStopped: stats.blockedTotal("reelsTab", days: 7),
            opens: week.reduce(0) { $0 + stats.day($1).opens }
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }
}

/// A square summary image for sharing.
private struct ShareCard: View {
    let weekMinutes: Int
    let hidden: Int
    let reelsStopped: Int
    let opens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Circle().stroke(Color.cgGold, lineWidth: 3).frame(width: 22, height: 22)
                Text("CloseGram").font(.headline).foregroundStyle(Color.cgGold)
            }
            Text("My week on Instagram")
                .font(.title2.bold())
                .foregroundStyle(.white)
            row("\(weekMinutes / 60)h \(weekMinutes % 60)m", "on Instagram")
            row("\(hidden)", "ads, suggested posts and reels hidden")
            row("\(reelsStopped)", "trips to Reels stopped")
            row("\(opens)", "times opened")
            Spacer(minLength: 0)
            Text("Only the people I follow.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(28)
        .frame(width: 360, height: 360, alignment: .topLeading)
        .background(LinearGradient(colors: [.cgNavy, .cgNavyDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func row(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.cgGold)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private extension View {
    func card() -> some View {
        background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)))
        )
    }
}
