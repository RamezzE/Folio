import SwiftUI
import Combine
internal import UniformTypeIdentifiers

// MARK: - Apply depth

enum ApplyDepth: String, CaseIterable, Identifiable, Equatable {
    case rootOnly  = "Root only"
    case immediate = "Immediate subfolders"
    case recursive = "All subfolders"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .rootOnly:  return "folder"
        case .immediate: return "folder.badge.plus"
        case .recursive: return "arrow.triangle.branch"
        }
    }
    var help: String {
        switch self {
        case .rootOnly:  return "Apply only to the selected folder itself."
        case .immediate: return "Apply to the selected folder and its direct children."
        case .recursive: return "Apply to every nested subfolder, no matter how deep."
        }
    }
}

// MARK: - Per-folder result

struct FolderIconResult: Identifiable {
    let id = UUID()
    let url: URL
    let iconID: UUID?
    let iconName: String?
    let matchSource: String?
    let color: FolderColor?
    var applied: Bool = false
    var matched: Bool { iconID != nil || color != nil }
    var name: String { url.lastPathComponent }
    var path: String { url.path }
}

// MARK: - Preview inputs (drives .task cancellation)

private struct PreviewInput: Equatable {
    let path: String
    let depth: ApplyDepth
    let ignoreKey: String
}

// MARK: - Pagination

struct PaginationState {
    var currentPage: Int = 1
    let pageSize: Int = 50

    var startIndex: Int { (currentPage - 1) * pageSize }

    func totalPages(for itemCount: Int) -> Int {
        max(1, Int(ceil(Double(itemCount) / Double(pageSize))))
    }

    func pageSlice<T>(_ items: [T]) -> [T] {
        let end = min(startIndex + pageSize, items.count)
        guard startIndex < items.count else { return [] }
        return Array(items[startIndex..<end])
    }
}

// MARK: - Projects scan store
//
// Holds the scan selection and results. It lives at app scope (injected as an
// environment object) so results are preserved when the user navigates away
// from the Apply tab and back, instead of being thrown away each time the view
// is recreated.
@MainActor
final class ProjectsModel: ObservableObject {
    @Published var selectedURL: URL?
    @Published var depth: ApplyDepth = .immediate
    @Published var previewItems: [FolderIconResult] = []
    @Published var hasScanned = false
    @Published var hasApplied = false
    @Published var hasReverted = false
    @Published var isComputingPreview = false
    /// Persists across tab navigation so the progress bar survives switching tabs mid-apply.
    @Published var applyProgress: (done: Int, total: Int)?
    @Published var isPaused = false
    @Published var applyErrors: [ApplyError] = []
    /// Incremented each time apply finishes with errors so the view can show the dialog.
    @Published var applyErrorSignal = 0
    var applyTask: Task<Void, Never>?

    /// Signature (folder + depth) of the last completed scan, used to decide
    /// whether existing results are still valid for the current selection.
    private var scannedSignature: String?

    init() {
        // Restore the last folder + depth from disk once, at launch.
        let savedPath = UserDefaults.standard.string(forKey: "projects.lastFolderPath") ?? ""
        if !savedPath.isEmpty,
           (try? FileManager.default.contentsOfDirectory(atPath: savedPath)) != nil {
            selectedURL = URL(fileURLWithPath: savedPath)
        }
        if let raw = UserDefaults.standard.string(forKey: "projects.lastDepth"),
           let d = ApplyDepth(rawValue: raw) {
            depth = d
        }
    }

    private func currentSignature() -> String { "\(selectedURL?.path ?? "")|\(depth.rawValue)" }

    /// True when results already match the current folder + depth, so no
    /// automatic rescan is needed when re-entering the tab.
    var hasValidResults: Bool { hasScanned && scannedSignature == currentSignature() }

    func markScanned() {
        hasScanned = true
        scannedSignature = currentSignature()
    }

    func cancelApplyTask() {
        applyTask?.cancel()
        applyTask = nil
        applyProgress = nil
        isPaused = false
    }

    func reset() {
        cancelApplyTask()
        selectedURL = nil
        previewItems = []
        hasScanned = false
        hasApplied = false
        hasReverted = false
        isComputingPreview = false
        applyErrors = []
        applyErrorSignal = 0
        scannedSignature = nil
    }
}

// MARK: - ProjectsView

enum ResultFilter: String, CaseIterable {
    case all = "All"
    case matched = "Matched"
    case unmatched = "Unmatched"
}

struct ProjectsView: View {
    @EnvironmentObject var iconManager: IconManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var scan: ProjectsModel

    @AppStorage("projects.lastFolderPath")    private var savedFolderPath: String = ""
    @AppStorage("projects.lastDepth")         private var savedDepth: String = ApplyDepth.immediate.rawValue
    @AppStorage("projects.ignorePatternsV2")  private var savedIgnorePatternsJSON: String = ""

