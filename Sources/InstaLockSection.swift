import SwiftUI
import FamilyControls

/// Settings for locking the real Instagram app with Screen Time.
struct InstaLockSection: View {
    @State private var isOn = LockStore.isOn
    @State private var selection = LockStore.selection
    @State private var unlockedUntil = LockStore.unlockedUntil
    @State private var showPicker = false
    @State private var message: String?

    private var hasApps: Bool { !selection.applicationTokens.isEmpty }

    var body: some View {
        Section {
            Toggle("Lock the Instagram app", isOn: Binding(get: { isOn }, set: setOn))
            if isOn {
                Button(hasApps ? "Change locked apps (\(selection.applicationTokens.count))" : "Choose the Instagram app") {
                    showPicker = true
                }
                if let until = unlockedUntil, until > Date() {
                    LabeledContent("Unlocked until", value: until.formatted(date: .omitted, time: .shortened))
                    Button("Lock again now") {
                        LockStore.lockAgainNow()
                        unlockedUntil = nil
                    }
                } else if hasApps {
                    Button("Unlock for \(LockStore.unlockMinutes) minutes") { unlock() }
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Instagram app")
        } footer: {
            Text("Puts a Screen Time block on the real Instagram app so you use CloseGram instead. When you need the app, for example to post a reel, unlock it for \(LockStore.unlockMinutes) minutes and it locks again by itself.")
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { _, newValue in
            LockStore.selection = newValue
            LockStore.sync()
        }
    }

    private func setOn(_ on: Bool) {
        message = nil
        guard on else {
            isOn = false
            LockStore.isOn = false
            LockStore.lockAgainNow() // stops any timed unlock, then clears the shield
            unlockedUntil = nil
            return
        }
        Task { @MainActor in
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                isOn = true
                LockStore.isOn = true
                LockStore.sync()
                if !hasApps { showPicker = true }
            } catch {
                message = "CloseGram needs Screen Time permission to lock Instagram. Try again, and tap Continue when iPhone asks."
            }
        }
    }

    private func unlock() {
        do {
            try LockStore.unlockForAWhile()
            unlockedUntil = LockStore.unlockedUntil
        } catch {
            message = "Couldn't unlock: \(error.localizedDescription)"
        }
    }
}
