import Foundation
import AppKit
import Combine

class HistoryManager: ObservableObject {
    @Published var entries: [HistoryEntry] = []

    private static let storageURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Folio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        load()
        purgeOldUserDefaultsKey()
    }

    func record(folderPath: String, iconID: UUID?, iconName: String,
                colorName: String? = nil, colorHex: String? = nil,
                originalIconData: Data? = nil, action: HistoryAction = .apply) {
        let entry = HistoryEntry(folderPath: folderPath, appliedIconID: iconID,
                                 appliedIconName: iconName, appliedColorName: colorName,
                                 appliedColorHex: colorHex,
                                 originalIconData: originalIconData, action: action)
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        save()
    }

    func recordColorApply(folderPath: String, colorName: String, colorHex: String,
                           originalIconData: Data? = nil) {
        record(folderPath: folderPath, iconID: nil, iconName: "Color: \(colorName)",
               colorName: colorName, colorHex: colorHex,
               originalIconData: originalIconData, action: .applyColor)
    }

    func recordColorRemove(folderPath: String, originalIconData: Data? = nil) {
        record(folderPath: folderPath, iconID: nil, iconName: "Color removed",
               originalIconData: originalIconData, action: .removeColor)
    }

    func recordIconAndColor(folderPath: String, iconID: UUID, iconName: String,
                            colorName: String, colorHex: String,
                            originalIconData: Data? = nil) {
        record(folderPath: folderPath, iconID: iconID, iconName: iconName,
               colorName: colorName, colorHex: colorHex,
               originalIconData: originalIconData, action: .applyIconAndColor)
    }

    @discardableResult
    func revert(entry: HistoryEntry) -> Bool {
        let path = entry.folderPath
        let ok: Bool
        if let data = entry.originalIconData, let image = NSImage(data: data) {
            ok = NSWorkspace.shared.setIcon(image, forFile: path, options: [])
        } else {
            ok = NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
        }
        if ok {
            let label = entry.originalIconData != nil ? "Reverted to previous" : "Default restored"
            record(folderPath: path, iconID: nil, iconName: label, action: .revert)
        }
        return ok
    }

    func revertAll() -> Int {
        let snapshot = entries
        var count = 0
        for entry in snapshot where entry.action != .revert {
            if revert(entry: entry) { count += 1 }
        }
        return count
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence (file-based)

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.storageURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func purgeOldUserDefaultsKey() {
        UserDefaults.standard.removeObject(forKey: "history_entries")
    }
}
