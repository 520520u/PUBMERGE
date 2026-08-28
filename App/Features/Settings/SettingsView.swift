import SwiftUI

struct SettingsView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(LanguageController.self) private var language
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        Form {
            Section("language_title") {
                Picker("language_title", selection: Bindable(language).language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.menuTitle).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Text("language_default_note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("privacy_title") {
                Text("privacy_body")
                Toggle("encrypt_temp", isOn: Bindable(session).encryptTemporaries)
                Button("clear_temp", role: .destructive) {
                    session.clearTemporaryFiles()
                }
                Button("reset_session", role: .destructive) {
                    session.reset()
                    dismiss()
                }
            }
            Section("legal_title") {
                Text("legal_body")
                Text("trademark_body")
                    .foregroundStyle(.secondary)
            }
            Section("about_title") {
                LabeledContent("app_name", value: "PubMerge")
                LabeledContent("schema_current", value: "16")
                Text("about_body")
            }
            if layout.isCompactWidth {
                Section {
                    Button("settings_back_home") {
                        session.returnToHome()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("nav_settings")
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("settings_done") {
                    dismiss()
                }
            }
            if layout.isRegularWidth {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings_back_home") {
                        session.returnToHome()
                        dismiss()
                    }
                }
            }
        }
    }
}