    // Scan selection + results live in `scan` (ProjectsModel) so they persist
    // across tab navigation. These remain view-local transient UI state.
    @State private var previewTask: Task<Void, Never>?
    @State private var projectForPicker: FolderIconResult?
    @State private var searchText = ""
    @State private var resultFilter: ResultFilter = .all
    @State private var showIgnoreManager = false
    @State private var pagination = PaginationState()
    @State private var showErrorDialog = false
    @State private var currentError: ApplyError?

    // Apply state lives in `scan` so it persists across tab navigation and is
    // accessible for cancellation during app termination.
    private var applyProgress: (done: Int, total: Int)? {
        get { scan.applyProgress }
        nonmutating set { scan.applyProgress = newValue }
    }
    private var isPaused: Bool {
        get { scan.isPaused }
        nonmutating set { scan.isPaused = newValue }
    }
    private var applyErrors: [ApplyError] {
        get { scan.applyErrors }
        nonmutating set { scan.applyErrors = newValue }
    }

    // Convenience accessors so the existing body code reads unchanged.
    private var selectedURL: URL? {
        get { scan.selectedURL }
        nonmutating set { scan.selectedURL = newValue }
    }
    private var depth: ApplyDepth {
        get { scan.depth }
        nonmutating set { scan.depth = newValue }
    }
    private var previewItems: [FolderIconResult] {
        get { scan.previewItems }
        nonmutating set { scan.previewItems = newValue }
    }
    private var isComputingPreview: Bool {
        get { scan.isComputingPreview }
        nonmutating set { scan.isComputingPreview = newValue }
    }
    private var hasApplied: Bool {
        get { scan.hasApplied }
        nonmutating set { scan.hasApplied = newValue }
    }
    private var hasReverted: Bool {
        get { scan.hasReverted }
        nonmutating set { scan.hasReverted = newValue }
    }
    private var hasScanned: Bool { scan.hasScanned }

    private let builtInSkips: Set<String> = [
        "node_modules", ".git", "build", ".build", "dist", "DerivedData", ".cache"
    ]

