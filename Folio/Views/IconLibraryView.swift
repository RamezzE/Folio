import SwiftUI
internal import UniformTypeIdentifiers

struct IconLibraryView: View {
    @EnvironmentObject var iconManager: IconManager
    @EnvironmentObject var ruleEngine: RuleEngine
    @State private var showAddSheet = false
    @State private var selectedCategoryID: UUID? = nil
    @State private var editMode = false
    @State private var searchText = ""
    @State private var iconToDelete: IconModel?
    @State private var iconUsages: [String] = []
    @State private var showUsageWarning = false
    @State private var showFinalConfirm = false
    @State private var editingIcon: IconModel?
    @State private var showCategoryManager = false
    @State private var importSummary: String?
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showHiddenIcons = false

    var selectedCategoryName: String {
        guard let id = selectedCategoryID else { return "All Categories" }
        return iconManager.categories.first { $0.id == id }?.name ?? "All Categories"
    }

    var filtered: [IconModel] {
        iconManager.icons.filter { icon in
            guard !icon.isHidden else { return false }
            let matchesCategory: Bool
            if let catID = selectedCategoryID {
                matchesCategory = icon.categoryID == catID
            } else {
                matchesCategory = true
            }
            let matchesSearch = searchText.isEmpty ||
                icon.name.localizedCaseInsensitiveContains(searchText) ||
                icon.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            return matchesCategory && matchesSearch
        }
    }

    var hiddenIcons: [IconModel] { iconManager.icons.filter(\.isHidden) }

