import SwiftUI
import FamilyControls

struct ContentView: View {
    @EnvironmentObject private var web: WebModel
    @EnvironmentObject private var usage: UsageTracker
    @EnvironmentObject private var gate: Gate
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Pref.dailyLimit) private var dailyLimit = 0
    @AppStorage(Pref.faceID) private var faceID = false
    @State private var showSettings = false
    @State private var showInsights = false
    @EnvironmentObject private var stats: StatsStore

    private let tick = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var limitReached: Bool {
        dailyLimit > 0 && usage.secondsToday >= usage.allowanceToday(limitMinutes: dailyLimit)
    }

    var body: some View {
        ZStack {
            WebView(model: web)
                .ignoresSafeArea(.keyboard)
                .overlay(alignment: .trailing) { sideTabs }

            if gate.needsPause {
                PauseView(messagesOnly: Pref.messagesOnlyNow) { path in
                    if let path { web.navigate(path) } else { web.goHome() }
                    withAnimation { gate.needsPause = false }
                }
                .transition(.opacity)
            }
            if limitReached {
                LimitView(limitMinutes: dailyLimit)
            }
            if faceID && (gate.needsUnlock || scenePhase != .active) {
                LockView()
            }
        }
        .sheet(isPresented: $showInsights) {
            InsightsView()
                .environmentObject(stats)
                .environmentObject(usage)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.large])
        }
        #if DEBUG
        .onAppear { if CommandLine.arguments.contains("-showInsights") { showInsights = true } }
        #endif
        .onReceive(tick) { _ in
            usage.objectWillChange.send() // re-checks the daily limit
            web.refreshTimeBasedMode()   // quiet hours start and end with the clock
        }
        .onOpenURL { url in
            // closegram://go?path=/direct/inbox/ opens a page. Handy for testing.
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            if url.host == "go", let path = value {
                web.navigate(path)
            }
        }
    }

    /// The tabs on the right edge: a back button on deeper pages, and settings.
    private var sideTabs: some View {
        VStack(spacing: 8) {
            if web.showsBackButton {
                sideTab("chevron.left", label: "Back") { web.goBack() }
            }
            sideTab("slider.horizontal.3", label: "Settings") { showSettings = true }
        }
        .animation(.easeInOut(duration: 0.2), value: web.showsBackButton)
    }

    private func sideTab(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 44)
                .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10))
        }
        .opacity(0.7)
        .accessibilityLabel(label)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var web: WebModel
    @EnvironmentObject private var usage: UsageTracker
    @Environment(\.dismiss) private var dismiss

    // Feed
    @AppStorage(Pref.blockReels) private var blockReels = true
    @AppStorage(Pref.blockExplore) private var blockExplore = true
    @AppStorage(Pref.hideSuggested) private var hideSuggested = true
    @AppStorage(Pref.hideFeedReels) private var hideFeedReels = true
    @AppStorage(Pref.followingOnly) private var followingOnly = false
    @AppStorage(Pref.feedCap) private var feedCap = 0
    @AppStorage(Pref.stopAtSeen) private var stopAtSeen = false
    @AppStorage(Pref.hideLikes) private var hideLikes = false
    @AppStorage(Pref.hideStories) private var hideStories = false
    // Messages
    @AppStorage(Pref.messagesOnly) private var messagesOnly = false
    @AppStorage(Pref.quietHours) private var quietHours = false
    @AppStorage(Pref.quietStart) private var quietStart = 22
    @AppStorage(Pref.quietEnd) private var quietEnd = 7
    // Opening
    @AppStorage(Pref.pauseOnOpen) private var pauseOnOpen = false
    @AppStorage(Pref.dailyLimit) private var dailyLimit = 0
    @AppStorage(Pref.faceID) private var faceID = false
    // Look
    @AppStorage(Pref.grayscale) private var grayscale = false

    @State private var confirmClear = false
    @State private var showInsights = false
    @EnvironmentObject private var stats: StatsStore
    @StateObject private var lock = LockModel()

    /// Settings that change the injected script. Changing any of them reloads the page.
    private var scriptSettings: [Int] {
        [blockReels, blockExplore, hideSuggested, hideFeedReels, followingOnly, stopAtSeen, hideLikes, hideStories,
         messagesOnly, quietHours, grayscale].map { $0 ? 1 : 0 } + [feedCap, quietStart, quietEnd]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today") {
                    LabeledContent("Time in app", value: formatted(usage.secondsToday))
                    if dailyLimit > 0 {
                        LabeledContent("Daily limit", value: "\(dailyLimit) min")
                    }
                    Button {
                        showInsights = true
                    } label: {
                        Label("See your week", systemImage: "chart.bar.fill")
                    }
                }

                Section {
                    Toggle("Following only, newest first", isOn: $followingOnly)
                    Toggle("Hide suggested posts and ads", isOn: $hideSuggested)
                    Picker("Stop the feed after", selection: $feedCap) {
                        Text("Off").tag(0)
                        ForEach([10, 20, 30, 50], id: \.self) { Text("\($0) posts").tag($0) }
                    }
                    Toggle("Stop at posts I've already seen", isOn: $stopAtSeen)
                    Toggle("Hide likes and counts", isOn: $hideLikes)
                    Toggle("Hide stories bar", isOn: $hideStories)
                } header: {
                    Text("Feed")
                } footer: {
                    Text("\"Stop at posts I've already seen\" works best with Following only, where the feed is in order.")
                }

                Section {
                    Toggle("Block the Reels tab", isOn: $blockReels)
                    Toggle("Hide reels in the feed", isOn: $hideFeedReels)
                    Toggle("Hide Explore grid", isOn: $blockExplore)
                } header: {
                    Text("Blocked")
                } footer: {
                    Text("A reel someone sends you still opens, as a single video with nothing to swipe to.")
                }

                Section {
                    Toggle("Messages only", isOn: $messagesOnly)
                    Toggle("Quiet hours", isOn: $quietHours)
                    if quietHours {
                        Picker("From", selection: $quietStart) {
                            ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                        }
                        Picker("Until", selection: $quietEnd) {
                            ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                        }
                    }
                } header: {
                    Text("Messages")
                } footer: {
                    Text("Messages only hides the feed, Explore and profiles, and opens straight to your inbox. Quiet hours switch it on between the times you pick.")
                }

                Section {
                    Toggle("Pause before opening", isOn: $pauseOnOpen)
                    Picker("Daily limit", selection: $dailyLimit) {
                        Text("Off").tag(0)
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Toggle("Lock with Face ID", isOn: $faceID)
                } header: {
                    Text("Opening")
                } footer: {
                    Text("The pause asks what you're here for and waits 5 seconds. Past the daily limit you can unlock more time by typing a sentence or waiting a minute.")
                }

                InstaLockSection(lock: lock)

                Section("Look") {
                    Toggle("Grayscale", isOn: $grayscale)
                }

                Section {
                    Button("Go to home feed") {
                        web.goHome()
                        dismiss()
                    }
                    Button("Sign out and clear data", role: .destructive) {
                        confirmClear = true
                    }
                }
            }
            .navigationTitle("CloseGram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showInsights) {
                InsightsView()
                    .environmentObject(stats)
                    .environmentObject(usage)
            }
            .familyActivityPicker(isPresented: $lock.showPicker, selection: $lock.selection)
            .onChange(of: scriptSettings) { _, _ in
                web.applySettings()
            }
            .confirmationDialog("Sign out of Instagram and delete all saved site data?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Sign out and clear", role: .destructive) {
                    web.clearAllData()
                    dismiss()
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "am" : "pm")"
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
