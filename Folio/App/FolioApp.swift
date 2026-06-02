import SwiftUI

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var historyManager = HistoryManager()
    @StateObject private var iconManager: IconManager
    @StateObject private var ruleEngine: RuleEngine
    @StateObject private var appState = AppState.shared
    @StateObject private var projectsModel = ProjectsModel()

    init() {
        let iconManager = IconManager()

        _iconManager = StateObject(wrappedValue: iconManager)
        _ruleEngine = StateObject(wrappedValue: RuleEngine(iconManager: iconManager))
    }

    var body: some Scene {
        Window("Folio", id: "main") {
            ContentView()
                .environmentObject(historyManager)
                .environmentObject(iconManager)
                .environmentObject(ruleEngine)
                .environmentObject(appState)
                .environmentObject(projectsModel)
                .frame(minWidth: 1120, minHeight: 740)
                .task {
                    ruleEngine.syncDefaultIconsForRuleSets(from: iconManager)
                    AnalyticsService.recordLaunch()
                }
                .onAppear {
                    StatusBarController.shared.attach(iconManager: iconManager, ruleEngine: ruleEngine)
                    AppState.shared.terminationHandler = { [p = projectsModel] in p.cancelApplyTask() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 780)
        .windowResizability(.contentMinSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        StatusBarController.shared.setUp()
    }

    /// Keep the app (and its menu-bar item) alive when the main window is closed.
    /// Without this, closing the single window terminates the whole app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Fired when the app is re-activated (e.g. relaunched from Finder). Bring
    /// the main window back to the foreground.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindowManager.shared.activateMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppWindowManager.shared.isTerminating = true

        // Cancel any in-flight apply task first.
        AppState.shared.terminationHandler?()

        // Allow cancellation to propagate briefly on the main run loop
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Intentionally empty — cleanup is done in applicationShouldTerminate
        // so it completes before exit() is called.
    }
}

/// Manages showing/hiding the main window while keeping the app dock-icon-free.
///
/// The app runs as an `.accessory` (no Dock icon), so the system won't manage
/// window activation for us. This delegate keeps the single main window alive
/// across close (we hide instead of destroy) and centralises the logic for
/// bringing it back to the foreground and giving it focus.
class AppWindowManager: NSObject, NSWindowDelegate {
    static let shared = AppWindowManager()

    /// Set to true by AppDelegate before termination so windowShouldClose
    /// allows the window to close cleanly instead of blocking the quit.
    var isTerminating = false

    private weak var mainWindow: NSWindow?

    private var foundMainWindow: NSWindow? {
        if let w = mainWindow { return w }
        return NSApp.windows.first { $0.identifier?.rawValue == "main" || $0.title == "Folio" }
    }

    /// Register the window so we can hide/restore and re-focus it later.
    func register(_ window: NSWindow) {
        mainWindow = window
        window.delegate = self
    }

    /// Show, activate, and focus the main window — handling the accessory-app
    /// cases: app hidden, app not frontmost, or the window currently hidden.
    func activateMainWindow() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate(ignoringOtherApps: true)

        if let win = foundMainWindow {
            register(win)
            win.makeKeyAndOrderFront(nil)
            // orderFrontRegardless ensures the window appears even though the
            // app may not be the active app yet.
            win.orderFrontRegardless()
        }
    }

    /// Keep the window alive when the user clicks the red close button — hide it
    /// instead of destroying it, so it can be restored instantly from the menu
    /// bar without SwiftUI having to recreate the scene.
    ///
    /// During app termination (dock quit, Cmd-Q) we allow the close to proceed
    /// normally; blocking it during termination causes a crash.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isTerminating { return true }
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}

/// Owns the menu-bar status item. A left-click shows (and focuses) the main
/// window; a right-click (or control-click) opens a small menu with the same
/// "Open Folio" action, a live status line, and Quit.
///
/// SwiftUI's `MenuBarExtra` always pops its menu on click, so to get a direct
/// left-click action we manage an AppKit `NSStatusItem` ourselves.
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    var quitRequested = false
    private var statusItem: NSStatusItem?
    private weak var iconManager: IconManager?
    private weak var ruleEngine: RuleEngine?

    /// Create the status-bar item. Safe to call once at launch.
    func setUp() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "paintbrush.fill", accessibilityDescription: "Folio")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    /// Wire up the live data shown in the right-click menu. Called from the
    /// window's `onAppear` once SwiftUI has created the model objects.
    func attach(iconManager: IconManager, ruleEngine: RuleEngine) {
        self.iconManager = iconManager
        self.ruleEngine = ruleEngine
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        // let isRightClick = event?.type == .rightMouseUp
        //     || event?.modifierFlags.contains(.control) == true
        let isLeftClick = event?.type == .leftMouseUp
            && !event!.modifierFlags.contains(.control)

        // Right click opens menu
        if isLeftClick {
            showMenu()
        }

        // Left click does nothing
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "Open Folio", action: #selector(openWindow), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let iconCount = iconManager?.icons.count ?? 0
        let ruleCount = ruleEngine?.rules.filter(\.isEnabled).count ?? 0
        let info = NSMenuItem(title: "\(iconCount) icons · \(ruleCount) active rules", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Folio", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Temporarily attach the menu and trigger it, then detach so the next
        // left-click runs the open-window action again instead of the menu.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openWindow() {
        AppWindowManager.shared.activateMainWindow()
    }

    @objc private func quitApp() {
        quitRequested = true
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}
