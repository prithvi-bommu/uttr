import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start Uttr at login", isOn: Binding(
                    get: { store.settings.startAtLogin },
                    set: { newValue in
                        try? store.update { $0.startAtLogin = newValue }
                    }
                ))
            }

            Section("Dictation Shortcut") {
                HStack {
                    Text("Current shortcut:")
                    Text(currentHotkeyDisplay)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Button("Change Shortcut…") {
                    }
                }
                Text("The Fn/Globe key is not supported as a shortcut modifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var currentHotkeyDisplay: String {
        let hotkey = store.settings.hotkey
        let h = Hotkey(
            keyCode: hotkey.keyCode,
            modifiers: Set(hotkey.modifiers)
        )
        return h.displayString
    }
}
