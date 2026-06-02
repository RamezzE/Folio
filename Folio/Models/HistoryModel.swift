import Foundation

enum HistoryAction: String, Codable {
    case apply = "apply"
    case revert = "revert"
    case reapply = "reapply"
    case applyColor = "apply_color"
    case removeColor = "remove_color"
    case applyIconAndColor = "apply_icon_and_color"
}

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    var folderPath: String
    var folderName: String
    var appliedIconID: UUID?
    var appliedIconName: String
    var appliedColorName: String?
    var appliedColorHex: String?
    var timestamp: Date
    var originalIconData: Data?
    var action: HistoryAction

    init(folderPath: String, appliedIconID: UUID?, appliedIconName: String,
         appliedColorName: String? = nil, appliedColorHex: String? = nil,
         originalIconData: Data? = nil, action: HistoryAction = .apply) {
        self.id = UUID()
        self.folderPath = folderPath
        self.folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        self.appliedIconID = appliedIconID
        self.appliedIconName = appliedIconName
        self.appliedColorName = appliedColorName
        self.appliedColorHex = appliedColorHex
        self.timestamp = Date()
        self.originalIconData = originalIconData
        self.action = action
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var folderExists: Bool {
        FileManager.default.fileExists(atPath: folderPath)
    }

    var actionDescription: String {
        switch action {
        case .apply:            return "Applied icon"
        case .revert:           return "Reverted"
        case .reapply:          return "Re-applied"
        case .applyColor:       return "Applied color"
        case .removeColor:      return "Removed color"
        case .applyIconAndColor: return "Applied icon + color"
        }
    }
}
