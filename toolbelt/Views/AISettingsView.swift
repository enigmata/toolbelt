import SwiftUI

/// Choose the AI model/service powering lookups and suggestions, and manage
/// API keys for cloud providers. Keys live in the Keychain.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var service = AIService.shared
    @State private var selectedID: AIProviderID = AIService.shared.selectedProviderID
    @State private var claudeKey = KeychainHelper.read(for: .claude) ?? ""
    @State private var geminiKey = KeychainHelper.read(for: .gemini) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $selectedID) {
                        ForEach(AIProviderID.allCases) { id in
                            Text(id.displayName).tag(id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("AI Provider")
                } footer: {
                    Text("Powers tool lookups, photo identification of packaging, link suggestions, and companion-tool ideas. The Apple on-device model is free, private, and works offline; cloud providers need an API key and a connection. Identification lookups can use a different provider — the Add Tool form asks once, remembers your choice, and shows a Lookup Provider picker to change it any time.")
                }

                Section("Status") {
                    ForEach(AIProviderID.allCases) { id in
                        if let provider = service.provider(for: id) {
                            LabeledContent(id.displayName) {
                                if let issue = service.readinessIssue(for: provider) {
                                    Label(issue, systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                        .labelStyle(.titleAndIcon)
                                } else {
                                    Label("Ready", systemImage: "checkmark.circle")
                                        .foregroundStyle(.green)
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section {
                    SecureField("Anthropic API Key", text: $claudeKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { KeychainHelper.save(claudeKey, for: .claude) }
                } header: {
                    Text("Claude")
                } footer: {
                    Text("From console.anthropic.com. Stored in the Keychain.")
                }

                Section {
                    SecureField("Google AI API Key", text: $geminiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { KeychainHelper.save(geminiKey, for: .gemini) }
                } header: {
                    Text("Gemini")
                } footer: {
                    Text("From aistudio.google.com. Stored in the Keychain.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("AI Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                }
            }
        }
    }

    private func saveAndDismiss() {
        KeychainHelper.save(claudeKey, for: .claude)
        KeychainHelper.save(geminiKey, for: .gemini)
        AIService.shared.selectedProviderID = selectedID
        dismiss()
    }
}
