import SwiftUI

enum SidebarItem: String, CaseIterable, Hashable {
    case dashboard = "Dashboard"
    case projects  = "Apply"
    case rules     = "Rules"
    case history   = "History"
    case icons     = "Icon Library"

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .projects:  return "folder.fill"
        case .rules:     return "slider.horizontal.3"
        case .history:   return "clock.arrow.circlepath"
        case .icons:     return "photo.on.rectangle.angled"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "Overview & recent activity"
        case .projects:  return "Apply icons & colors to folders"
        case .rules:     return "Auto-assign icons by folder name"
        case .history:   return "Review & revert past changes"
        case .icons:     return "Manage your icon collection"
        }
    }
}
