import SwiftUI
import UniformTypeIdentifiers

// AppKit owns only the window lifetime: SwiftUI scene launch suppression requires macOS 15.
// On every supported OS this window is created on demand and its SwiftUI content released on close.
@MainActor final class WordbookWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(store: WordbookStore, settings: LookupSettings) {
        if window == nil {
            let controller = NSHostingController(rootView: WordbookView(store: store, settings: settings))
            let window = NSWindow(contentViewController: controller)
            window.title = "Wordbook"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 960, height: 680))
            window.minSize = NSSize(width: 760, height: 550)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window?.delegate = nil
        window = nil
    }
}

extension UTType {
    static let glossaWordbook = UTType(exportedAs: "com.glossa.wordbook", conformingTo: .json)
}

struct WordbookDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.glossaWordbook, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw WordbookError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct WordbookView: View {
    let store: WordbookStore
    let settings: LookupSettings
    @State private var search = ""
    @State private var showTrash = false
    @State private var groups: [WordbookGroup] = []
    @State private var selectedID: String?
    @State private var sheet: WordbookSheet?
    @State private var importing = false
    @State private var exporting = false
    @State private var processingFile = false
    @State private var document: WordbookDocument?
    @State private var fileError: String?
    @State private var fileNotice: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your reading, remembered", systemImage: "bookmark")
                        .font(.headline)
                    TextField("Search words, context, and notes", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Picker("Collection", selection: $showTrash) {
                        Text("Saved").tag(false)
                        Text("Recently Deleted").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Collection")
                }
                .padding(16)
                List(groups, selection: $selectedID) { group in
                    WordbookRow(group: group).tag(group.id)
                }
                .listStyle(.sidebar)
                .overlay {
                    if groups.isEmpty && !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
                Divider()
                HStack {
                    if store.isBusy || processingFile { ProgressView().controlSize(.small) }
                    Text("\(groups.count) words")
                    Spacer()
                    Menu {
                        Button("Import Wordbook…") { importing = true }
                        Button("Export Backup…") { prepareExport() }
                    } label: {
                        Label("Import and Export", systemImage: "square.and.arrow.up")
                    }
                    .labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
                    .disabled(!store.canWrite || processingFile)
                    Button("Sync & Backups", systemImage: "icloud") { sheet = .sync }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Sync & Backups")
                }
                .font(.caption).foregroundStyle(.secondary).padding(14)
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 380)
        } detail: {
            VStack(spacing: 0) {
                if let message = fileError ?? store.error {
                    HStack(alignment: .top) {
                        Label(message, systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Retry") { Task { fileError = nil; await store.refresh() } }
                    }
                    .foregroundStyle(.orange).padding()
                    Divider()
                } else if let message = fileNotice ?? store.notice {
                    HStack {
                        Label(message, systemImage: "checkmark.circle")
                        Spacer()
                        Button("Dismiss") { fileNotice = nil; store.clearMessage() }
                    }
                    .font(.callout).padding()
                    Divider()
                }
                if let group = groups.first(where: { $0.id == selectedID }) {
                    WordbookDetail(group: group, store: store) { entry in sheet = .edit(entry) }
                } else if store.isBusy && !store.isLoaded {
                    ProgressView("Opening wordbook…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label(showTrash ? "Nothing here to restore" : "Keep the words that stay with you", systemImage: "book.closed")
                    } description: {
                        Text(showTrash ? "Deleted encounters stay here until you restore them."
                             : "Save a lookup with the bookmark button. Its meaning, context, and memory note will live here.")
                    } actions: {
                        if !showTrash { Button("Import Wordbook…") { importing = true }.disabled(!store.canWrite) }
                    }
                }
            }
            .frame(minWidth: 400)
        }
        .navigationTitle("Wordbook")
        .frame(minWidth: 760, minHeight: 520)
        .task { await store.refresh(); updateGroups() }
        .onChange(of: store.entries) { updateGroups() }
        .onChange(of: search) { updateGroups() }
        .onChange(of: showTrash) { selectedID = nil; updateGroups() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit(let entry): WordbookEditor(entry: entry, store: store, settings: settings)
            case .sync: WordbookSyncView(store: store)
            case .importBackup(let backup): WordbookImportView(backup: backup, store: store)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.glossaWordbook, .json]) { result in
            switch result {
            case .success(let url): prepareImport(url)
            case .failure: fileError = "The file could not be opened. Your wordbook was not changed."
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .glossaWordbook,
                      defaultFilename: "Glossa Wordbook \(Date().formatted(.iso8601.year().month().day()))") { result in
            document = nil
            switch result {
            case .success: fileNotice = "Backup exported, including deleted encounters. Keep a dated copy for recovery."
            case .failure: fileError = "The backup could not be written. Choose another location and try again."
            }
        }
    }

