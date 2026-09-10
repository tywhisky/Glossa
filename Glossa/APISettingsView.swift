import SwiftUI

struct APISettingsView: View {
    let settings: LookupSettings

    var body: some View {
        Form {
            Section {
                ForEach(AIProvider.allCases) { provider in
                    ProviderSettingsEditor(provider: provider, settings: settings)
                }
            } header: {
                Text("AI Providers")
            } footer: {
                Text("Each provider has its own connection and default model. API keys stay in this Mac’s Keychain, separately for each base URL. Saving does not send a request.")
            }
        }
        .formStyle(.grouped)
        .disabled(!settings.canEdit)
    }
}

private struct ProviderSettingsEditor: View {
    private static let savedKeySentinel = "saved api key"

    let provider: AIProvider
    let settings: LookupSettings
    // This is an editable draft; only Save changes the configuration used by lookups.
    @State private var configuration: APIConfiguration
    @State private var key = ""
    @State private var message: String?
    @State private var keyStatus = "Checking key…"
    @State private var isSaving = false
    @State private var isExpanded = false
    @State private var confirmsDelete = false
    @FocusState private var isKeyFocused: Bool

    init(provider: AIProvider, settings: LookupSettings) {
        self.provider = provider
        self.settings = settings
        _configuration = State(initialValue: settings.configuration(for: provider))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Group {
                Text(provider.setupNote).font(.caption).foregroundStyle(.secondary)
                if provider != .openAI && provider != .deepSeek {
                    Text("Documentation-reviewed; not verified with a live API key.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Base URL", text: $configuration.baseURL)
                    .autocorrectionDisabled()
                    .onChange(of: configuration.baseURL) { _, _ in
                        key = ""
                        keyStatus = "Checking key…"
                        message = nil
                    }
                TextField("Default model", text: $configuration.model)
                    .autocorrectionDisabled()
                SecureField("API key", text: $key, prompt: Text("Leave blank to keep saved key"))
                    .autocorrectionDisabled()
                    .focused($isKeyFocused)
                    .accessibilityHint(keyStatus == "Key saved" ? "A key is saved. Leave blank to keep it." : "Enter an API key.")
                    .onChange(of: isKeyFocused) { _, focused in
                        if focused, key == Self.savedKeySentinel {
                            key = ""
                        } else if !focused, key.isEmpty, keyStatus == "Key saved" {
                            key = Self.savedKeySentinel
                        }
                    }
                HStack {
                    Button("Save") { save() }
                    Button("Restore Defaults") { configuration = provider.defaults; message = nil }
                    Spacer()
                    Button("Delete Key", role: .destructive) { confirmsDelete = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                .padding(.top, 8)
                if let message { Text(verbatim: message).font(.caption).textSelection(.enabled) }
            }
            .disabled(isSaving)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.providerName(provider))
                    Text(configuration.model).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(configuration != settings.configuration(for: provider) || hasKeyDraft ? "Unsaved changes" : keyStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .task(id: configuration.baseURL) { await refreshKeyStatus() }
        .onDisappear { key = "" }
        .alert("Delete the saved API key?", isPresented: $confirmsDelete) {
            Button("Delete Key", role: .destructive) { deleteKey() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Flows using this base URL will need a new key before they can look up text.")
        }
    }

    private func refreshKeyStatus() async {
        let value = configuration
        let status = await Task.detached {
            do { return try APIKeyStore.containsKey(for: value) ? "Key saved" : "Key required" }
            catch { return "Key unavailable" }
        }.value
        guard !Task.isCancelled else { return }
        keyStatus = status
        if status == "Key saved", key.isEmpty, !isKeyFocused {
            key = Self.savedKeySentinel
        }
    }

    private func save() {
        do {
            let value = try configuration.validated()
            let secret = hasKeyDraft ? key.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            isSaving = true
            message = nil
            Task {
                do {
                    // Keychain can wait for system authorization; keep it off the UI thread.
                    try await Task.detached {
                        if !secret.isEmpty { try APIKeyStore.save(secret, for: value) }
                    }.value
                    try settings.save(value, for: provider)
                    configuration = value
                    key = ""
                    message = "Saved. Flows using the default model will use this configuration."
                    await refreshKeyStatus()
                } catch { message = error.localizedDescription }
                isSaving = false
            }
        } catch { message = error.localizedDescription }
    }

    private func deleteKey() {
        let value = configuration
        isSaving = true
        Task {
            do {
                try await Task.detached { try APIKeyStore.delete(for: value) }.value
                key = ""
                message = "Saved key deleted for this base URL."
                await refreshKeyStatus()
            } catch { message = error.localizedDescription }
            isSaving = false
        }
    }

    private var hasKeyDraft: Bool {
        !key.isEmpty && key != Self.savedKeySentinel
    }
}
