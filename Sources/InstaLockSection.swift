import SwiftUI
import FamilyControls

/// State for the Instagram app lock. Owned by the settings screen, so the app picker
/// is attached there and isn't dismissed when the list redraws a row.
@MainActor
final class LockModel: ObservableObject {
    @Published var isOn = LockStore.isOn
    @Published var selection = LockStore.selection {
        didSet {
            LockStore.selection = selection
            LockStore.sync()
        }
    }
    @Published var unlockedUntil = LockStore.unlockedUntil
    @Published var showPicker = false
    @Published var message: String?

    var hasApps: Bool { !selection.applicationTokens.isEmpty }

    func setOn(_ on: Bool) {
        message = nil
        guard on else {
            isOn = false
            LockStore.isOn = false
            LockStore.lockAgainNow() // stops any timed unlock, then clears the shield
            unlockedUntil = nil
            return
        }
        Task {
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

    func unlock() {
        do {
            try LockStore.unlockForAWhile()
            unlockedUntil = LockStore.unlockedUntil
        } catch {
            message = "Couldn't unlock: \(error.localizedDescription)"
        }
    }

    func lockAgain() {
        LockStore.lockAgainNow()
        unlockedUntil = nil
    }
}

/// Settings for locking the real Instagram app with Screen Time.
struct InstaLockSection: View {
    @ObservedObject var lock: LockModel

    var body: some View {
        Section {
            Toggle("Lock the Instagram app", isOn: Binding(get: { lock.isOn }, set: { lock.setOn($0) }))
            if lock.isOn {
                Button(lock.hasApps ? "Change locked apps (\(lock.selection.applicationTokens.count))" : "Choose the Instagram app") {
                    lock.showPicker = true
                }
                if let until = lock.unlockedUntil, until > Date() {
                    LabeledContent("Unlocked until", value: until.formatted(date: .omitted, time: .shortened))
                    Button("Lock again now") { lock.lockAgain() }
                } else if lock.hasApps {
                    Button("Unlock for \(LockStore.unlockMinutes) minutes") { lock.unlock() }
                }
            }
            if let message = lock.message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Instagram app")
        } footer: {
            Text("Puts a Screen Time block on the real Instagram app so you use CloseGram instead. The block is on whenever you're outside CloseGram. In the list, open Social or search for Instagram. When you need the app, for example to post a reel, unlock it for \(LockStore.unlockMinutes) minutes and it locks again by itself.")
        }
    }
}