    private func updateGroups() {
        groups = store.groups(search: search, trash: showTrash)
        if !groups.contains(where: { $0.id == selectedID }) { selectedID = groups.first?.id }
    }

    private func prepareImport(_ url: URL) {
        processingFile = true
        fileError = nil
        Task {
            defer { processingFile = false }
            do {
                let backup = try await Task.detached { try WordbookBackup.read(url) }.value
                sheet = .importBackup(backup)
            } catch {
                fileError = (error as? WordbookError)?.localizedDescription ?? "The backup could not be read. Nothing was imported."
            }
        }
    }

    private func prepareExport() {
        processingFile = true
        fileError = nil
        Task {
            defer { processingFile = false }
            await store.refresh()
            guard store.canWrite else { return }
            let entries = store.entries
            do {
                let data = try await Task.detached { try WordbookBackup(entries: entries).encoded() }.value
                document = WordbookDocument(data: data)
                exporting = true
            } catch {
                fileError = (error as? WordbookError)?.localizedDescription ?? "The backup could not be prepared. Your wordbook was not changed."
            }
        }
    }
}

private enum WordbookSheet: Identifiable {
    case edit(WordbookEntry), sync, importBackup(WordbookBackup)
    var id: String {
        switch self {
        case .edit(let entry): entry.id.uuidString
        case .sync: "sync"
        case .importBackup: "import"
        }
    }
}

private struct WordbookRow: View {
    let group: WordbookGroup
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(verbatim: group.latest.term).font(.headline).lineLimit(1)
                Spacer()
                if group.entries.count > 1 {
                    Text("\(group.entries.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(verbatim: group.latest.meaningMarkdown.isEmpty ? group.latest.context : group.latest.meaningMarkdown)
                .lineLimit(2).font(.callout).foregroundStyle(.secondary)
            Text(group.latest.createdAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct WordbookDetail: View {
    let group: WordbookGroup
    let store: WordbookStore
    let edit: (WordbookEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: group.latest.term).font(.system(.largeTitle, design: .serif)).textSelection(.enabled)
                    Text("\(group.entries.count) saved encounters · \(languageName(group.latest.sourceLanguage))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(group.entries) { entry in
                    WordbookEncounter(entry: entry, store: store, edit: edit)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WordbookEncounter: View {
    let entry: WordbookEntry
    let store: WordbookStore
    let edit: (WordbookEntry) -> Void
    @State private var deleting = false
    @State private var originalExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(entry.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                if let source = entry.sourceApplication { Text(verbatim: "· \(source)") }
                Spacer(minLength: 8)
                Text(verbatim: languageName(entry.targetLanguage))
            }
            .font(.caption).foregroundStyle(.secondary)

            if !entry.context.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHEN YOU FOUND IT").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: entry.context).textSelection(.enabled)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }
            if !entry.meaningMarkdown.isEmpty { WordbookMarkdown(text: entry.meaningMarkdown) }
            if !entry.memoryHook.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    Text(verbatim: entry.memoryHook).textSelection(.enabled)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.07), in: .rect(cornerRadius: 10))
            }
            DisclosureGroup("Original AI lookup", isExpanded: $originalExpanded) {
                WordbookMarkdown(text: entry.answerMarkdown).padding(.top, 8)
            }
            HStack {
                if entry.deletedAt == nil {
                    Button(entry.memoryHook.isEmpty ? "Add Context & AI Note…" : "Edit Note…", systemImage: "square.and.pencil") { edit(entry) }
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
                        .labelStyle(.iconOnly).help("Move encounter to Recently Deleted")
                } else {
                    Label("Deleted encounters are retained for recovery", systemImage: "trash")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore") { Task { await store.setDeleted(entry, deleted: false) } }
                }
            }
            .disabled(!store.canWrite)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.45)) }
        .onAppear { originalExpanded = entry.meaningMarkdown.isEmpty }
        .confirmationDialog("Delete this encounter?", isPresented: $deleting) {
            Button("Move to Recently Deleted", role: .destructive) {
                Task { await store.setDeleted(entry, deleted: true) }
            }
        } message: {
            Text("This deletion also syncs when iCloud is enabled. You can restore the encounter from Recently Deleted.")
        }
    }
}

