import SwiftUI
import ServiceManagement
import Combine

struct SettingsView: View {
    @EnvironmentObject var iconManager: IconManager
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var historyManager: HistoryManager

    @State private var showRestoreDefaultsConfirm = false
    @State private var showResetConfirm = false
    @State private var showClearIconsConfirm = false
    @State private var showClearRulesConfirm = false
    @State private var showClearHistoryConfirm = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @StateObject private var updater = UpdateChecker()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(.title3).fontWeight(.semibold)
                    Text("Preferences & data management").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 14)

            Divider().opacity(0.3)

            Form {
            Section("General") {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                        Text("Start Folio automatically when you sign in.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            }

            Section("Data") {
                HStack {
                    Text("Saved icons")
                    Spacer()
                    Text("\(iconManager.icons.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Icon categories")
                    Spacer()
                    Text("\(iconManager.categories.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Active individual rules")
                    Spacer()
                    Text("\(ruleEngine.rules.filter(\.isEnabled).count) of \(ruleEngine.rules.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Active rule sets")
                    Spacer()
                    Text("\(ruleEngine.ruleSets.filter(\.isEnabled).count) of \(ruleEngine.ruleSets.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("History entries")
                    Spacer()
                    Text("\(historyManager.entries.count)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Preferences") {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore Defaults").font(.system(size: 13, weight: .medium))
                        Text("Restores built-in icons, default rules and rule sets, and resets all preferences. Your custom icons, custom rules, and history are removed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore") { showRestoreDefaultsConfirm = true }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.orange)
                        .tint(.orange)
                        .controlSize(.small)
                }
            }

            Section {
                DangerRow(
                    icon: "paintbrush.fill",
                    title: "Clear Custom Icons",
                    description: "Removes all your manually added icons. Built-in icons are kept.",
                    buttonLabel: "Clear Custom Icons"
                ) { showClearIconsConfirm = true }

                DangerRow(
                    icon: "list.bullet.rectangle.portrait",
                    title: "Clear All Rules & Rule Sets",
                    description: "Deletes all individual rules and rule sets, including built-in defaults. Use Restore Defaults to get them back.",
                    buttonLabel: "Clear Rules & Sets"
                ) { showClearRulesConfirm = true }

                DangerRow(
                    icon: "clock.arrow.circlepath",
                    title: "Clear History",
                    description: "Removes all recorded folder icon changes.",
                    buttonLabel: "Clear History"
                ) { showClearHistoryConfirm = true }

                DangerRow(
                    icon: "trash.fill",
                    title: "Wipe Everything",
                    description: "Removes all icons, rules, rule sets, history, and preferences. Built-in defaults won't regenerate — use Restore Defaults to get them back.",
                    buttonLabel: "Wipe Everything",
                    isDestructivePrimary: true
                ) { showResetConfirm = true }
            } header: {
                Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Section("Support") {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Support Development").font(.system(size: 13, weight: .medium))
                        Text("If Folio is useful to you, a small tip is always appreciated and keeps the project going.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Donate") {
                        if let url = URL(string: "https://paypal.me/ramezehab") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.blue)
                    .tint(.blue)
                    .controlSize(.small)
                }
            }

            Section {

                HStack {
                    Text("Updates")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task {
                            async let check: () = updater.check()
                            async let delay: () = { try? await Task.sleep(for: .seconds(1)) }()
                            _ = await (check, delay)
                        }
                    } label: {
                        if updater.isChecking {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Check")
                        }
                    }
                    .disabled(updater.isChecking || updater.isDownloading)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    HStack(spacing: 8) {
                        Text(UpdateChecker.currentVersion)
                            .foregroundStyle(.secondary)
                        Button("Release Notes") {
                            let tag = "v\(UpdateChecker.currentVersion)"
                            let urlString = "https://github.com/\(UpdateConfig.repoOwner)/\(UpdateConfig.repoName)/releases/tag/\(tag)"
                            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    }
                }

                HStack {
                    Spacer()
                    updateStatusView
                    Spacer()
                }

            }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 480, height: 560)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .confirmationDialog("Clear custom icons?", isPresented: $showClearIconsConfirm, titleVisibility: .visible) {
            Button("Clear Custom Icons", role: .destructive) {
                iconManager.icons.removeAll { !$0.isBuiltIn }
                iconManager.categories.removeAll { !$0.isBuiltIn }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your manually added icons. Built-in icons will remain.")
        }
        .confirmationDialog("Clear all rules and rule sets?", isPresented: $showClearRulesConfirm, titleVisibility: .visible) {
            Button("Clear Rules & Sets", role: .destructive) {
                ruleEngine.rules = []
                ruleEngine.ruleSets = []
                ruleEngine.evalOrder = []
                UserDefaults.standard.set(true, forKey: RuleEngine.defaultsSuppressedKey)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all individual rules and rule sets, including built-in defaults. Use Restore Defaults to get them back.")
        }
        .confirmationDialog("Clear history?", isPresented: $showClearHistoryConfirm, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                historyManager.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all history entries.")
        }
        .confirmationDialog("Restore defaults?", isPresented: $showRestoreDefaultsConfirm, titleVisibility: .visible) {
            Button("Restore Defaults", role: .destructive) {
                restoreDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore built-in icons and default rules and rule sets, and reset all preferences. Custom icons, custom rules, and history will be removed.")
        }
        .confirmationDialog("Wipe everything?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Wipe Everything", role: .destructive) {
                iconManager.icons = []
                iconManager.categories = []
                ruleEngine.rules = []
                ruleEngine.ruleSets = []
                ruleEngine.evalOrder = []
                historyManager.clear()
                // Reset preferences without repopulating defaults
                launchAtLogin = false
                setLaunchAtLogin(false)
                UserDefaults.standard.removeObject(forKey: "projects.lastFolderPath")
                UserDefaults.standard.removeObject(forKey: "projects.lastDepth")
                UserDefaults.standard.removeObject(forKey: "projects.ignorePatternsV2")
                UserDefaults.standard.removeObject(forKey: UpdateChecker.skippedVersionKey)
                // Suppress default regeneration on next launch
                UserDefaults.standard.set(true, forKey: RuleEngine.defaultsSuppressedKey)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every icon, rule, rule set, and history entry, and resets all preferences. Nothing regenerates automatically — use Restore Defaults to get the built-in content back. This cannot be undone.")
        }
    }

    private func restoreDefaults() {
        // Preferences
        launchAtLogin = false
        setLaunchAtLogin(false)
        UserDefaults.standard.removeObject(forKey: "projects.lastFolderPath")
        UserDefaults.standard.removeObject(forKey: "projects.lastDepth")
        UserDefaults.standard.removeObject(forKey: "projects.ignorePatternsV2")
        UserDefaults.standard.removeObject(forKey: UpdateChecker.skippedVersionKey)
        // Restore built-in icons immediately (removes user icons, re-syncs bundle icons)
        iconManager.restoreBuiltIns()
        // Restore default rules/rule sets immediately
        ruleEngine.repopulateDefaults()
        // Wire built-in icons onto the restored rule sets
        ruleEngine.syncDefaultIconsForRuleSets(from: iconManager)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .upToDate:
            Label("You're on the latest version.", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                Label("Version \(release.version) is available.", systemImage: "arrow.down.circle.fill")
                    .font(.caption).foregroundStyle(Theme.accent)
                VStack(spacing: 10) {
                    HStack {
                        Spacer()
                        Button {
                            Task { await updater.downloadAndInstall(release) }
                        } label: {
                            if updater.isDownloading {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Downloading…")
                                }
                            } else {
                                Text("Download & Install")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updater.isDownloading || release.downloadURL == nil)
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        Button("Release Notes") {
                            NSWorkspace.shared.open(release.htmlURL)
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
                if release.downloadURL == nil {
                    Text("No downloadable asset found on this release — opening the release page instead.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Revert the toggle to reflect the real state if the change failed.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Danger row

private struct DangerRow: View {
    let icon: String
    let title: String
    let description: String
    let buttonLabel: String
    var isDestructivePrimary: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(isDestructivePrimary ? 0.18 : 0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonLabel, action: action)
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                .tint(.red)
                .controlSize(.small)
                .fontWeight(isDestructivePrimary ? .semibold : .regular)
        }
    }
}

// MARK: - Automatic updates (via public GitHub Releases)
//
// ─────────────────────────────────────────────────────────────────────────
//  PUBLISHING CHECKLIST — update these values before shipping a release:
//
//  1. `UpdateConfig.repoOwner` / `UpdateConfig.repoName`
//        The PUBLIC GitHub repository that hosts your Releases. The updater
//        reads:  https://api.github.com/repos/<owner>/<name>/releases/latest
//
//  2. Release tags MUST be the version number, optionally "v"-prefixed
//        (e.g. "v1.2.0" or "1.2.0"). This is compared against the app's
//        CFBundleShortVersionString (MARKETING_VERSION in the Xcode project).
//        Bump MARKETING_VERSION for every release or the app will think it is
//        already up to date.
//
//  3. Each release should attach ONE downloadable asset whose filename ends in
//        ".dmg" (preferred) or ".zip". The updater downloads the first matching
//        asset and opens it (mounting the DMG / unzipping) so the user can drag
//        the new app into /Applications. If no such asset exists, the updater
//        falls back to opening the release page in the browser.
//
//  NOTE: requires the outgoing-network sandbox entitlement
//  (ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES in the build settings).
//
//  Why not Sparkle? Sparkle is the usual macOS choice, but it requires adding a
//  framework/SPM dependency, hosting a signed appcast XML feed, and managing
//  EdDSA signing keys. For a single-maintainer app distributed through GitHub
//  Releases, this ~120-line native checker is simpler to maintain and has no
//  third-party dependency. Swap in Sparkle later if you need delta updates or
//  silent background installs.
// ─────────────────────────────────────────────────────────────────────────

enum UpdateConfig {
    /// CHANGE ME when publishing: your public GitHub repo that holds Releases.
    static let repoOwner = "ramezze"
    static let repoName  = "Folio"
}

struct AvailableRelease: Identifiable {
    var id: String { version }
    let version: String
    let htmlURL: URL
    let downloadURL: URL?
    let downloadName: String?
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum State {
        case idle
        case upToDate
        case available(AvailableRelease)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var isChecking = false
    @Published var isDownloading = false

    /// The app's current version, e.g. "1.0".
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Skipped versions

    static let skippedVersionKey = "updates.skippedVersion"

    /// Remember a version the user chose to skip — it won't trigger the startup
    /// prompt again (the manual "Check for Updates" button still shows it).
    static func skip(version: String) {
        UserDefaults.standard.set(version, forKey: skippedVersionKey)
    }

    static var skippedVersion: String? {
        UserDefaults.standard.string(forKey: skippedVersionKey)
    }

    /// Silent check used at app startup. Returns the available release only if a
    /// newer version exists and the user hasn't chosen to skip it. Does not
    /// mutate `state`, so it won't surface errors in the Settings panel.
    func checkAtStartup() async -> AvailableRelease? {
        await check()
        if case .available(let release) = state, release.version != Self.skippedVersion {
            return release
        }
        return nil
    }

    func check() async {
        isChecking = true
        defer { isChecking = false }

        let urlString = "https://api.github.com/repos/\(UpdateConfig.repoOwner)/\(UpdateConfig.repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            state = .failed("Invalid update URL.")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Folio-Updater", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                state = .failed("No published releases found yet.")
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = Self.normalize(release.tag_name)

            guard Self.isVersion(latest, newerThan: Self.normalize(Self.currentVersion)) else {
                state = .upToDate
                return
            }

            // Prefer a .dmg, then .zip, asset.
            let asset = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
                ?? release.assets.first { $0.name.lowercased().hasSuffix(".zip") }

            state = .available(AvailableRelease(
                version: latest,
                htmlURL: URL(string: release.html_url) ?? url,
                downloadURL: asset.flatMap { URL(string: $0.browser_download_url) },
                downloadName: asset?.name
            ))
        } catch {
            state = .failed("Couldn't check for updates. \(error.localizedDescription)")
        }
    }

    /// Download the release asset to a temp file and open it (mounts the DMG or
    /// unzips), letting the user drag the new app into /Applications.
    func downloadAndInstall(_ release: AvailableRelease) async {
        guard let downloadURL = release.downloadURL else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }
        isDownloading = true
        defer { isDownloading = false }

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
            let fileName = release.downloadName ?? downloadURL.lastPathComponent
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            NSWorkspace.shared.open(dest)
        } catch {
            state = .failed("Download failed. \(error.localizedDescription)")
        }
    }

    // MARK: - Version helpers

    /// Strip a leading "v" and any whitespace from a tag.
    static func normalize(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v
    }

    /// Semantic-ish comparison of dot-separated numeric versions.
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - GitHub API response shapes

private struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
