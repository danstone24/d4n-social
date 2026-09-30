import SwiftUI
import UniformTypeIdentifiers

/// One list: a section per platform, then beta filters, tools, audit and
/// settings. Every toggle applies live to the open pages.
struct FiltersView: View {
    private let settings = Settings.shared
    private let rules = RulesStore.shared
    private let shell = Shell.shared

    @State private var pendingImport: Data?
    @State private var showImportChoice = false
    @State private var showFilePicker = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Instagram") {
                    ForEach(Filters.core(for: .instagram)) { FilterRow(spec: $0) }
                }
                Section("X") {
                    ForEach(Filters.core(for: .x)) { FilterRow(spec: $0) }
                }
                Section("More") {
                    NavigationLink {
                        FilterListView(title: "Beta filters", specs: Filters.beta(for: .x),
                                       footer: "New X filters ship here, off by default, until tested. Keys keep their names when promoted.")
                    } label: {
                        LabeledContent("Beta filters", value: "\(Filters.beta(for: .x).count)")
                    }
                    NavigationLink("Mute words") { MuteWordsView() }
                    NavigationLink {
                        BlockLogView()
                    } label: {
                        LabeledContent("Block log", value: "\(settings.blockLog.count)")
                    }
                }
                Section {
                    FilterRow(spec: Filters.spec("auditMode")!)
                    NavigationLink("What was hidden") { AuditView() }
                } header: {
                    Text("Audit")
                } footer: {
                    Text("With audit mode on nothing is hidden. Matches are dimmed, outlined in red and labelled with the filter that caught them. Screenshot that to report a wrong match.")
                }
                Section("Settings") {
                    ShareLink(item: settings.exportJSON(), preview: SharePreview("D4N Social filters")) {
                        Text("Export settings")
                    }
                    Button("Copy settings as JSON") {
                        UIPasteboard.general.string = settings.exportJSON()
                        notice = "Copied"
                    }
                    Button("Import from clipboard") {
                        if let text = UIPasteboard.general.string, !text.isEmpty {
                            pendingImport = Data(text.utf8)
                            showImportChoice = true
                        } else {
                            notice = "The clipboard is empty"
                        }
                    }
                    Button("Import from file") { showFilePicker = true }
                }
                Section {
                    LabeledContent("Rules", value: "v\(rules.version), \(rules.source.rawValue)")
                    if let checked = rules.lastChecked {
                        LabeledContent("Checked", value: checked.formatted(.relative(presentation: .named)))
                    }
                    if let error = rules.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button(rules.checking ? "Checking…" : "Check for rule updates") {
                        Task { await rules.refresh() }
                    }
                    .disabled(rules.checking)
                    Button("Reload Instagram") { shell.tab(.instagram).reload() }
                    Button("Reload X") { shell.tab(.x).reload() }
                    LabeledContent("App", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
                } header: {
                    Text("Rules")
                } footer: {
                    Text("Rule files ship with the app and are refreshed from GitHub on launch. New rules apply on the next page load.")
                }
            }
            .navigationTitle("Filters")
            .confirmationDialog("Import settings", isPresented: $showImportChoice, presenting: pendingImport) { data in
                Button("Replace") { apply(data, mode: .replace) }
                Button("Merge") { apply(data, mode: .merge) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Replace starts from defaults and applies the file. Merge keeps current settings and overlays the file.")
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json, .plainText]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    pendingImport = data
                    showImportChoice = true
                } else {
                    notice = "Could not read that file"
                }
            }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK") {}
            }
        }
    }

    private func apply(_ data: Data, mode: Settings.ImportMode) {
        do {
            let count = try settings.importJSON(data, mode: mode)
            notice = "Imported \(count) settings"
        } catch {
            notice = error.localizedDescription
        }
    }
}

/// A toggle with its description and, once the page has reported, how many
/// elements it has caught.
struct FilterRow: View {
    let spec: FilterSpec
    private let settings = Settings.shared

    var body: some View {
        Toggle(isOn: settings.binding(spec.key)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spec.title)
                    if spec.beta {
                        Text("beta").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        if let platform = spec.platform, let count = settings.count(for: spec.key, platform: platform), count > 0 {
            return "\(spec.detail) · \(count) hidden"
        }
        return spec.detail
    }
}

struct FilterListView: View {
    let title: String
    let specs: [FilterSpec]
    var footer = ""

    var body: some View {
        List {
            Section {
                ForEach(specs) { FilterRow(spec: $0) }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(title)
    }
}

struct MuteWordsView: View {
    private let settings = Settings.shared

    var body: some View {
        List {
            Section {
                FilterRow(spec: Filters.spec("betaMuteWords")!)
            }
            Section {
                TextEditor(text: Binding(get: { settings.muteWordsList }, set: { settings.setMuteWords($0) }))
                    .frame(minHeight: 200)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Words")
            } footer: {
                Text("One word or phrase per line. A post containing any of them is hidden on X.")
            }
        }
        .navigationTitle("Mute words")
    }
}

/// Who the app blocked on X, with undo. Stored on this phone only.
struct BlockLogView: View {
    private let settings = Settings.shared
    private let shell = Shell.shared
    @State private var failure: String?

    var body: some View {
        List {
            if settings.blockLog.isEmpty {
                Text("No blocks yet. The ⃠ button on each X post blocks its author and records it here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.blockLog) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(entry.handle)")
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Unblock") { unblock(entry.handle) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Block log")
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        }
    }

    private func unblock(_ handle: String) {
        Task {
            do {
                try await shell.tab(.x).unblock(handle)
                settings.removeBlock(handle)
            } catch {
                failure = "Unblock failed: \(error.localizedDescription)"
            }
        }
    }
}

/// Hidden counts per filter for the pages currently open.
struct AuditView: View {
    private let settings = Settings.shared

    var body: some View {
        List {
            ForEach(Platform.allCases) { platform in
                Section(platform.title) {
                    let specs = Filters.all.filter { $0.platform == platform }
                    let counted = specs.compactMap { spec -> (FilterSpec, Int)? in
                        guard let count = settings.count(for: spec.key, platform: platform), count > 0 else { return nil }
                        return (spec, count)
                    }
                    if counted.isEmpty {
                        Text("Nothing caught on the open page yet").foregroundStyle(.secondary)
                    }
                    ForEach(counted, id: \.0.key) { spec, count in
                        LabeledContent(spec.title, value: "\(count)")
                    }
                }
            }
        }
        .navigationTitle("What was hidden")
    }
}