struct WordbookMarkdown: View {
    let text: String
    var body: some View {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
             ?? AttributedString(text))
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func languageName(_ code: String) -> String {
    FlowLanguage(rawValue: code)?.name ?? code
}

@MainActor @Observable
private final class WordbookDraft {
    var context: String
    var meaning: String
    var memoryHook: String
    var error: String?
    var isGenerating = false
    @ObservationIgnored private var output = ""

    init(entry: WordbookEntry) {
        context = entry.context
        meaning = entry.meaningMarkdown
        memoryHook = entry.memoryHook
    }

    func generate(entry: WordbookEntry, configuration: APIConfiguration) async {
        isGenerating = true
        error = nil
        output = ""
        defer { isGenerating = false; output = "" }
        do {
            var input = entry
            input.context = context
            _ = try input.validated()
            let prompt = try WordbookMemoryNote.prompt(entry: input)
            let request = try ChatCompletionsClient.request(configuration: configuration,
                key: APIKeyStore.read(for: configuration), prompt: prompt)
            try await ChatCompletionsClient.stream(request: request) { [weak self] text in
                await self?.receive(text)
            }
            try Task.checkCancellation()
            let note = try WordbookMemoryNote.decode(output)
            meaning = note.meaning
            memoryHook = note.memoryHook
        } catch {
            if !Task.isCancelled {
                self.error = (error as? APIError)?.localizedDescription ?? "AI could not create a valid note. Your draft has been kept."
            }
        }
    }