    var bulkDeleteMessage: String {
        let builtInCount = selectedIDs.filter { id in
            iconManager.icons.first(where: { $0.id == id })?.isBuiltIn == true
        }.count
        let customCount = selectedIDs.count - builtInCount
        var parts: [String] = []
        if customCount > 0 { parts.append("\(customCount) custom icon\(customCount == 1 ? "" : "s") will be permanently deleted") }
        if builtInCount > 0 { parts.append("\(builtInCount) built-in icon\(builtInCount == 1 ? "" : "s") will be hidden (restorable)") }
        return parts.joined(separator: ". ") + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PageHeader(title: "Icon Library")
                Spacer()

                Button { showCategoryManager = true } label: {
                    Label("Categories", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)

                Toggle(isOn: $editMode.onChange { if !$0 { selectedIDs.removeAll() } }) {
                    Label("Edit", systemImage: "pencil")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(editMode ? .orange : nil)

                Button { importIconsFromFolder() } label: {
                    Label("Import Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .help("Import all images from a folder. Filenames matching project types (e.g. react.png) are auto-tagged.")

                Button { showAddSheet = true } label: {
                    Label("Add Icon", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .help("You can also drag any image anywhere in the app to add it here")
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: editMode && !selectedIDs.isEmpty)

            HStack(spacing: 10) {
                SearchField(placeholder: "Search icons or tags…", text: $searchText)

                Menu {
                    Button("All Categories") { selectedCategoryID = nil }
                    Divider()
                    ForEach(iconManager.categories) { category in
                        let count = iconManager.icons.filter { $0.categoryID == category.id && !$0.isHidden }.count
                        Button("\(category.name) (\(count))") { selectedCategoryID = category.id }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(selectedCategoryName).lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if !hiddenIcons.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showHiddenIcons.toggle() }
                    } label: {
                        Label("\(hiddenIcons.count) Hidden", systemImage: showHiddenIcons ? "eye" : "eye.slash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(showHiddenIcons ? Theme.accent : nil)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, editMode && !selectedIDs.isEmpty ? 8 : 16)

            if editMode && !selectedIDs.isEmpty {
                HStack(spacing: 10) {
                    Text("\(selectedIDs.count) selected")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Divider().frame(height: 14)
                    Button("Deselect All") { selectedIDs.removeAll() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                    Spacer()
                    Button {
                        selectedIDs.forEach { id in
                            if let icon = iconManager.icons.first(where: { $0.id == id }) {
                                iconManager.hideIcon(icon)
                            }
                        }
                        selectedIDs.removeAll()
                    } label: {
                        Label("Hide Selected", systemImage: "eye.slash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button(role: .destructive) { showBulkDeleteConfirm = true } label: {
                        Label("Delete Selected", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .foregroundStyle(.red).tint(.red)
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.07))
                .transition(.opacity)
            }

            Divider()

            if iconManager.icons.filter({ !$0.isHidden }).isEmpty && !showHiddenIcons {
                ContentUnavailableView("No icons yet", systemImage: "photo.on.rectangle",
                    description: Text("Add icons via the button above, or drag any PNG, JPEG, TIFF, or ICNS image anywhere in the app."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Hidden icons restore section
                        if showHiddenIcons && !hiddenIcons.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "eye.slash").foregroundStyle(.secondary).font(.caption)
                                    Text("Hidden Icons").font(.subheadline).fontWeight(.semibold)
                                    Text("These icons are hidden from the library but not deleted. Tap Restore to bring them back.")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Restore All") {
                                        hiddenIcons.forEach { iconManager.unhideIcon($0) }
                                    }
                                    .buttonStyle(.bordered).controlSize(.small)
                                }
                                .padding(.horizontal, 24).padding(.top, 16)

                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 16) {
                                    ForEach(hiddenIcons) { icon in
                                        HiddenIconCard(icon: icon) { iconManager.unhideIcon(icon) }
                                    }
                                }
                                .padding(.horizontal, 24).padding(.bottom, 8)

                                Divider().padding(.horizontal, 24).padding(.bottom, 8)
                            }
                        }

                        // Main icon grid
                        if !filtered.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 16) {
                                ForEach(filtered) { icon in
                                    IconCard(
                                        icon: icon,
                                        editMode: editMode,
                                        isSelected: selectedIDs.contains(icon.id),
                                        onDelete: { requestDelete(icon) },
                                        onEdit: { editingIcon = icon },
                                        onHide: { iconManager.hideIcon(icon) },
                                        onToggleSelect: {
                                            if editMode {
                                                if selectedIDs.contains(icon.id) { selectedIDs.remove(icon.id) }
                                                else { selectedIDs.insert(icon.id) }
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(24)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddIconSheet().environmentObject(iconManager)
        }
        .sheet(item: $editingIcon) { icon in
            IconEditorSheet(icon: icon)
                .environmentObject(iconManager)
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagerSheet()
                .environmentObject(iconManager)
        }
        .alert("Import Complete", isPresented: Binding(
            get: { importSummary != nil },
            set: { if !$0 { importSummary = nil } }
        )) {
            Button("OK") { importSummary = nil }
        } message: {
            Text(importSummary ?? "")
        }
        .alert("Icon Is Currently In Use", isPresented: $showUsageWarning) {
            Button("Continue Anyway", role: .destructive) { showFinalConfirm = true }
            Button("Cancel", role: .cancel) { iconToDelete = nil }
        } message: {
            let list = iconUsages.joined(separator: "\n• ")
            Text("\"\(iconToDelete?.name ?? "")\" is assigned to the following rules:\n• \(list)\n\nDeleting it will remove it from all of these rules and cannot be undone.")
        }
        .confirmationDialog(
            iconToDelete?.isBuiltIn == true
                ? "Hide \"\(iconToDelete?.name ?? "")\"?"
                : "Delete \"\(iconToDelete?.name ?? "")\"?",
            isPresented: $showFinalConfirm,
            titleVisibility: .visible
        ) {
            if iconToDelete?.isBuiltIn == true {
                Button("Hide Icon", role: .destructive) {
                    if let icon = iconToDelete { iconManager.hideIcon(icon) }
                    iconToDelete = nil
                }
            } else {
                Button("Delete Permanently", role: .destructive) {
                    if let icon = iconToDelete {
                        ruleEngine.clearIconReferences(icon.id)
                        iconManager.delete(icon)
                    }
                    iconToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { iconToDelete = nil }
        } message: {
            if iconToDelete?.isBuiltIn == true {
                Text("Built-in icons can't be permanently deleted. \"\(iconToDelete?.name ?? "")\" will be hidden from the library. You can restore it anytime from the Hidden Icons section.")
            } else {
                Text("This will permanently remove \"\(iconToDelete?.name ?? "")\" from your library and clear it from any rules that reference it. This cannot be undone.")
            }
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) icons?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete / Hide Selected", role: .destructive) {
                for id in selectedIDs {
                    guard let icon = iconManager.icons.first(where: { $0.id == id }) else { continue }
                    if !icon.isBuiltIn { ruleEngine.clearIconReferences(id) }
                }
                iconManager.deleteIcons(selectedIDs)
                selectedIDs.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(bulkDeleteMessage) }
    }

    private func importIconsFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the DefaultIcons folder (or any folder with icon images)"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "icns"]
        let typeMap: [String: ProjectType] = Dictionary(
            uniqueKeysWithValues: ProjectType.allCases.filter { $0 != .unknown }.map { ($0.rawValue, $0) }
        )

        var added = 0
        var skipped = 0
        let files = (try? FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: nil)) ?? []

        for file in files {
            let ext = file.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            guard let data = try? Data(contentsOf: file) else { continue }

            let stem = file.deletingPathExtension().lastPathComponent
            if iconManager.icons.contains(where: { $0.name.lowercased() == stem.lowercased() }) {
                skipped += 1
                continue
            }
            let type = typeMap[stem.lowercased()]
            iconManager.addIcon(name: stem, type: type, data: data)
            added += 1
        }

        importSummary = "Added \(added) icon\(added == 1 ? "" : "s").\(skipped > 0 ? " Skipped \(skipped) already in library." : "")"
    }

    private func requestDelete(_ icon: IconModel) {
        iconToDelete = icon
        if icon.isBuiltIn {
            // Built-ins skip the usage warning — hiding doesn't break rule references
            showFinalConfirm = true
            return
        }
        let usages = ruleEngine.usages(of: icon.id)
        if usages.isEmpty {
            showFinalConfirm = true
        } else {
            iconUsages = usages
            showUsageWarning = true
        }
    }
}

// MARK: - Hidden icon restore card

private struct HiddenIconCard: View {
    let icon: IconModel
    let onRestore: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let img = icon.nsImage {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(width: 68, height: 68)
                        .grayscale(1)
                        .opacity(0.45)
                }
            }
            .padding(.top, 6)
            Text(icon.name).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .help("Restore \"\(icon.name)\"")
    }
}

// MARK: - Binding onChange helper

extension Binding {
    func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in self.wrappedValue = newValue; handler(newValue) }
        )
    }
}

// MARK: - Icon Editor Sheet

struct IconEditorSheet: View {
    let icon: IconModel
    @EnvironmentObject var iconManager: IconManager
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var selectedCategoryID: UUID?

    init(icon: IconModel) {
        self.icon = icon
        _name = State(initialValue: icon.name)
        _selectedCategoryID = State(initialValue: icon.categoryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Edit Icon").font(.headline)
                Spacer()
                if let img = icon.nsImage {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            TextField("Icon name", text: $name).textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Text("Category:").foregroundStyle(.secondary)
                Picker("Category", selection: $selectedCategoryID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(iconManager.categories) { cat in
                        Text(cat.name).tag(Optional(cat.id))
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 160)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    var updated = icon
                    updated.name = name
                    updated.categoryID = selectedCategoryID
                    iconManager.updateIcon(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(24).frame(width: 400, height: 220)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

// MARK: - Category Manager Sheet

struct CategoryManagerSheet: View {
    @EnvironmentObject var iconManager: IconManager
    @Environment(\.dismiss) var dismiss
    @State private var newCategoryName = ""
    @State private var editingCategory: IconCategory?
    @State private var editName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Manage Categories").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            List {
                ForEach(iconManager.categories) { category in
                    HStack {
                        if editingCategory?.id == category.id {
                            TextField("Name", text: $editName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    var cat = category
                                    cat.name = editName
                                    iconManager.updateCategory(cat)
                                    editingCategory = nil
                                }
                            Button("Save") {
                                var cat = category
                                cat.name = editName
                                iconManager.updateCategory(cat)
                                editingCategory = nil
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        } else {
                            Image(systemName: "folder.fill").foregroundStyle(.secondary)
                            Text(category.name).fontWeight(.medium)
                            if category.isBuiltIn {
                                Text("Built-in").font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                            let count = iconManager.icons.filter { $0.categoryID == category.id }.count
                            Text("\(count) icon\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.tertiary)

                            if !category.isBuiltIn {
                                Button {
                                    editingCategory = category
                                    editName = category.name
                                } label: {
                                    Image(systemName: "pencil").font(.caption)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    iconManager.deleteCategory(category)
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                        .foregroundStyle(count == 0 ? Color.red : Color.secondary.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                                .disabled(count > 0)
                                .help(count > 0 ? "Reassign or remove all \(count) icon\(count == 1 ? "" : "s") in this category before deleting it." : "Delete category")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            HStack {
                TextField("New category name…", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCategory() }
                Button("Add") { addCategory() }
                    .buttonStyle(.bordered)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 450, height: 400)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        iconManager.addCategory(IconCategory(name: trimmed))
        newCategoryName = ""
    }
}

// MARK: - FilterPill

struct FilterPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isSelected
                            ? AnyShapeStyle(Theme.accent)
                            : AnyShapeStyle(isHovered ? Theme.glassHover : Theme.glassFill)
                    )
                )
                .foregroundStyle(isSelected ? .white : .primary.opacity(isHovered ? 1 : 0.85))
                .overlay(Capsule().strokeBorder(
                    isSelected ? Color.clear : Theme.glassStroke, lineWidth: 0.6
                ))
                .scaleEffect(isSelected ? 1.0 : isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - IconCard

struct IconCard: View {
    let icon: IconModel
    let editMode: Bool
    var isSelected: Bool = false
    let onDelete: () -> Void
    let onEdit: () -> Void
    var onHide: () -> Void = {}
    var onToggleSelect: () -> Void = {}
    @EnvironmentObject var iconManager: IconManager
    @State private var isHovered = false

    init(icon: IconModel, editMode: Bool, isSelected: Bool = false,
         onDelete: @escaping () -> Void, onEdit: @escaping () -> Void = {},
         onHide: @escaping () -> Void = {},
         onToggleSelect: @escaping () -> Void = {}) {
        self.icon = icon
        self.editMode = editMode
        self.isSelected = isSelected
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onHide = onHide
        self.onToggleSelect = onToggleSelect
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let img = icon.nsImage {
                    Image(nsImage: img)
                        .resizable().scaledToFit()
                        .frame(width: 68, height: 68)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.glassFill)
                        .frame(width: 68, height: 68)
                }
            }
            .padding(.top, 6)

            Text(icon.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if let catID = icon.categoryID, let cat = iconManager.categories.first(where: { $0.id == catID }) {
                Text(cat.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.accentColor : (editMode ? Color.orange.opacity(0.35) : Color.clear),
                    lineWidth: isSelected ? 2.0 : 1.0
                )
        )
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) { cornerActions }
        .overlay(alignment: .topLeading) {
            if editMode && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .topLeading)))
            }
        }
        .onTapGesture { if editMode { onToggleSelect() } }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: editMode)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        .contextMenu {
            if !icon.isBuiltIn {
                Button("Edit") { onEdit() }
                Button("Hide") { onHide() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            } else {
                Button("Hide", role: .destructive) { onDelete() }
            }
        }
    }

    @ViewBuilder
    private var cornerActions: some View {
        if editMode {
            // In edit mode, show select indicator only (tap selects)
            EmptyView()
        } else if icon.isBuiltIn {
            if isHovered {
                HStack(spacing: 6) {
                    IconCardActionButton(systemName: "eye.slash", tint: .secondary, action: onDelete)
                        .help("Hide icon")
                }
                .padding(6)
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
            }
        } else if isHovered {
            HStack(spacing: 6) {
                IconCardActionButton(systemName: "pencil", tint: Theme.accent, action: onEdit)
                    .help("Edit icon")
                IconCardActionButton(systemName: "eye.slash", tint: .secondary, action: onHide)
                    .help("Hide icon")
                IconCardActionButton(systemName: "trash", tint: .red, action: onDelete)
                    .help("Delete icon")
            }
            .padding(6)
            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
        }
    }
}

// MARK: - Icon card corner controls

private struct IconCardActionButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovered ? .white : tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(hovered ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.15)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(tint.opacity(hovered ? 0 : 0.35), lineWidth: 0.8)
                )
                .shadow(color: tint.opacity(hovered ? 0.3 : 0), radius: 5, y: 2)
                .scaleEffect(hovered ? 1.06 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovered)
    }
}

private struct IconCardBadge: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().strokeBorder(Theme.glassStroke, lineWidth: 0.6))
    }
}

// MARK: - AddIconSheet

struct AddIconSheet: View {
    @EnvironmentObject var iconManager: IconManager
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var selectedCategoryID: UUID? = nil
    @State private var imageData: Data?
    @State private var previewImage: NSImage?

    init(preloadedData: Data? = nil, preloadedName: String = "") {
        _name          = State(initialValue: preloadedName)
        _imageData     = State(initialValue: preloadedData)
        _previewImage  = State(initialValue: preloadedData.flatMap { NSImage(data: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Icon").font(.headline)

            TextField("Icon name", text: $name).textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Text("Category:").foregroundStyle(.secondary)
                Picker("Category", selection: $selectedCategoryID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(iconManager.categories) { cat in
                        Text(cat.name).tag(Optional(cat.id))
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 160)
            }

            Button("Choose Image…") { pickImage() }.buttonStyle(.bordered)

            if let img = previewImage {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button("Add") {
                    if let data = imageData, !name.isEmpty {
                        iconManager.addIcon(name: name, type: nil, data: data)
                        if let catID = selectedCategoryID, var lastIcon = iconManager.icons.last {
                            lastIcon.categoryID = catID
                            iconManager.updateIcon(lastIcon)
                        }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(imageData == nil || name.isEmpty)
            }
        }
        .padding(24).frame(width: 340, height: 400)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            imageData = data
            previewImage = NSImage(data: data)
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        }
    }
}
