import SwiftUI

/// Contents of the status-bar (menu bar) menu. The first item shows and focuses
/// the main window — clicking the menu bar icon and choosing "Open Folio" brings
/// the app to the front (and restores the Dock icon via `activateMainWindow`).
struct MenuBarView: View {
    @EnvironmentObject var iconManager: IconManager
    @EnvironmentObject var ruleEngine: RuleEngine

    var body: some View {
        Button("Open Folio") {
            AppWindowManager.shared.activateMainWindow()
        }
        .keyboardShortcut("o")

        Divider()

        Text("\(iconManager.icons.count) icons · \(ruleEngine.rules.filter(\.isEnabled).count) active rules")

        Divider()

        Button("Quit Folio") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
