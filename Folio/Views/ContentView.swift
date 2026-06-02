import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var iconManager: IconManager
    @EnvironmentObject var ruleEngine: RuleEngine

    @State private var isDraggingOver = false
    @State private var droppedIcon: DroppedIconPayload? = nil

    @StateObject private var startupUpdater = UpdateChecker()
    @State private var pendingUpdate: AvailableRelease?

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ZStack {
                switch appState.selectedTab {
                case .dashboard:
                    DashboardView()
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                                                removal: .opacity))
                case .projects:
                    ProjectsView()
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                                                removal: .opacity))
                case .rules:
                    RulesView()
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                                                removal: .opacity))
                case .history:
                    HistoryView()
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                                                removal: .opacity))
                case .icons:
                    IconLibraryView()
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                                                removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .FolioBackground()
            .animation(.easeInOut(duration: 0.22), value: appState.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onDrop(of: [.image, .png, .jpeg, .tiff, .fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
        }
        .overlay(alignment: .bottom) {
            if isDraggingOver {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Drop to add to Icon Library")
                }
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color.accentColor, in: Capsule())
                .shadow(radius: 8, y: 4)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: isDraggingOver)
        .sheet(item: $droppedIcon) { payload in
            AddIconSheet(preloadedData: payload.data, preloadedName: payload.name)
                .environmentObject(iconManager)
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(iconManager)
                .environmentObject(ruleEngine)
                .environmentObject(historyManager)
        }
        .sheet(item: $pendingUpdate) { release in
            UpdatePromptView(release: release, updater: startupUpdater)
        }
        .onAppear {
            // Register the main window so it can be hidden/restored and re-focused
            // from the menu bar. The window is visible, so show the Dock icon.
            if let win = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.isKeyWindow || $0.title == "Folio" }) {
                AppWindowManager.shared.register(win)
            }
        }
        .task {
            // Check for updates once on startup; surface a prompt if one is
            // available and hasn't been skipped.
            pendingUpdate = await startupUpdater.checkAtStartup()
        }
    }

    @discardableResult
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = item as? URL }
                guard let url, let data = try? Data(contentsOf: url) else { return }
                DispatchQueue.main.async {
                    droppedIcon = DroppedIconPayload(data: data, name: url.deletingPathExtension().lastPathComponent)
                }
            }
            return true
        }

        for type in ["public.png", "public.jpeg", "public.tiff", "public.image"] {
            guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                guard let data else { return }
                DispatchQueue.main.async {
                    droppedIcon = DroppedIconPayload(data: data, name: "Dropped Icon")
                }
            }
            return true
        }

        return false
    }
}

struct DroppedIconPayload: Identifiable {
    let id = UUID()
    let data: Data
    let name: String
}
