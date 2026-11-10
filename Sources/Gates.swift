import SwiftUI

/// "What are you here for?" shown on opening, with a short wait before the choices unlock.
struct PauseView: View {
    let messagesOnly: Bool
    let choose: (String?) -> Void // a path to open, or nil for the usual start page

    @State private var left = 5
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct Choice: Identifiable {
        let id: String
        let icon: String
        let path: String?
    }

    private var choices: [Choice] {
        let messages = Choice(id: "Messages", icon: "paperplane", path: "/direct/inbox/")
        if messagesOnly { return [messages] }
        return [
            messages,
            Choice(id: "Post something", icon: "plus.app", path: nil),
            Choice(id: "Look someone up", icon: "magnifyingglass", path: "/explore/"),
            Choice(id: "Browse my feed", icon: "house", path: nil),
        ]
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("What are you here for?")
                .font(.title2.bold())
            Text(left > 0 ? "Take a breath. \(left)" : (messagesOnly ? "It's messages only right now." : "Pick one."))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            VStack(spacing: 12) {
                ForEach(choices) { choice in
                    Button {
                        choose(choice.path)
                    } label: {
                        Label(choice.id, systemImage: choice.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(left > 0)
                    .opacity(left > 0 ? 0.4 : 1)
                }
            }
            Spacer()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onReceive(timer) { _ in
            if left > 0 { withAnimation { left -= 1 } }
        }
    }
}

/// "Done for today", shown once the daily limit is used up.
struct LimitView: View {
    @EnvironmentObject private var usage: UsageTracker
    let limitMinutes: Int

    static let sentence = "I choose to spend more time on Instagram"
    @State private var typed = ""
    @State private var waitLeft: Int?
    @FocusState private var typing: Bool
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Done for today")
                .font(.title.bold())
            Text("You've spent \(Int(usage.secondsToday) / 60) min on Instagram today. Your limit is \(limitMinutes) min.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("For 15 more minutes, type:")
                    .font(.subheadline)
                Text(Self.sentence)
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
                TextField("Type it here", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($typing)
                    .onChange(of: typed) { _, value in
                        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if clean == Self.sentence.lowercased() {
                            typed = ""
                            typing = false
                            usage.addBonus(minutes: 15)
                        }
                    }
            }
            Button {
                waitLeft = 60
            } label: {
                Text(waitLeft.map { "Waiting… \($0) s" } ?? "Or wait 60 seconds for 5 more minutes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(waitLeft != nil)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onReceive(timer) { _ in
            guard let left = waitLeft else { return }
            if left <= 1 {
                waitLeft = nil
                usage.addBonus(minutes: 5)
            } else {
                waitLeft = left - 1
            }
        }
    }
}

/// Covers the app until Face ID (or the passcode) unlocks it. Also hides the content in the app switcher.
struct LockView: View {
    @EnvironmentObject private var gate: Gate
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial)
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 36))
                Text("CloseGram is locked")
                    .font(.headline)
                if gate.needsUnlock {
                    Button("Unlock") { gate.authenticate() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .ignoresSafeArea()
        .task(id: scenePhase) {
            // Ask once automatically; after a cancel, the Unlock button asks again.
            if scenePhase == .active && gate.needsUnlock && !gate.autoTried {
                gate.autoTried = true
                gate.authenticate()
            }
        }
    }
}