    private func receive(_ text: String) { output = text }
}

private struct WordbookEditor: View {
    let entry: WordbookEntry
    let store: WordbookStore
    let settings: LookupSettings
    @State private var draft: WordbookDraft
    @State private var flowID: UUID?
    @State private var generation: UUID?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(entry: WordbookEntry, store: WordbookStore, settings: LookupSettings) {
        self.entry = entry
        self.store = store
        self.settings = settings
        _draft = State(initialValue: WordbookDraft(entry: entry))
        let matches = settings.flows.filter { $0.target.rawValue == entry.targetLanguage }
        _flowID = State(initialValue: matches.count == 1 ? matches[0].id : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: entry.term).font(.title2)
            Text("Keep the meaning. Remember the moment.").foregroundStyle(.secondary)
            Form {
                Section("Your context") {
                    TextField("Original sentence (optional)", text: $draft.context, axis: .vertical).lineLimit(3...6)
                    Text("Add the actual sentence yourself. Glossa does not capture surrounding text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Memory note") {
                    TextField("One-sentence meaning", text: $draft.meaning, axis: .vertical).lineLimit(2...4)
                    TextField("Memory hook or useful contrast", text: $draft.memoryHook, axis: .vertical).lineLimit(2...4)
                }
                Section("AI assistance") {
                    Picker("Use provider from flow", selection: $flowID) {
                        Text("Choose a flow").tag(nil as UUID?)
                        ForEach(settings.flows) { flow in
                            Text("\(flow.title) · \(settings.providerName(flow.provider))").tag(Optional(flow.id))
                        }
                    }
                    Text("Create Note sends this word, your context, and up to 8,000 characters of its saved lookup to the chosen provider. It may incur API charges. The response stays in \(languageName(entry.targetLanguage)). Review it before saving.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(draft.isGenerating || saving)
            if let error = draft.error { Text(verbatim: error).foregroundStyle(.orange) }
            HStack {
                if draft.isGenerating {
                    ProgressView().controlSize(.small)
                    Button("Stop") { generation = nil }
                } else {
                    Button("Create AI Note", systemImage: "sparkles") { generation = UUID() }
                        .disabled(flowID == nil || !settings.canEdit || saving)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(draft.isGenerating || saving || !store.canWrite)
            }
        }
        .padding(24).frame(width: 600, height: 650)
        .interactiveDismissDisabled(saving)
        .task(id: generation) {
            guard generation != nil, let flow = settings.flows.first(where: { $0.id == flowID }) else { return }
            var configuration = settings.configuration(for: flow.provider)
            if !flow.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { configuration.model = flow.model }
            await draft.generate(entry: entry, configuration: configuration)
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            var updated = entry
            updated.context = draft.context
            updated.meaningMarkdown = draft.meaning
            updated.memoryHook = draft.memoryHook
            updated.updatedAt = max(Date(), entry.updatedAt.addingTimeInterval(0.001))
            if await store.save(updated, replacing: entry) { dismiss() }
            else { draft.error = store.error ?? "Wait for the wordbook to finish saving, then try again." }
        }
    }
}

private struct WordbookSyncView: View {
    let store: WordbookStore
    @State private var confirmingEnable = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Sync & Backups", systemImage: "icloud").font(.title2)
            Form {
                Section("iCloud") {
                    Toggle("Sync wordbook with iCloud", isOn: Binding(get: { store.syncEnabled }, set: { enabled in
                        if enabled { confirmingEnable = true } else { store.setSyncEnabled(false) }
                    }))
                    .disabled(WordbookStore.signedCloudIdentifier == nil && !store.syncEnabled)
                    Text(verbatim: store.syncStatus).font(.callout).foregroundStyle(.secondary)
                    if store.needsRestart {
                        Text("Quit and reopen Glossa to apply this change. The current sync setting remains active until then; your local records stay on this Mac.")
                            .foregroundStyle(.orange)
                    }
                    if WordbookStore.signedCloudIdentifier == nil {
                        Text("iCloud is unavailable in this build. Use a signed Glossa build with iCloud enabled. Local saving, import, and export remain available.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Keep a backup") {
                    Text("iCloud sync includes deletions. Export a dated backup from the sidebar’s Import and Export menu for independent recovery; you can save it in iCloud Drive.")
                    Text("Backups include your words, original AI results, context, notes, dates, and deleted encounters. API keys and app settings are excluded. Files are readable JSON and are not encrypted by Glossa.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 520, height: 480)
        .confirmationDialog("Enable iCloud sync?", isPresented: $confirmingEnable) {
            Button("Enable iCloud") { store.setSyncEnabled(true) }
        } message: {
            Text("Saved words, source app names, original text, AI results, and memory notes will sync through your private iCloud database. Deletions sync too. The change takes effect after restarting Glossa.")
        }
    }
}

private struct WordbookImportView: View {
    let backup: WordbookBackup
    let store: WordbookStore
    @State private var importing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Merge Wordbook", systemImage: "square.and.arrow.down").font(.title2)
            Text("\(backup.entries.count) records · exported \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))")
            Text("New records will be added. For the same record, only a newer version is applied. Identical records are skipped. Different encounters with the same word are kept together.")
            Text("The backup includes \(backup.entries.filter { $0.deletedAt != nil }.count) deleted encounters. Newer deletion markers also apply. Restore them from Recently Deleted if needed.")
                .font(.callout).foregroundStyle(.secondary)
            if store.activeCloudIdentifier != nil {
                Label("Imported changes will also sync to iCloud.", systemImage: "icloud").font(.callout)
            }
            if let error = store.error { Text(verbatim: error).foregroundStyle(.orange) }
            HStack {
                if importing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(importing)
                Button("Merge Records") {
                    importing = true
                    Task {
                        let imported = await store.importBackup(backup)
                        importing = false
                        if imported { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction).disabled(importing || !store.canWrite)
            }
        }
        .padding(24).frame(width: 490)
        .interactiveDismissDisabled(importing)
    }
}