    private var userIgnorePaths: [IgnoredPath] {
        guard !savedIgnorePatternsJSON.isEmpty,
              let data = savedIgnorePatternsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([IgnoredPath].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveIgnorePaths(_ paths: [IgnoredPath]) {
        if let data = try? JSONEncoder().encode(paths),
           let json = String(data: data, encoding: .utf8) {
            savedIgnorePatternsJSON = json
        }
    }

    private var previewInput: PreviewInput {
        PreviewInput(path: selectedURL?.path ?? "", depth: depth,
                     ignoreKey: userIgnorePaths.map { "\($0.pattern):\($0.isRecursive)" }.joined(separator: ","))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                PageHeader(title: "Apply")
                Spacer()
                if selectedURL != nil {
                    Button(action: closeProject) {
                        Label("Close Project", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("Close current project and return to empty state")
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

            // Folder picker
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: selectedURL != nil ? "folder.fill" : "folder.badge.questionmark")
                        .font(.system(size: 20))
                        .foregroundStyle(selectedURL != nil ? Theme.accent : .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let url = selectedURL {
                        Text(url.lastPathComponent).fontWeight(.semibold)
                        Text(url.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    } else {
                        Text("No folder selected").fontWeight(.medium).foregroundStyle(.secondary)
                        Text("Choose any folder — a project root or a single directory.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button(selectedURL == nil ? "Choose Folder…" : "Change") { pickFolder() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .glassCard(cornerRadius: 12)
            .padding(.horizontal, 24).padding(.bottom, 16)

            // Depth selector
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Apply to").font(.subheadline).fontWeight(.medium)
                    Spacer()
                    // Dynamic explanation of selected depth
                    Text(depth.help)
                        .font(.caption).foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .id(depth)
                }
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.18), value: depth)

                HStack(spacing: 10) {
                    ForEach(ApplyDepth.allCases) { d in
                        DepthCard(option: d, isSelected: depth == d) { depth = d }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 20)

            // Action buttons row
            HStack(spacing: 8) {
                if applyProgress == nil {
                    Button(action: applyIcons) {
                        Label("Apply Styling", systemImage: "paintbrush.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedURL == nil || previewItems.filter(\.matched).isEmpty)

                    Button(role: .destructive) { removeAllIcons() } label: {
                        Label("Remove All Styling", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedURL == nil)

                    if selectedURL != nil {
                        Button(action: rescan) {
                            Label("Rescan", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Re-scan project, refresh .gitignore and folder structure")
                    }
                } else {
                    Button {
                        scan.isPaused.toggle()
                    } label: {
                        Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        scan.cancelApplyTask()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // Ignore manager button (opens modal)
                if depth != .rootOnly {
                    Button { showIgnoreManager = true } label: {
                        let count = userIgnorePaths.count
                        Label(count > 0 ? "Ignored (\(count))" : "Ignored", systemImage: "eye.slash")
                    }
                    .buttonStyle(.bordered)
                }

                if !applyErrors.isEmpty {
                    Button {
                        currentError = applyErrors.first
                        showErrorDialog = true
                    } label: {
                        Label("\(applyErrors.count) error\(applyErrors.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 24)

            // Apply progress bar
            if let p = applyProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(p.done), total: Double(p.total))
                        .tint(isPaused ? .orange : Color.accentColor)
                        .animation(.easeInOut(duration: 0.25), value: p.done)
                    HStack {
                        Label(
                            isPaused ? "Paused — \(p.done) of \(p.total)" : "Applying… \(p.done) of \(p.total)",
                            systemImage: isPaused ? "pause.circle.fill" : "paintbrush.fill"
                        )
                        .font(.caption).foregroundStyle(isPaused ? .orange : .secondary)
                        Spacer()
                        Text("\(p.total - p.done) remaining")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .padding(.top, 20)
                .animation(.easeInOut(duration: 0.2), value: applyProgress != nil)

            // Preview / Results list
            if selectedURL == nil {
                ContentUnavailableView("No folder selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Choose a folder to see what icons would be applied."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasScanned && !isComputingPreview {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 46))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                    VStack(spacing: 6) {
                        Text("Ready to scan")
                            .font(.headline)
                        Text("Click Scan to analyze the selected folder and preview which icons will be applied.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                    }
                    Button {
                        startScan()
                    } label: {
                        Label("Scan Folder", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else if isComputingPreview {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(Color.accentColor)
                    VStack(spacing: 4) {
                        Text("Scanning folders…")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Matching your rules and rule sets — this may take a moment.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                previewResultsList
            }
        }
        .animation(.easeInOut(duration: 0.22), value: applyProgress != nil)
        .onAppear {
            // Reset only transient UI state. Scan selection + results live in
            // `scan` and are intentionally preserved across tab navigation.
            searchText = ""
            resultFilter = .all
            pagination = PaginationState()

            // Wire termination cleanup so the apply task is cancelled before
            // the process exits, preventing background threads from accessing
            // deallocated objects.
            AppState.shared.terminationHandler = { [sc = scan] in sc.cancelApplyTask() }

            // If the saved folder no longer exists, drop it.
            if let url = selectedURL,
               (try? FileManager.default.contentsOfDirectory(atPath: url.path)) == nil {
                scan.reset()
                savedFolderPath = ""
            }
        }
        .onChange(of: selectedURL) { _, url in
            savedFolderPath = url?.path ?? ""
            if url != nil { importGitignore() }
        }
        .onChange(of: depth) { _, d in
            savedDepth = d.rawValue
            // A depth change invalidates the current results — rescan automatically.
            if selectedURL != nil { rescan() }
        }
        .sheet(item: $projectForPicker) { item in
            IconPickerSheet(title: item.name) { icon in
                let r = iconManager.applyIcon(icon, to: item.url)
                if r.success {
                    historyManager.record(folderPath: item.url.path, iconID: icon.id,
                                          iconName: icon.name, originalIconData: r.originalIconData)
                    updateItem(item, with: icon)
                }
            }
            .environmentObject(iconManager)
        }
        .sheet(isPresented: $showIgnoreManager) {
            IgnoreManagerSheet(
                ignorePaths: userIgnorePaths,
                builtInSkips: builtInSkips,
                onSave: { saveIgnorePaths($0) },
                onImportGitignore: { importGitignore() }
            )
        }
        .onChange(of: scan.applyErrorSignal) { _, _ in
            if let first = scan.applyErrors.first {
                currentError = first
                showErrorDialog = true
            }
        }
        .alert("Apply Error", isPresented: $showErrorDialog, presenting: currentError) { error in
            Button("Copy Error") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(error.description, forType: .string)
            }
            Button("Retry") {
                retryError(error)
            }
            Button("Dismiss", role: .cancel) {
                if let e = currentError {
                    applyErrors.removeAll { $0.id == e.id }
                }
            }
        } message: { error in
            Text(error.description)
        }
    }

    // MARK: - Preview Results with Pagination

    @ViewBuilder
    private var previewResultsList: some View {
        let allMatched   = previewItems.filter(\.matched)
        let allUnmatched = previewItems.filter { !$0.matched }

        HStack(spacing: 8) {
            SearchField(placeholder: "Search folders…", text: $searchText)

            HStack(spacing: 4) {
                ForEach(ResultFilter.allCases, id: \.self) { f in
                    FilterPill(label: f.rawValue, isSelected: resultFilter == f) { resultFilter = f }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)

        let matched = allMatched.filter { item in
            (resultFilter != .unmatched) &&
            (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
        }
        let unmatched = allUnmatched.filter { item in
            (resultFilter != .matched) &&
            (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
        }
        let allFiltered = matched + unmatched
        let totalPages = pagination.totalPages(for: allFiltered.count)
        let pageItems = pagination.pageSlice(allFiltered)
        let pageMatched = pageItems.filter(\.matched)
        let pageUnmatched = pageItems.filter { !$0.matched }

        List {
            if !pageMatched.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: hasApplied ? "checkmark.circle" : "paintbrush")
                        Text(hasApplied ? "\(previewItems.filter { $0.matched && $0.applied }.count) applied" : "\(allMatched.count) will be changed")
                    }
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(hasApplied ? Color.green : Theme.accentSoft)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background((hasApplied ? Color.green : Theme.accent).opacity(0.16), in: Capsule())

                    ForEach(pageMatched) { item in
                        ResultRow(item: item, isPreview: !hasApplied)
                            .contextMenu {
                                Button("Choose Icon…") { projectForPicker = item }
                            }
                    }
                }
            }

            if !pageUnmatched.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: hasReverted ? "checkmark.circle" : "circle.slash")
                        Text(hasReverted
                             ? "\(allUnmatched.count) styling removed"
                             : "\(allUnmatched.count) no matching rule")
                    }
                    .font(.subheadline)
                    .foregroundStyle(hasReverted ? Color.green : .secondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(hasReverted ? Color.green.opacity(0.14) : Theme.glassFill, in: Capsule())

                    ForEach(pageUnmatched) { item in
                        ResultRow(item: item, isPreview: !hasApplied)
                    }
                }
            }

            if pageMatched.isEmpty && pageUnmatched.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search or filter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)

        if totalPages > 1 {
            PaginationBar(currentPage: $pagination.currentPage, totalPages: totalPages, totalItems: allFiltered.count, pageSize: pagination.pageSize)
                .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    // MARK: - Preview

    private func computePreview() async {
        guard let root = selectedURL else {
            previewItems = []
            hasApplied = false
            hasReverted = false
            return
        }
        isComputingPreview = true
        hasApplied = false
        hasReverted = false
        pagination.currentPage = 1

        let startTime = Date()

        let folders = foldersToProcess(root: root)
        var items: [FolderIconResult] = []
        for folder in folders {
            try? await Task.sleep(nanoseconds: 0)
            guard !Task.isCancelled else { return }
            let eval = ruleEngine.evaluate(folderURL: folder)
            let iconName = eval?.iconID.flatMap { iconManager.icon(for: $0)?.name }
            let source: String? = eval.map { r in
                switch r.matchedBy {
                case "ruleset":  return "Rule Set: \(r.matchName)"
                default:         return "Rule: \(r.matchName)"
                }
            }
            items.append(FolderIconResult(url: folder, iconID: eval?.iconID,
                                          iconName: iconName, matchSource: source,
                                          color: eval?.color))
        }

        // Enforce a minimum 1.5-second display time for the loading state so
        // the user can see it register — fast scans would otherwise flash invisibly.
        let elapsed = Date().timeIntervalSince(startTime)
        let minDuration: TimeInterval = 1.5
        if elapsed < minDuration {
            try? await Task.sleep(nanoseconds: UInt64((minDuration - elapsed) * 1_000_000_000))
        }
        guard !Task.isCancelled else { return }

        previewItems = items
        isComputingPreview = false
        scan.markScanned()
    }

    // MARK: - Apply

    private func applyIcons() {
        let toApply = previewItems.filter(\.matched)
        guard !toApply.isEmpty else { return }
        scan.isPaused = false
        scan.applyProgress = (done: 0, total: toApply.count)
        scan.applyErrors = []

        // Capture references; all I/O runs on background threads via async wrappers.
        // Only UI mutations hop back to the main actor explicitly.
        let icMgr = iconManager
        let histMgr = historyManager
        let sc = scan

        scan.applyTask = Task { [weak sc] in
            guard let sc else { return }
            var done = 0

            for item in toApply {
                guard !Task.isCancelled else { break }

                while await MainActor.run(body: { sc.isPaused }) && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                guard !Task.isCancelled else { break }

                let hasIcon = item.iconID != nil
                let hasColor = item.color != nil
                var applied = false
                var applyErr: ApplyError?

                if hasIcon && hasColor {
                    let icon = await MainActor.run { icMgr.icon(for: item.iconID!) }!
                    let r = await icMgr.applyIconAndColorAsync(icon, color: item.color!.nsColor, to: item.url)
                    if r.success {
                        let oData = r.originalIconData
                        await MainActor.run {
                            histMgr.recordIconAndColor(folderPath: item.url.path, iconID: icon.id,
                                iconName: icon.name, colorName: item.color!.displayName,
                                colorHex: item.color!.nsColor.hexString, originalIconData: oData)
                        }
                        applied = true
                    } else {
                        applyErr = ApplyError(operation: "apply icon+color",
                                              folderPath: item.url.path,
                                              message: "Could not set icon. Check permissions.")
                    }
                } else if hasIcon {
                    let icon = await MainActor.run { icMgr.icon(for: item.iconID!) }!
                    let r = await icMgr.applyIconAsync(icon, to: item.url)
                    if r.success {
                        let oData = r.originalIconData
                        await MainActor.run {
                            histMgr.record(folderPath: item.url.path, iconID: icon.id,
                                           iconName: icon.name, originalIconData: oData)
                        }
                        applied = true
                    } else {
                        applyErr = ApplyError(operation: "apply icon \(icon.name)",
                                              folderPath: item.url.path,
                                              message: "Could not set icon. Check permissions.")
                    }
                } else if hasColor {
                    let r = await icMgr.applyColorAsync(item.color!.nsColor, to: item.url)
                    if r.success {
                        let oData = r.originalIconData
                        await MainActor.run {
                            histMgr.recordColorApply(folderPath: item.url.path,
                                colorName: item.color!.displayName,
                                colorHex: item.color!.nsColor.hexString,
                                originalIconData: oData)
                        }
                        applied = true
                    } else {
                        applyErr = ApplyError(operation: "apply color \(item.color!.displayName)",
                                              folderPath: item.url.path,
                                              message: "Permission denied or folder not found.")
                    }
                }

                done += 1
                let d = done
                let total = toApply.count
                let itemID = item.id
                let wasApplied = applied
                let err = applyErr

                await MainActor.run {
                    if wasApplied, let i = sc.previewItems.firstIndex(where: { $0.id == itemID }) {
                        sc.previewItems[i].applied = true
                    }
                    if let e = err { sc.applyErrors.append(e) }
                    sc.applyProgress = (done: d, total: total)
                }
            }

            await MainActor.run {
                sc.applyProgress = nil
                sc.isPaused = false
                if !Task.isCancelled {
                    sc.hasApplied = true
                    if !sc.applyErrors.isEmpty {
                        sc.applyErrorSignal += 1
                    }
                }
                sc.applyTask = nil
            }
        }
    }

    private func removeAllIcons() {
        guard let root = selectedURL else { return }
        let folders = foldersToProcess(root: root)
        scan.isPaused = false
        scan.applyProgress = (done: 0, total: folders.count)

        let icMgr = iconManager
        let histMgr = historyManager
        let sc = scan

        scan.applyTask = Task { [weak sc] in
            guard let sc else { return }
            let startTime = Date()
            var done = 0
            for folder in folders {
                guard !Task.isCancelled else { break }
                await icMgr.removeIconAsync(from: folder)
                let fPath = folder.path
                let d = done + 1
                let total = folders.count
                done = d
                await MainActor.run {
                    histMgr.record(folderPath: fPath, iconID: nil, iconName: "Removed icon", action: .revert)
                    sc.applyProgress = (done: d, total: total)
                }
            }
            // Enforce a minimum 1-second progress display so it doesn't flash away.
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 1.0 {
                try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
            }
            await MainActor.run {
                if !Task.isCancelled {
                    sc.previewItems = sc.previewItems.map {
                        FolderIconResult(url: $0.url, iconID: nil, iconName: nil, matchSource: nil, color: nil)
                    }
                    sc.hasApplied = false
                    sc.hasReverted = true
                }
                sc.applyProgress = nil
                sc.applyTask = nil
            }
        }
    }

    // MARK: - Close Project

    private func closeProject() {
        previewTask?.cancel()
        previewTask = nil
        scan.reset()   // cancels applyTask and clears applyProgress/isPaused/applyErrors
        savedFolderPath = ""
        searchText = ""
        resultFilter = .all
        pagination = PaginationState()
    }

    // MARK: - Rescan

    private func rescan() {
        guard selectedURL != nil else { return }
        importGitignore()
        previewItems = []
        hasApplied = false
        hasReverted = false
        pagination = PaginationState()
        applyErrors = []
        startScan()
    }

    /// Start (or restart) a preview scan, cancelling any in-flight scan first so
    /// rapid depth/folder changes don't race each other.
    private func startScan() {
        previewTask?.cancel()
        previewTask = Task { await computePreview() }
    }

    // MARK: - .gitignore Import (recursive through all subfolders)

    private func importGitignore() {
        guard let root = selectedURL else { return }
        var paths = userIgnorePaths
        paths.removeAll { $0.source == .gitignore }

        // Collect patterns from .gitignore files found recursively
        let collected = collectGitignorePatterns(in: root, existingPatterns: Set(paths.map(\.pattern)))
        for pattern in collected {
            guard !builtInSkips.contains(pattern) else { continue }
            paths.append(IgnoredPath(pattern: pattern, isRecursive: true, source: .gitignore))
        }

        saveIgnorePaths(paths)
    }

    /// Walk directory tree top-down, reading .gitignore at each level.
    /// Folders that match already-discovered ignore patterns are skipped.
    private func collectGitignorePatterns(in dir: URL, existingPatterns: Set<String>) -> [String] {
        let fm = FileManager.default
        var allPatterns: [String] = []
        var skipSet = existingPatterns.union(builtInSkips)

        // Read .gitignore at this level
        let gitignoreURL = dir.appendingPathComponent(".gitignore")
        if let content = try? String(contentsOf: gitignoreURL, encoding: .utf8) {
            for pattern in parseGitignore(content) where !skipSet.contains(pattern) {
                allPatterns.append(pattern)
                skipSet.insert(pattern)
            }
        }

        // Recurse into subdirectories, skipping ignored ones
        guard let items = try? fm.contentsOfDirectory(at: dir,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return allPatterns
        }
        for item in items {
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = item.lastPathComponent
            guard !builtInSkips.contains(name) else { continue }
            guard !skipSet.contains(name) else { continue }
            allPatterns += collectGitignorePatterns(in: item, existingPatterns: skipSet)
            // Merge newly found patterns into skip set for sibling traversal
            for p in allPatterns { skipSet.insert(p) }
        }

        return allPatterns
    }

    private func parseGitignore(_ content: String) -> [String] {
        var patterns: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("!") { continue }
            if line.hasSuffix("/") { line = String(line.dropLast()) }
            if line.hasPrefix("/") { line = String(line.dropFirst()) }
            if line.contains("*") || line.contains("?") || line.contains("[") { continue }
            guard !line.isEmpty else { continue }
            patterns.append(line)
        }
        return patterns
    }

    // MARK: - Error Retry

    private func retryError(_ error: ApplyError) {
        let url = URL(fileURLWithPath: error.folderPath)
        if error.operation.contains("icon") {
            if let item = previewItems.first(where: { $0.url == url }),
               let iconID = item.iconID,
               let icon = iconManager.icon(for: iconID) {
                if let color = item.color {
                    let r = iconManager.applyIconAndColor(icon, color: color.nsColor, to: url)
                    if r.success {
                        historyManager.recordIconAndColor(folderPath: url.path, iconID: icon.id,
                                                          iconName: icon.name, colorName: color.displayName,
                                                          colorHex: color.nsColor.hexString,
                                                          originalIconData: r.originalIconData)
                        applyErrors.removeAll { $0.id == error.id }
                    }
                } else {
                    let r = iconManager.applyIcon(icon, to: url)
                    if r.success {
                        historyManager.record(folderPath: url.path, iconID: icon.id,
                                              iconName: icon.name, originalIconData: r.originalIconData)
                        applyErrors.removeAll { $0.id == error.id }
                    }
                }
            }
        } else if error.operation.contains("color") {
            if let item = previewItems.first(where: { $0.url == url }),
               let color = item.color {
                let r = iconManager.applyColor(color.nsColor, to: url)
                if r.success {
                    historyManager.recordColorApply(folderPath: url.path, colorName: color.displayName,
                                                     colorHex: color.nsColor.hexString,
                                                     originalIconData: r.originalIconData)
                    applyErrors.removeAll { $0.id == error.id }
                }
            }
        }
    }

    // MARK: - Helpers

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedURL = url
            previewItems = []
            hasApplied = false
            pagination = PaginationState()
            startScan()
        }
    }

    private func foldersToProcess(root: URL) -> [URL] {
        switch depth {
        case .rootOnly:  return [root]
        case .immediate: return [root] + subfolders(of: root)
        case .recursive: return walkRecursive(root)
        }
    }

    private func shouldSkip(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let path = url.path
        if builtInSkips.contains(name) { return true }
        for ignored in userIgnorePaths {
            if ignored.pattern.hasPrefix("/") {
                if ignored.isRecursive {
                    if path == ignored.pattern || path.hasPrefix(ignored.pattern + "/") { return true }
                } else {
                    if path == ignored.pattern { return true }
                }
            } else {
                if ignored.isRecursive {
                    if name.lowercased() == ignored.pattern.lowercased() { return true }
                    if path.lowercased().contains("/" + ignored.pattern.lowercased() + "/") { return true }
                } else {
                    if name.lowercased() == ignored.pattern.lowercased() { return true }
                }
            }
        }
        return false
    }

    private func subfolders(of url: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: url,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return items.filter {
            !shouldSkip($0) &&
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func walkRecursive(_ url: URL) -> [URL] {
        var result = [url]
        for sub in subfolders(of: url) { result += walkRecursive(sub) }
        return result
    }

    private func markApplied(_ item: FolderIconResult) {
        if let i = previewItems.firstIndex(where: { $0.id == item.id }) {
            previewItems[i].applied = true
        }
    }

    private func updateItem(_ old: FolderIconResult, with icon: IconModel) {
        if let i = previewItems.firstIndex(where: { $0.id == old.id }) {
            var result = FolderIconResult(url: old.url, iconID: icon.id,
                                          iconName: icon.name, matchSource: "Manual", color: nil)
            result.applied = true
            previewItems[i] = result
        }
    }
}

// MARK: - Ignore Manager Sheet (separate modal window)

struct IgnoreManagerSheet: View {
    @State var ignorePaths: [IgnoredPath]
    let builtInSkips: Set<String>
    let onSave: ([IgnoredPath]) -> Void
    let onImportGitignore: () -> Void
    @Environment(\.dismiss) var dismiss

    @State private var newPattern = ""
    @State private var newRecursive = false
    @State private var searchText = ""

    var filteredPaths: [IgnoredPath] {
        if searchText.isEmpty { return ignorePaths }
        return ignorePaths.filter { $0.pattern.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ignored Folders").font(.headline)
                    Text("Folders listed here are skipped during scanning — they won't be assigned icons.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    onSave(ignorePaths)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            // Built-in skips explanation
            GroupBox {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Always skipped (built-in)", systemImage: "lock.fill")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    Text(builtInSkips.sorted().joined(separator: "  ·  "))
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("These folders are always excluded because they contain build artifacts, dependencies, or version control data that should never get custom icons.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.caption2).foregroundStyle(.orange)
                    Text("Recursive").font(.caption2).foregroundStyle(.secondary)
                    Text("— searches all subfolders").font(.caption2).foregroundStyle(.tertiary)
                }
                HStack(spacing: 4) {
                    Text(".gitignore").font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                    Text("— imported automatically").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            // Search
            SearchField(placeholder: "Search…", text: $searchText)

            // List
            List {
                ForEach(filteredPaths) { path in
                    HStack(spacing: 8) {
                        Image(systemName: path.isRecursive ? "arrow.triangle.branch" : "folder.badge.minus")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(path.pattern).font(.callout)

                        if path.isRecursive {
                            Text("recursive")
                                .font(.caption2).foregroundStyle(.orange)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                                .help("Recursive: this folder name is ignored anywhere in the directory tree, including inside nested subfolders.")
                        }

                        if path.source == .gitignore {
                            Text(".gitignore")
                                .font(.caption2).foregroundStyle(.blue)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .help("Imported from your project's .gitignore file. Folio automatically reads .gitignore to skip build artifacts and ignored files.")
                        }

                        Spacer()

                        Button { ignorePaths.removeAll { $0.id == path.id } } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
        .scrollContentBackground(.hidden)

            // Add new
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Folder name or /full/path…", text: $newPattern)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addPattern() }
                    Toggle("Recursive", isOn: $newRecursive)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("Recursive: ignore this folder name anywhere in the directory tree, not just at the top level. Non-recursive only ignores a folder matching the exact top-level path.")
                    Button("Add") { addPattern() }
                        .buttonStyle(.bordered)
                        .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if newRecursive {
                    Label("Recursive: will ignore this folder name in every subfolder, no matter how deep.", systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.orange)
                } else {
                    Label("Non-recursive: only ignores an exact match at the top level of the selected folder.", systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    onImportGitignore()
                    // Reload from parent
                    dismiss()
                } label: {
                    Label("Re-import .gitignore", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Clear All Manual", role: .destructive) {
                    ignorePaths.removeAll { $0.source == .manual }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 550, height: 500)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !ignorePaths.contains(where: { $0.pattern == trimmed }) else { return }
        ignorePaths.append(IgnoredPath(pattern: trimmed, isRecursive: newRecursive, source: .manual))
        newPattern = ""
        newRecursive = false
    }
}

// MARK: - PaginationBar

struct PaginationBar: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let totalItems: Int
    let pageSize: Int

    var body: some View {
        HStack(spacing: 4) {
            Button { currentPage = max(1, currentPage - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage <= 1)
            .buttonStyle(.plain)

            let visible = visiblePageNumbers()
            ForEach(Array(visible.enumerated()), id: \.offset) { idx, page in
                if idx > 0, page != visible[idx - 1] + 1 {
                    Text("…").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 2)
                }
                Button {
                    currentPage = page
                } label: {
                    Text("\(page)")
                        .font(.caption).fontWeight(currentPage == page ? .bold : .regular)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(currentPage == page ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(currentPage == page ? .white : .primary)
                }
                .buttonStyle(.plain)
            }

            Button { currentPage = min(totalPages, currentPage + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= totalPages)
            .buttonStyle(.plain)

            Spacer()

            Text("\(totalItems) items")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func visiblePageNumbers() -> [Int] {
        guard totalPages > 1 else { return [1] }
        var pages: Set<Int> = [1, totalPages]
        let window = 2
        for p in max(1, currentPage - window)...min(totalPages, currentPage + window) {
            pages.insert(p)
        }
        return pages.sorted()
    }
}

// MARK: - DepthCard

struct DepthCard: View {
    let option: ApplyDepth
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: option.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : isHovered ? .primary : .secondary)
                    .frame(height: 22)
                Text(option.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? Theme.accent : isHovered ? .primary : .primary.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isSelected ? Theme.accent.opacity(0.15) : isHovered ? Theme.glassHover : Theme.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        isSelected ? Theme.accent.opacity(0.55) : isHovered ? Theme.glassStroke.opacity(2) : Theme.glassStroke,
                        lineWidth: isSelected ? 1.0 : 0.5
                    )
            )
            .shadow(color: isSelected ? Theme.accent.opacity(0.15) : .clear, radius: 8, y: 3)
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .help(option.help)
    }
}

// MARK: - ResultRow

struct ResultRow: View {
    let item: FolderIconResult
    let isPreview: Bool
    @EnvironmentObject var iconManager: IconManager

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.matched {
                    if isPreview {
                        Image(systemName: "paintbrush.fill")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Image(systemName: item.applied ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(item.applied ? .green : .red)
                    }
                } else {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.body).frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).fontWeight(.medium)
                    if let color = item.color {
                        Circle().fill(Color(nsColor: color.nsColor))
                            .frame(width: 10, height: 10)
                        Text(color.displayName).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let source = item.matchSource {
                    Text(source).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if let id = item.iconID, let icon = iconManager.icon(for: id), let img = icon.nsImage {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 5))
                Text(icon.name).font(.subheadline).foregroundStyle(.secondary)
            } else if !item.matched {
                Text("No match").font(.subheadline).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .opacity(item.matched ? 1 : 0.55)
    }
}

// MARK: - IconPickerSheet

struct IconPickerSheet: View {
    let title: String
    let onSelect: (IconModel) -> Void
    @EnvironmentObject var iconManager: IconManager
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var filterCategoryID: UUID? = nil
    @State private var selectedIcon: IconModel? = nil

    var categoriesInLibrary: [IconCategory] {
        iconManager.categories.filter { cat in
            iconManager.icons.contains { $0.categoryID == cat.id && !$0.isHidden }
        }
    }

    var filterCategoryName: String {
        guard let id = filterCategoryID else { return "All Categories" }
        return iconManager.categories.first { $0.id == id }?.name ?? "All Categories"
    }

    var filtered: [IconModel] {
        iconManager.icons.filter { icon in
            guard !icon.isHidden else { return false }
            let matchesCategory = filterCategoryID == nil || icon.categoryID == filterCategoryID
            let matchesSearch = searchText.isEmpty || icon.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose Icon").font(.title3).fontWeight(.semibold)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 14)

            Divider().opacity(0.3)

            HStack(spacing: 0) {
                // Left: search + grid
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        SearchField(placeholder: "Search icons…", text: $searchText)

                        if !categoriesInLibrary.isEmpty {
                            Menu {
                                Button("All Categories") { filterCategoryID = nil }
                                Divider()
                                ForEach(categoriesInLibrary) { cat in
                                    Button(cat.name) { filterCategoryID = cat.id }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                    Text(filterCategoryName).lineLimit(1)
                                }
                                .font(.system(size: 12, weight: .medium))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }

                    if iconManager.icons.isEmpty {
                        ContentUnavailableView("No icons saved", systemImage: "photo.badge.plus",
                            description: Text("Add icons in the Icon Library first."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filtered.isEmpty {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                                ForEach(filtered) { icon in
                                    IconPickerCell(icon: icon, isSelected: selectedIcon?.id == icon.id)
                                        .onTapGesture { selectedIcon = icon }
                                }
                            }
                            .padding(4)
                        }
                    }

                    Button { uploadNewIcon() } label: {
                        Label("Upload New Icon…", systemImage: "plus.rectangle.on.rectangle")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 22)
                .frame(width: 470)

                Divider().opacity(0.3)

                // Right: preview + apply
                VStack(spacing: 18) {
                    Spacer()

                    VStack(spacing: 14) {
                        if let icon = selectedIcon, let img = icon.nsImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 140, height: 140)
                                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

                            Text(icon.name)
                                .font(.headline)
                                .multilineTextAlignment(.center)

                            if let type = icon.associatedType {
                                Text(type.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .glassCard(cornerRadius: 10)
                            }
                        } else {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 52))
                                .foregroundStyle(Theme.accent.opacity(0.4))

                            Text("Select an icon")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()

                    Button("Apply Icon") {
                        if let icon = selectedIcon { onSelect(icon); dismiss() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedIcon == nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.vertical, 30)
            }
        }
        .frame(width: 760, height: 620)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func uploadNewIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns]
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            iconManager.addIcon(name: url.deletingPathExtension().lastPathComponent, type: nil, data: data)
            selectedIcon = iconManager.icons.last
        }
    }
}

// MARK: - IconPickerCell

struct IconPickerCell: View {
    let icon: IconModel
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 7) {
            if let img = icon.nsImage {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(width: 58, height: 58)
                    .scaleEffect(isSelected ? 1.05 : isHovered ? 1.03 : 1.0)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Theme.glassFill).frame(width: 58, height: 58)
            }
            Text(icon.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.accent : .primary)
        }
        .padding(11).frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Theme.accent.opacity(0.16) : isHovered ? Theme.glassHover : Theme.glassFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Theme.accent.opacity(0.6) : isHovered ? Theme.glassStroke.opacity(2) : Theme.glassStroke,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .shadow(color: isSelected ? Theme.accent.opacity(0.18) : .clear, radius: 6, y: 2)
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isSelected)
    }
}
