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

    init(provider: AIProvider, settings: LookupSettings) {
        self.provider = provider
        self.settings = settings
        _configuration = State(initialValue: settings.configuration(for: provider))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Group {
                TextField("Base URL", text: $configuration.baseURL)
                    .autocorrectionDisabled()
                    .onChange(of: configuration.baseURL) { _, _ in key = ""; message = nil }
                TextField("Default model", text: $configuration.model)
                    .autocorrectionDisabled()
                SecureField("API key", text: $key, prompt: Text("Leave blank to keep saved key"))
                    .autocorrectionDisabled()
                HStack {
                    Button("Save") { save() }
                    Button("Restore Defaults") { configuration = provider.defaults; message = nil }
                    Spacer()
                    Button("Delete Key…", role: .destructive) { confirmsDelete = true }
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
                Text(configuration != settings.configuration(for: provider) || !key.isEmpty ? "Unsaved changes" : keyStatus)
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
    }

    private func save() {
        do {
            let value = try configuration.validated()
            let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
