import SwiftUI

enum HistoryActionFilter: String, CaseIterable {
    case all = "All"
    case applied = "Applied"
    case reverted = "Reverted"
    case colors = "Colors"
}

struct HistoryView: View {
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var iconManager: IconManager
    @State private var showRevertAllConfirm = false
    @State private var showClearAllConfirm = false
    @State private var feedback: (message: String, success: Bool)?
    @State private var searchText = ""
    @State private var actionFilter: HistoryActionFilter = .all

    var filteredEntries: [HistoryEntry] {
        historyManager.entries.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.folderName.localizedCaseInsensitiveContains(searchText) ||
                entry.appliedIconName.localizedCaseInsensitiveContains(searchText)
            let matchesAction: Bool
            switch actionFilter {
            case .all:      matchesAction = true
            case .applied:  matchesAction = entry.action == .apply || entry.action == .reapply || entry.action == .applyIconAndColor
            case .reverted: matchesAction = entry.action == .revert
            case .colors:   matchesAction = entry.action == .applyColor || entry.action == .removeColor || entry.action == .applyIconAndColor
            }
            return matchesSearch && matchesAction
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PageHeader(title: "History")
                Spacer()
                if !historyManager.entries.isEmpty {
                    Button("Revert All") { showRevertAllConfirm = true }
                        .buttonStyle(.bordered)
                        .help("Undo every recorded icon change")
                    Button("Clear All", role: .destructive) { showClearAllConfirm = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)

            // Feedback banner
            if let fb = feedback {
                HStack(spacing: 8) {
                    Image(systemName: fb.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(fb.success ? .green : .red)
                    Text(fb.message).font(.caption)
                    Spacer()
                    Button { feedback = nil } label: {
                        Image(systemName: "xmark").font(.caption)
                    }.buttonStyle(.plain)
                }
                .padding(10)
                .background((fb.success ? Color.green : Color.red).opacity(0.1),
                             in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24).padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            if historyManager.entries.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock",
                    description: Text("Icon and color changes will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    SearchField(placeholder: "Search history…", text: $searchText)

                    HStack(spacing: 4) {
                        ForEach(HistoryActionFilter.allCases, id: \.self) { f in
                            FilterPill(label: f.rawValue, isSelected: actionFilter == f) { actionFilter = f }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                if filteredEntries.isEmpty {
                    ContentUnavailableView("No results", systemImage: "magnifyingglass",
                        description: Text("Try a different search or filter."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredEntries) { entry in
                        HStack(spacing: 12) {
                            // Icon / action indicator
                            ZStack {
                                if entry.action == .revert || entry.action == .removeColor {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                        .font(.title2).foregroundStyle(.orange)
                                        .frame(width: 32, height: 32)
                                } else if entry.action == .applyColor || entry.action == .applyIconAndColor {
                                    let entryColor: Color = {
                                        if let hex = entry.appliedColorHex, let ns = NSColor(hex: hex) {
                                            return Color(nsColor: ns)
                                        }
                                        if let name = entry.appliedColorName,
                                           let preset = FolderColor(rawValue: name.lowercased()) {
                                            return Color(nsColor: preset.nsColor)
                                        }
                                        return .purple
                                    }()
                                    ZStack {
                                        Image(systemName: "folder.fill")
                                            .font(.title2).foregroundStyle(entryColor)
                                            .frame(width: 32, height: 32)
                                    }
                                } else if let id = entry.appliedIconID,
                                          let icon = iconManager.icon(for: id),
                                          let img = icon.nsImage {
                                    Image(nsImage: img)
                                        .resizable().scaledToFit()
                                        .frame(width: 32, height: 32)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: "folder.fill")
                                        .font(.title2).foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.folderName).fontWeight(.medium)
                                    actionBadge(entry.action)
                                }
                                if let colorName = entry.appliedColorName {
                                    HStack(spacing: 4) {
                                        if let hex = entry.appliedColorHex, let ns = NSColor(hex: hex) {
                                            Circle().fill(Color(nsColor: ns)).frame(width: 8, height: 8)
                                        } else if let preset = FolderColor(rawValue: colorName.lowercased()) {
                                            Circle().fill(Color(nsColor: preset.nsColor)).frame(width: 8, height: 8)
                                        }
                                        Text("Color: \(colorName)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text(entry.folderPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(entry.appliedIconName).font(.caption).foregroundStyle(.secondary)
                                Text(entry.timeAgo).font(.caption2).foregroundStyle(.tertiary)
                            }

                            // Re-apply (only for apply/reapply actions that have an icon)
                            if entry.action != .revert && entry.action != .removeColor, entry.appliedIconID != nil {
                                Button { reapply(entry) } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("Re-apply this icon")
                                .disabled(!entry.folderExists)
                            }

                            // Revert
                            Button { performRevert(entry) } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(entry.folderExists ? .orange : .secondary)
                            .help(entry.originalIconData != nil
                                  ? "Revert to previous icon"
                                  : "Remove custom icon (restore default)")
                            .disabled(!entry.folderExists)
                        }
                        .padding(.vertical, 4)
                        .opacity(entry.folderExists ? 1 : 0.45)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: feedback?.message)
        .confirmationDialog("Revert all recorded changes?",
                            isPresented: $showRevertAllConfirm,
                            titleVisibility: .visible) {
            Button("Revert All", role: .destructive) {
                let count = historyManager.revertAll()
                showFeedback(count > 0
                    ? "Reverted \(count) change\(count == 1 ? "" : "s")"
                    : "Nothing to revert.", success: count > 0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will undo every icon change recorded in history.")
        }
        .confirmationDialog("Clear all history?",
                            isPresented: $showClearAllConfirm,
                            titleVisibility: .visible) {
            Button("Clear All", role: .destructive) { historyManager.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all history entries. Applied icons are not affected.")
        }
    }

    @ViewBuilder
    private func actionBadge(_ action: HistoryAction) -> some View {
        switch action {
        case .apply: EmptyView()
        case .reapply:
            Text("Re-applied").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.blue.opacity(0.12), in: Capsule())
                .foregroundStyle(.blue)
        case .revert:
            Text("Reverted").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .foregroundStyle(.orange)
        case .applyColor:
            Text("Color").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.green.opacity(0.12), in: Capsule())
                .foregroundStyle(.green)
        case .removeColor:
            Text("Color removed").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .foregroundStyle(.orange)
        case .applyIconAndColor:
            Text("Icon + Color").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.blue.opacity(0.12), in: Capsule())
                .foregroundStyle(.blue)
        }
    }

    private func reapply(_ entry: HistoryEntry) {
        guard let id = entry.appliedIconID, let icon = iconManager.icon(for: id) else {
            showFeedback("Icon no longer in library.", success: false)
            return
        }
        let url = URL(fileURLWithPath: entry.folderPath)
        let result = iconManager.applyIcon(icon, to: url)
        if result.success {
            historyManager.record(folderPath: entry.folderPath, iconID: icon.id,
                                  iconName: icon.name, originalIconData: result.originalIconData,
                                  action: .reapply)
            showFeedback("Re-applied \"\(icon.name)\" to \(entry.folderName)", success: true)
        } else {
            showFeedback("Failed to apply icon. Check permissions.", success: false)
        }
    }

    private func performRevert(_ entry: HistoryEntry) {
        let ok = historyManager.revert(entry: entry)
        showFeedback(ok
            ? "Reverted \(entry.folderName) successfully."
            : "Revert failed. Check permissions.",
            success: ok)
    }

    private func showFeedback(_ message: String, success: Bool) {
        withAnimation { feedback = (message: message, success: success) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { if feedback?.message == message { feedback = nil } }
        }
    }
}
