import SwiftUI

// MARK: - Top-level Rules View

enum RulesTab: String, CaseIterable {
    case order     = "Priority Order"
    case ruleSets  = "Rule Sets"
    case rules     = "Individual Rules"

    var icon: String {
        switch self {
        case .order:     return "list.number"
        case .rules:     return "line.3.horizontal.decrease"
        case .ruleSets:  return "rectangle.3.group"
        }
    }
}

struct RulesView: View {
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager
    @State private var activeTab: RulesTab = .order
    @State private var editMode = false
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageHeader(title: "Rules")
                Spacer()
                Toggle(isOn: $editMode) {
                    Label("Edit", systemImage: "pencil")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(editMode ? .orange : nil)
                addButton
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 14)

            HStack(spacing: 2) {
                ForEach(RulesTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { activeTab = tab }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon).font(.system(size: 12, weight: activeTab == tab ? .semibold : .regular))
                            Text(tab.rawValue).font(.system(size: 13, weight: activeTab == tab ? .semibold : .regular))
                        }
                        .foregroundStyle(activeTab == tab ? Theme.accent : .secondary)
                        .padding(.vertical, 7).padding(.horizontal, 14)
                        .background {
                            if activeTab == tab {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.accent.opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "tab_bg", in: tabNamespace)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(4)
            .background(Theme.glassFill, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.glassStroke, lineWidth: 0.5))
            .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 14)

            Divider()

            switch activeTab {
            case .order:     EvalOrderTab()
            case .rules:     IndividualRulesTab(editMode: editMode)
            case .ruleSets:  RuleSetsTab(editMode: editMode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("[RulesView] Appeared")
        }
        .onDisappear {
            print("[RulesView] Disappeared")
        }
    }

    @ViewBuilder
    var addButton: some View {
        switch activeTab {
        case .order:     EmptyView()
        case .rules:     AddRuleButton()
        case .ruleSets:  AddRuleSetButton()
        }
    }
}

// MARK: - Unified Priority Order Tab

struct EvalOrderTab: View {
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager
    @State private var showEnabledOnly = true

    var visibleItems: [EvalItem] {
        guard showEnabledOnly else { return ruleEngine.evalOrder }
        return ruleEngine.evalOrder.filter { item in
            switch item.kind {
            case .ruleSet:  return ruleEngine.ruleSets.first(where:  { $0.id == item.id })?.isEnabled == true
            case .rule:     return ruleEngine.rules.first(where:     { $0.id == item.id })?.isEnabled == true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag to reorder. Rules are checked from top to bottom. Lower matching rules can override higher ones.")
                    Text("Keep general rules near the top and specific rules near the bottom.")
                }
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.9))

                Spacer()
                Toggle("Enabled only", isOn: $showEnabledOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.glassFill)

            Divider()

            if ruleEngine.evalOrder.isEmpty {
                ContentUnavailableView("No rules yet",
                    systemImage: "list.number",
                    description: Text("Add rule sets or individual rules to start building your priority order."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleItems.isEmpty {
                ContentUnavailableView("No enabled items",
                    systemImage: "checkmark.circle",
                    description: Text("All items are currently disabled. Toggle \"Enabled only\" off to see everything."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleItems) { item in
                        EvalOrderRow(item: item)
                    }
                    .onMove { from, to in
                        if showEnabledOnly {
                            // Map visible indices back to the full evalOrder before moving
                            let movedIDs = from.map { visibleItems[$0].id }
                            let destinationID = to < visibleItems.count ? visibleItems[to].id : nil
                            var full = ruleEngine.evalOrder
                            let removed = movedIDs.compactMap { id in full.firstIndex(where: { $0.id == id }) }
                                .sorted(by: >)
                                .map { idx -> EvalItem in let item = full[idx]; full.remove(at: idx); return item }
                                .reversed()
                            let insertAt: Int
                            if let destID = destinationID, let idx = full.firstIndex(where: { $0.id == destID }) {
                                insertAt = idx
                            } else {
                                insertAt = full.count
                            }
                            full.insert(contentsOf: removed, at: insertAt)
                            for i in full.indices { full[i].order = i }
                            ruleEngine.evalOrder = full
                            ruleEngine.saveEvalOrderPublic()
                        } else {
                            ruleEngine.moveEvalItems(from: from, to: to)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EvalOrderRow: View {
    let item: EvalItem
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager

    var label: String {
        switch item.kind {
        case .ruleSet:  return ruleEngine.ruleSets.first(where:  { $0.id == item.id })?.name ?? "Unknown rule set"
        case .rule:     return ruleEngine.rules.first(where:     { $0.id == item.id })?.name ?? "Unknown rule"
        }
    }

    var isEnabled: Bool {
        switch item.kind {
        case .ruleSet:  return ruleEngine.ruleSets.first(where:  { $0.id == item.id })?.isEnabled ?? false
        case .rule:     return ruleEngine.rules.first(where:     { $0.id == item.id })?.isEnabled ?? false
        }
    }

    var iconID: UUID? {
        switch item.kind {
        case .ruleSet:  return ruleEngine.ruleSets.first(where:  { $0.id == item.id })?.rootIconID
        case .rule:     return ruleEngine.rules.first(where:     { $0.id == item.id })?.iconID
        }
    }

    var color: FolderColor? {
        switch item.kind {
        case .ruleSet:  return ruleEngine.ruleSets.first(where:  { $0.id == item.id })?.rootColor
        case .rule:     return ruleEngine.rules.first(where:     { $0.id == item.id })?.color
        }
    }

    var kindLabel: String {
        switch item.kind {
        case .ruleSet:  return "Rule Set"
        case .rule:     return "Rule"
        }
    }

    var kindColor: Color {
        switch item.kind {
        case .ruleSet:  return .purple
        case .rule:     return .orange
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary).font(.caption)

            Text(kindLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(kindColor)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(kindColor.opacity(0.15), in: Capsule())

            Text(label).fontWeight(.medium)

            Spacer()

            if let color { ColorSwatch(color: color) }

            if let id = iconID, let icon = iconManager.icon(for: id), let img = icon.nsImage {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if !isEnabled {
                Text("Off").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Tab info banner

struct EvaluationOrderBanner: View {
    let currentStep: Int  // unused but kept for call-site compatibility

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.number").foregroundStyle(.secondary).font(.caption)
            Text("Evaluation order is set in the Priority Order tab. Items are checked top-to-bottom; first match wins.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Theme.glassFill)
    }
}

// MARK: - Position badge

struct PositionBadge: View {
    let number: Int

    var body: some View {
        Text("#\(number)")
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Individual Rules Tab

struct AddRuleButton: View {
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: { Label("Add Rule", systemImage: "plus") }
            .buttonStyle(.borderedProminent)
            .sheet(isPresented: $showSheet) {
                RuleEditorSheet(rule: nil) { ruleEngine.addRule($0) }
                    .environmentObject(iconManager)
            }
    }
}

enum RuleStatusFilter: String, CaseIterable {
    case all = "All"
    case enabled = "Enabled"
    case disabled = "Disabled"
}

struct IndividualRulesTab: View {
    let editMode: Bool
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager
    @State private var editingRule: RuleModel?
    @State private var ruleToDelete: RuleModel?
    @State private var searchText = ""
    @State private var statusFilter: RuleStatusFilter = .all
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false

    var filteredRules: [RuleModel] {
        ruleEngine.rules.filter { rule in
            let matchesSearch =
                searchText.isEmpty ||
                rule.name.localizedCaseInsensitiveContains(searchText)

            let matchesStatus: Bool
            switch statusFilter {
            case .all: matchesStatus = true
            case .enabled: matchesStatus = rule.isEnabled
            case .disabled: matchesStatus = !rule.isEnabled
            }

            return matchesSearch && matchesStatus
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            EvaluationOrderBanner(currentStep: 3)

            HStack(spacing: 8) {
                SearchField(placeholder: "Search rules…", text: $searchText)

                HStack(spacing: 4) {
                    ForEach(RuleStatusFilter.allCases, id: \.self) { f in
                        FilterPill(label: f.rawValue, isSelected: statusFilter == f) { statusFilter = f }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            if editMode && !selectedIDs.isEmpty {
                HStack(spacing: 10) {
                    Text("\(selectedIDs.count) selected")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Divider().frame(height: 14)
                    Button("Deselect All") { selectedIDs.removeAll() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                    Spacer()
                    Button("Enable All") {
                        selectedIDs.forEach { id in
                            if var r = ruleEngine.rules.first(where: { $0.id == id }) {
                                r.isEnabled = true; ruleEngine.updateRule(r)
                            }
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button("Disable All") {
                        selectedIDs.forEach { id in
                            if var r = ruleEngine.rules.first(where: { $0.id == id }) {
                                r.isEnabled = false; ruleEngine.updateRule(r)
                            }
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button(role: .destructive) { showBulkDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered).controlSize(.small).foregroundStyle(.red).tint(.red)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.07))
                .transition(.opacity)
            }

            Divider()

            if ruleEngine.rules.isEmpty {
                ContentUnavailableView("No rules", systemImage: "line.3.horizontal.decrease",
                    description: Text("Add rules to auto-assign icons based on folder names."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRules.isEmpty {
                ContentUnavailableView("No results", systemImage: "magnifyingglass",
                    description: Text("Try adjusting your search or filter."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(filteredRules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 8) {
                            if editMode {
                                Image(systemName: selectedIDs.contains(rule.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(rule.id) ? Color.accentColor : .secondary)
                                    .font(.system(size: 18))
                                    .onTapGesture {
                                        if selectedIDs.contains(rule.id) { selectedIDs.remove(rule.id) }
                                        else { selectedIDs.insert(rule.id) }
                                    }
                            }
                            PositionBadge(number: index + 1)
                            IndividualRuleRow(rule: rule, editMode: editMode)

                            if editMode {
                                HStack(spacing: 6) {
                                    RowActionButton(systemName: "pencil", tint: Color(NSColor.controlAccentColor)) { editingRule = rule }
                                        .help("Edit rule")
                                    RowActionButton(systemName: "trash", tint: .red) { ruleToDelete = rule }
                                        .help("Delete rule")
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
                            }
                        }
                        .listRowBackground(selectedIDs.contains(rule.id) ? Color.accentColor.opacity(0.07) : Color.clear)
                        .contextMenu {
                            Button("Edit") { editingRule = rule }
                            Button("Delete", role: .destructive) { ruleToDelete = rule }
                        }
                    }
                    .onMove { from, to in
                        var visible = filteredRules
                        visible.move(fromOffsets: from, toOffset: to)
                        var newRules = ruleEngine.rules
                        for moved in visible {
                            if let i = newRules.firstIndex(where: { $0.id == moved.id }) { newRules.remove(at: i) }
                        }
                        newRules.insert(contentsOf: visible, at: 0)
                        for (i, var r) in newRules.enumerated() { r.priority = i; ruleEngine.updateRule(r) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .sheet(item: $editingRule) { rule in
                    RuleEditorSheet(rule: rule) { ruleEngine.updateRule($0) }
                        .environmentObject(iconManager)
                }
                .confirmationDialog("Delete \"\(ruleToDelete?.name ?? "")\"?",
                                    isPresented: Binding(get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }),
                                    titleVisibility: .visible) {
                    Button("Delete Rule", role: .destructive) {
                        if let r = ruleToDelete { ruleEngine.deleteRule(r) }
                        ruleToDelete = nil
                    }
                    Button("Cancel", role: .cancel) { ruleToDelete = nil }
                } message: {
                    Text("This will permanently delete the rule \"\(ruleToDelete?.name ?? "")\".")
                }
                .confirmationDialog("Delete \(selectedIDs.count) rules?",
                                    isPresented: $showBulkDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete Rules", role: .destructive) {
                        ruleEngine.rules.removeAll { selectedIDs.contains($0.id) }
                        selectedIDs.removeAll()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This will permanently delete \(selectedIDs.count) rules. This cannot be undone.") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: editMode) { _, isOn in if !isOn { selectedIDs.removeAll() } }
    }
}

struct IndividualRuleRow: View {
    let rule: RuleModel
    var editMode: Bool = false
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager
    @State private var showNoIconWarning = false

    var conditionSummary: String {
        rule.conditions.map { "\($0.conditionOperator.rawValue) \"\($0.value)\"" }
            .joined(separator: " \(rule.logicOperator.rawValue) ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    if newValue && rule.iconID == nil && rule.color == nil { showNoIconWarning = true }
                    else { var r = rule; r.isEnabled = newValue; ruleEngine.updateRule(r) }
                }
            )).labelsHidden().toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name).fontWeight(.medium)
                Text(conditionSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if let color = rule.color { ColorSwatch(color: color, size: editMode ? 22 : 16) }

            if let id = rule.iconID, let icon = iconManager.icon(for: id) {
                IconBadge(icon: icon, size: editMode ? 28 : 18)
            }
        }
        .padding(.vertical, editMode ? 6 : 4)
        .opacity(rule.isEnabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: editMode)
        .alert("No Icon Assigned", isPresented: $showNoIconWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Assign an icon or color to \"\(rule.name)\" before enabling it.")
        }
    }
}

// MARK: - Rule Sets Tab

struct AddRuleSetButton: View {
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: { Label("Add Rule Set", systemImage: "plus") }
            .buttonStyle(.borderedProminent)
            .sheet(isPresented: $showSheet) {
                RuleSetEditorSheet(ruleSet: nil) { ruleEngine.addRuleSet($0) }
                    .environmentObject(iconManager)
            }
    }
}

struct RuleSetsTab: View {
    let editMode: Bool
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager
    @State private var editingSet: RuleSetModel?
    @State private var setToDelete: RuleSetModel?
    @State private var searchText = ""
    @State private var statusFilter: RuleStatusFilter = .all
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false

    var filteredSets: [RuleSetModel] {
        ruleEngine.ruleSets.filter { set in
            let matchesSearch =
                searchText.isEmpty ||
                set.name.localizedCaseInsensitiveContains(searchText)

            let matchesStatus: Bool
            switch statusFilter {
            case .all: matchesStatus = true
            case .enabled: matchesStatus = set.isEnabled
            case .disabled: matchesStatus = !set.isEnabled
            }

            return matchesSearch && matchesStatus
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            EvaluationOrderBanner(currentStep: 2)

            HStack(spacing: 8) {
                SearchField(placeholder: "Search rule sets…", text: $searchText)

                HStack(spacing: 4) {
                    ForEach(RuleStatusFilter.allCases, id: \.self) { f in
                        FilterPill(label: f.rawValue, isSelected: statusFilter == f) { statusFilter = f }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            if editMode && !selectedIDs.isEmpty {
                HStack(spacing: 10) {
                    Text("\(selectedIDs.count) selected")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Divider().frame(height: 14)
                    Button("Deselect All") { selectedIDs.removeAll() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                    Spacer()
                    Button("Enable All") {
                        selectedIDs.forEach { id in
                            if var s = ruleEngine.ruleSets.first(where: { $0.id == id }) {
                                s.isEnabled = true; ruleEngine.updateRuleSet(s)
                            }
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button("Disable All") {
                        selectedIDs.forEach { id in
                            if var s = ruleEngine.ruleSets.first(where: { $0.id == id }) {
                                s.isEnabled = false; ruleEngine.updateRuleSet(s)
                            }
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button(role: .destructive) { showBulkDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered).controlSize(.small).foregroundStyle(.red).tint(.red)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.07))
                .transition(.opacity)
            }

            Divider()

            if ruleEngine.ruleSets.isEmpty {
                ContentUnavailableView("No rule sets", systemImage: "rectangle.3.group",
                    description: Text("Group related rules together. e.g. \"GitHub Workspace\" applies different icons to subfolders."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSets.isEmpty {
                ContentUnavailableView("No results", systemImage: "magnifyingglass",
                    description: Text("Try adjusting your search or filter."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(filteredSets.enumerated()), id: \.element.id) { index, set in
                        HStack(spacing: 8) {
                            if editMode {
                                Image(systemName: selectedIDs.contains(set.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(set.id) ? Color.accentColor : .secondary)
                                    .font(.system(size: 18))
                                    .onTapGesture {
                                        if selectedIDs.contains(set.id) { selectedIDs.remove(set.id) }
                                        else { selectedIDs.insert(set.id) }
                                    }
                            }
                            PositionBadge(number: index + 1)
                            RuleSetRow(ruleSet: set)

                            if editMode {
                                HStack(spacing: 6) {
                                    RowActionButton(systemName: "pencil", tint: Color(NSColor.controlAccentColor)) { editingSet = set }
                                        .help("Edit rule set")
                                    RowActionButton(systemName: "trash", tint: .red) { setToDelete = set }
                                        .help("Delete rule set")
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
                            }
                        }
                        .listRowBackground(selectedIDs.contains(set.id) ? Color.accentColor.opacity(0.07) : Color.clear)
                        .contextMenu {
                            Button("Edit") { editingSet = set }
                            Button("Delete", role: .destructive) { setToDelete = set }
                        }
                    }
                    .onMove { from, to in
                        var arr = ruleEngine.ruleSets
                        arr.move(fromOffsets: from, toOffset: to)
                        for (i, var s) in arr.enumerated() { s.priority = i; ruleEngine.updateRuleSet(s) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .sheet(item: $editingSet) { set in
                    RuleSetEditorSheet(ruleSet: set) { ruleEngine.updateRuleSet($0) }
                        .environmentObject(iconManager)
                }
                .confirmationDialog("Delete \"\(setToDelete?.name ?? "")\"?",
                                    isPresented: Binding(get: { setToDelete != nil }, set: { if !$0 { setToDelete = nil } }),
                                    titleVisibility: .visible) {
                    Button("Delete Rule Set", role: .destructive) {
                        if let s = setToDelete { ruleEngine.deleteRuleSet(s) }
                        setToDelete = nil
                    }
                    Button("Cancel", role: .cancel) { setToDelete = nil }
                } message: {
                    Text("This will permanently delete the rule set \"\(setToDelete?.name ?? "")\" and all \(setToDelete?.rules.count ?? 0) of its sub-rules. This cannot be undone.")
                }
                .confirmationDialog("Delete \(selectedIDs.count) rule sets?",
                                    isPresented: $showBulkDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete Rule Sets", role: .destructive) {
                        ruleEngine.ruleSets.removeAll { selectedIDs.contains($0.id) }
                        selectedIDs.removeAll()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This will permanently delete \(selectedIDs.count) rule sets and all their sub-rules. This cannot be undone.") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: editMode) { _, isOn in if !isOn { selectedIDs.removeAll() } }
    }
}

struct RuleSetRow: View {
    let ruleSet: RuleSetModel
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var iconManager: IconManager
    @State private var showNoIconWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { ruleSet.isEnabled },
                    set: { newValue in
                        if newValue && !ruleSet.hasAnyIcon { showNoIconWarning = true }
                        else { var s = ruleSet; s.isEnabled = newValue; ruleEngine.updateRuleSet(s) }
                    }
                )).labelsHidden().toggleStyle(.switch)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ruleSet.name).fontWeight(.medium)
                    if !ruleSet.description.isEmpty {
                        Text(ruleSet.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(ruleSet.rules.count) sub-rule\(ruleSet.rules.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
            if !ruleSet.rules.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ruleSet.rules.prefix(3)) { rule in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary)
                            Text(rule.description).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let color = rule.color { ColorSwatch(color: color, size: 12) }
                            if let id = rule.iconID, let icon = iconManager.icon(for: id) {
                                Text(icon.name).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if ruleSet.rules.count > 3 {
                        Text("+ \(ruleSet.rules.count - 3) more…").font(.caption2).foregroundStyle(.tertiary).padding(.leading, 18)
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 6)
        .opacity(ruleSet.isEnabled ? 1 : 0.45)
        .alert("No Icon Assigned", isPresented: $showNoIconWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Assign at least one icon or color (root or sub-rule) to \"\(ruleSet.name)\" before enabling it.")
        }
    }
}

// MARK: - Individual Rule Editor

struct RuleEditorSheet: View {
    let rule: RuleModel?
    let onSave: (RuleModel) -> Void
    @EnvironmentObject var iconManager: IconManager
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var conditions: [RuleCondition]
    @State private var logicOperator: LogicOperator
    @State private var selectedIconID: UUID?
    @State private var priority: Int
    @State private var stopOnMatch: Bool
    @State private var selectedColor: FolderColor?
    @State private var showIconPicker = false

    init(rule: RuleModel?, onSave: @escaping (RuleModel) -> Void) {
        self.rule = rule; self.onSave = onSave
        _name = State(initialValue: rule?.name ?? "")
        _conditions = State(initialValue: rule?.conditions ?? [RuleCondition()])
        _logicOperator = State(initialValue: rule?.logicOperator ?? .and)
        _selectedIconID = State(initialValue: rule?.iconID)
        _priority = State(initialValue: rule?.priority ?? 0)
        _stopOnMatch = State(initialValue: rule?.stopOnMatch ?? true)
        _selectedColor = State(initialValue: rule?.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(rule == nil ? "New Rule" : "Edit Rule").font(.headline)

            TextField("Rule name", text: $name).textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Conditions").font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Picker("", selection: $logicOperator) {
                        ForEach(LogicOperator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 120)
                    Button { conditions.append(RuleCondition()) } label: { Image(systemName: "plus.circle") }
                        .buttonStyle(.plain).foregroundStyle(Color(NSColor.controlAccentColor))
                }
                ForEach($conditions) { $condition in
                    ConditionRow(condition: $condition) {
                        conditions.removeAll { $0.id == condition.id }
                    }
                }
            }

            HStack(alignment: .center, spacing: 16) {
                CombinedFolderPreview(selectedIconID: selectedIconID, selectedColor: selectedColor)

                VStack(alignment: .leading, spacing: 12) {
                    IconPickerButton(selectedIconID: $selectedIconID, showPicker: $showIconPicker)
                    FolderColorPicker(selectedColor: $selectedColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Stop on match", isOn: $stopOnMatch)
                Text("When on, a folder that matches this rule is finished — no lower-priority rules or templates are checked for it. Turn off to let other rules keep matching and stack on top.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    var r = rule ?? RuleModel(name: name)
                    r.name = name; r.conditions = conditions; r.logicOperator = logicOperator
                    r.iconID = selectedIconID; r.color = selectedColor; r.priority = priority; r.stopOnMatch = stopOnMatch
                    if selectedIconID == nil && selectedColor == nil { r.isEnabled = false }
                    onSave(r); dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || conditions.isEmpty)
            }
        }
        .padding(24).frame(width: 650, height: 520)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .sheet(isPresented: $showIconPicker) {
            IconPickerSheet(title: "for rule") { icon in selectedIconID = icon.id }
                .environmentObject(iconManager)
        }
    }
}

struct ConditionRow: View {
    @Binding var condition: RuleCondition
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $condition.conditionOperator) {
                    ForEach(ConditionOperator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).frame(width: 250)
            TextField("value", text: $condition.value).textFieldStyle(.roundedBorder)
            Button(action: onDelete) { Image(systemName: "minus.circle").foregroundStyle(.red) }
                .buttonStyle(.plain)
        }
    }
}

// MARK: - Rule Set Section Header

struct RuleSetSectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
            if let subtitle {
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Rule Set Editor

struct RuleSetEditorSheet: View {
    let ruleSet: RuleSetModel?
    let onSave: (RuleSetModel) -> Void
    @EnvironmentObject var iconManager: IconManager
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var description: String
    @State private var triggerConditions: [RuleCondition]
    @State private var triggerLogic: LogicOperator
    @State private var subRules: [RuleSetRule]
    @State private var rootIconID: UUID?
    @State private var rootColor: FolderColor?
    @State private var applyRecursively: Bool
    @State private var stopOnMatch: Bool
    @State private var showRootIconPicker = false
    /// Defers sub-rule card rendering until after the sheet's initial frame is
    /// drawn, so the sheet opens instantly and the cards fade in.
    @State private var subRulesVisible = false

    init(ruleSet: RuleSetModel?, onSave: @escaping (RuleSetModel) -> Void) {
        self.ruleSet = ruleSet; self.onSave = onSave
        _name = State(initialValue: ruleSet?.name ?? "")
        _description = State(initialValue: ruleSet?.description ?? "")
        _triggerConditions = State(initialValue: ruleSet?.triggerConditions ?? [RuleCondition()])
        _triggerLogic = State(initialValue: ruleSet?.triggerLogic ?? .and)
        _subRules = State(initialValue: ruleSet?.rules ?? [])
        _rootIconID = State(initialValue: ruleSet?.rootIconID)
        _rootColor = State(initialValue: ruleSet?.rootColor)
        _applyRecursively = State(initialValue: ruleSet?.applyRecursively ?? true)
        _stopOnMatch = State(initialValue: ruleSet?.stopOnMatch ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Fixed header ──────────────────────────────────────────────
            HStack {
                Text(ruleSet == nil ? "New Rule Set" : "Edit Rule Set")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

            Divider()

            HStack(alignment: .top, spacing: 0) {

                // LEFT COLUMN (SCROLLABLE)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {

                        // ── Section: Identity ─────────────────────────────
                        RuleSetSectionHeader(title: "Identity",
                                             subtitle: "Give this rule set a recognisable name.")
                            .padding(.bottom, 10)

                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Rule set name (e.g. GitHub Workspace)", text: $name)
                                .textFieldStyle(.roundedBorder)
                            TextField("Description (optional)", text: $description)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.bottom, 24)

                        Divider().padding(.bottom, 24)

                        // ── Section: Trigger ──────────────────────────────
                        HStack(alignment: .top) {
                            RuleSetSectionHeader(title: "Trigger",
                                                 subtitle: "Which folder names activate this rule set?")
                            Spacer()
                            Button {
                                triggerConditions.append(RuleCondition())
                            } label: {
                                Label("Add condition", systemImage: "plus").font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(NSColor.controlAccentColor))
                        }
                        .padding(.bottom, 12)

                        if triggerConditions.isEmpty {
                            Text("No conditions yet — add one to define when this rule set activates.")
                                .font(.caption).foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("Match:")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Picker("", selection: $triggerLogic) {
                                        ForEach(LogicOperator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                    .pickerStyle(.segmented).frame(width: 120)
                                    Spacer()
                                }
                                ForEach($triggerConditions) { $cond in
                                    ConditionRow(condition: $cond) {
                                        triggerConditions.removeAll { $0.id == $cond.id }
                                    }
                                }
                            }
                        }

                        Color.clear.frame(height: 24)
                        Divider().padding(.bottom, 24)

                        // ── Section: Sub-rules ────────────────────────────
                        HStack(alignment: .top) {
                            RuleSetSectionHeader(title: "Sub-rules",
                                                 subtitle: "Style subfolders inside the triggered folder.")
                            Spacer()
                            Button {
                                subRules.append(RuleSetRule(description: "New sub-rule"))
                            } label: {
                                Label("Add sub-rule", systemImage: "plus").font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                        .padding(.bottom, 12)

                        if subRules.isEmpty {
                            Text("No sub-rules yet. Add one to style subfolders by name.")
                                .font(.caption).foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                        } else if !subRulesVisible {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(subRules) { rule in
                                    SubRuleSkeletonCard(label: rule.description.isEmpty ? "Sub-rule" : rule.description)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach($subRules) { $subRule in
                                    SubRuleRow(subRule: $subRule, icons: iconManager.icons) {
                                        subRules.removeAll { $0.id == $subRule.id }
                                    }
                                }
                            }
                            .transition(.opacity.animation(.easeIn(duration: 0.2)))
                        }

                        Color.clear.frame(height: 24)
                        Divider().padding(.bottom, 24)

                        // ── Section: Behavior ─────────────────────────────
                        RuleSetSectionHeader(title: "Behavior", subtitle: nil)
                            .padding(.bottom, 10)

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Stop on match", isOn: $stopOnMatch)
                            Text("When on, a matched folder skips all lower-priority rules. Turn off to let other rules stack on top.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(24)
                }
                .frame(maxHeight: .infinity)

                Divider()

                // RIGHT COLUMN — also scrollable so preview never clips
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .center, spacing: 12) {
                            CombinedFolderPreview(selectedIconID: rootIconID, selectedColor: rootColor)

                            VStack(alignment: .leading, spacing: 14) {
                                IconPickerButton(
                                    selectedIconID: $rootIconID,
                                    showPicker: $showRootIconPicker,
                                    label: "Root folder icon:"
                                )

                                FolderColorPicker(selectedColor: $rootColor)
                            }
                        }

                        RuleSetLogicPreview(
                            triggerConditions: triggerConditions,
                            triggerLogic: triggerLogic,
                            subRules: subRules,
                            rootIconID: rootIconID,
                            rootColor: rootColor
                        )
                    }
                    .padding(24)
                }
                .frame(maxHeight: .infinity)
                .frame(width: 380)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    var s = ruleSet ?? RuleSetModel(name: name)
                    s.name = name; s.description = description
                    s.triggerConditions = triggerConditions; s.triggerLogic = triggerLogic
                    s.rules = subRules; s.rootIconID = rootIconID; s.rootColor = rootColor
                    s.applyRecursively = applyRecursively; s.stopOnMatch = stopOnMatch

                    let anyAppearance = rootIconID != nil || rootColor != nil
                        || subRules.contains { $0.iconID != nil || $0.color != nil }

                    if !anyAppearance { s.isEnabled = false }

                    onSave(s)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 1020, height: 680)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .task {
            // Let SwiftUI complete the first layout pass with the skeleton,
            // then cross-fade in the real sub-rule cards.
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeInOut(duration: 0.25)) { subRulesVisible = true }
        }
        .sheet(isPresented: $showRootIconPicker) {
            IconPickerSheet(title: "root folder") { icon in rootIconID = icon.id }
                .environmentObject(iconManager)
        }
    }
}

// MARK: - Sub-rule skeleton (shown while cards are loading)

struct SubRuleSkeletonCard: View {
    let label: String
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            // Folder icon placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(shimmer)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                // Name bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 11)

                // Condition bar (shorter)
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmer)
                        .frame(width: 140, height: 9)
                    Spacer()
                }
            }

            Spacer()

            // Color swatch placeholder
            RoundedRectangle(cornerRadius: 5)
                .fill(shimmer)
                .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmer: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .secondary.opacity(0.10), location: max(0, phase - 0.3)),
                .init(color: .secondary.opacity(0.22), location: phase),
                .init(color: .secondary.opacity(0.10), location: min(1, phase + 0.3)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct SubRuleRow: View {
    @Binding var subRule: RuleSetRule
    let icons: [IconModel]
    let onDelete: () -> Void
    @EnvironmentObject var iconManager: IconManager
    @State private var showIconPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Name row ─────────────────────────────────────────────────
            HStack(spacing: 8) {
                TextField("Name (e.g. \"src\", \"components\")", text: $subRule.description)
                    .textFieldStyle(.roundedBorder)
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            Divider().padding(.bottom, 14)

            // ── Appearance ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("APPEARANCE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.5)

                HStack(alignment: .center, spacing: 12) {
                    CombinedFolderPreview(selectedIconID: subRule.iconID, selectedColor: subRule.color, size: 40)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Button(subRule.iconID == nil ? "Choose Icon…" : "Change Icon") { showIconPicker = true }
                                .buttonStyle(.bordered).controlSize(.small)
                            if subRule.iconID != nil {
                                Button { subRule.iconID = nil } label: {
                                    Image(systemName: "xmark").font(.caption2)
                                }.buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Clear icon")
                            }
                        }

                        FolderColorPicker(selectedColor: $subRule.color)
                    }
                }
            }
            .padding(.bottom, 14)

            Divider().padding(.bottom, 14)

            // ── Matching ─────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("MATCHING")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.5)

                SubRuleDepthControls(subRule: $subRule)

                if !subRule.conditions.isEmpty {
                    HStack(spacing: 8) {
                        Text("Conditions match:").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $subRule.logicOperator) {
                            ForEach(LogicOperator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 100)
                    }
                    ForEach($subRule.conditions) { $cond in
                        ConditionRow(condition: $cond) { subRule.conditions.removeAll { $0.id == cond.id } }
                    }
                }

                Button { subRule.conditions.append(RuleCondition()) } label: {
                    Label("Add condition", systemImage: "plus").font(.caption)
                }.buttonStyle(.plain).foregroundStyle(Color(NSColor.controlAccentColor))
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 10)
        .sheet(isPresented: $showIconPicker) {
            IconPickerSheet(title: "sub-rule") { icon in subRule.iconID = icon.id }
                .environmentObject(iconManager)
        }
    }
}

/// Depth-window + optional relative-path regex controls for a sub-rule.
struct SubRuleDepthControls: View {
    @Binding var subRule: RuleSetRule
    @State private var useRawRegex: Bool

    init(subRule: Binding<RuleSetRule>) {
        self._subRule = subRule
        let rx = subRule.wrappedValue.pathRegex ?? ""
        let isSimple = rx.isEmpty || (rx.hasPrefix("^") && rx.hasSuffix("/"))
        self._useRawRegex = State(initialValue: !isSimple)
    }

    /// Extracts the parent folder name from a `^name/` regex, or nil if not that pattern.
    private var parsedParentFolder: String {
        guard let rx = subRule.pathRegex, rx.hasPrefix("^"), rx.hasSuffix("/") else { return "" }
        return String(rx.dropFirst().dropLast())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Depth ────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Text("Depth:").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $subRule.depthMode) {
                    ForEach(SubRuleDepth.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(width: 130)

                switch subRule.depthMode {
                case .exact:
                    Stepper(value: $subRule.exactDepth, in: 1...12) {
                        Text("level \(subRule.exactDepth)").font(.caption).monospacedDigit()
                    }.frame(width: 130)
                case .range:
                    HStack(spacing: 4) {
                        Stepper(value: $subRule.minDepth, in: 1...12) {
                            Text("\(subRule.minDepth)").font(.caption).monospacedDigit()
                        }
                        Text("–").foregroundStyle(.secondary)
                        Stepper(value: $subRule.maxDepth, in: 1...12) {
                            Text("\(subRule.maxDepth)").font(.caption).monospacedDigit()
                        }
                    }
                default:
                    EmptyView()
                }
                Spacer()
            }
            .help("Depth is measured from the folder that triggers this rule set. 1 = a direct child, 2 = a grandchild, and so on.")

            // ── Path constraint ───────────────────────────────────────────
            if useRawRegex {
                // Advanced: raw regex
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField("e.g. ^src/components$", text: Binding(
                        get: { subRule.pathRegex ?? "" },
                        set: { subRule.pathRegex = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    Button("Simple") {
                        subRule.pathRegex = nil
                        useRawRegex = false
                    }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(Color(NSColor.controlAccentColor))
                    .help("Switch back to the guided path picker and clear the custom regex.")
                }
                .help("Matched against the folder's path relative to the trigger folder. Leave empty to ignore.")
            } else {
                // Simple: parent-folder picker
                HStack(spacing: 6) {
                    Text("Inside folder:")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. src", text: Binding(
                        get: { parsedParentFolder },
                        set: { val in
                            let t = val.trimmingCharacters(in: .whitespaces)
                            subRule.pathRegex = t.isEmpty ? nil : "^\(t)/"
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    Button("Regex…") { useRawRegex = true }
                        .buttonStyle(.plain).font(.caption2).foregroundStyle(.tertiary)
                        .help("Switch to a raw regex for advanced path matching.")
                }
                .help("Only match subfolders whose relative path starts with this folder name. e.g. \"src\" matches src/components, src/utils, etc. Leave empty for any path.")
            }
        }
    }
}

// MARK: - Rule Set Logic Preview

/// Renders a plain-language, tree-style summary of what a rule set does:
/// which folder activates it, and how its subfolders get styled.
struct RuleSetLogicPreview: View {
    let triggerConditions: [RuleCondition]
    let triggerLogic: LogicOperator
    let subRules: [RuleSetRule]
    let rootIconID: UUID?
    let rootColor: FolderColor?
    @EnvironmentObject var iconManager: IconManager

    private func summary(_ conditions: [RuleCondition], _ logic: LogicOperator) -> String {
        guard !conditions.isEmpty else { return "any folder" }
        return conditions
            .map { "\($0.conditionOperator.rawValue) \"\($0.value)\"" }
            .joined(separator: " \(logic.rawValue) ")
    }

    /// A friendly example folder name from a sub-rule's first condition.
    private func exampleName(_ subRule: RuleSetRule) -> String {
        let v = subRule.conditions.first?.value.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? "matching folder" : v
    }

    private func depthLabel(_ s: RuleSetRule) -> String {
        switch s.depthMode {
        case .any:          return "any depth"
        case .directChild:  return "direct child"
        case .exact:        return "level \(max(1, s.exactDepth))"
        case .range:        return "levels \(min(s.minDepth, s.maxDepth))–\(max(s.minDepth, s.maxDepth))"
        }
    }

    private func examplePath(_ s: RuleSetRule) -> String {
        if let rx = s.pathRegex, !rx.isEmpty {
            // Friendly rendering for the simple "inside folder" pattern (^name/)
            if rx.hasPrefix("^"), rx.hasSuffix("/") {
                let parent = String(rx.dropFirst().dropLast())
                return "\(parent)/\(exampleName(s))"
            }
            return rx
        }
        switch s.depthMode {
        case .directChild:  return exampleName(s)
        case .exact where s.exactDepth <= 1: return exampleName(s)
        default:            return "…/\(exampleName(s))"
        }
    }

    var hasRootStyle: Bool { rootIconID != nil || rootColor != nil }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Trigger
                if triggerConditions.isEmpty {
                    Label("No trigger set — this set never activates.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "folder.badge.gearshape").foregroundStyle(Theme.accentSoft)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Activates on a folder that \(summary(triggerConditions, triggerLogic))")
                                .font(.callout)
                            Text("(checked on the folder and its parent folders)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }

                Divider()

                // Tree
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        CombinedFolderPreview(selectedIconID: rootIconID, selectedColor: rootColor, size: 28)
                        Text("root folder").fontWeight(.medium)
                        if !hasRootStyle {
                            Text("no style").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }

                    if subRules.isEmpty && !hasRootStyle {
                        Text("No styling yet — add a sub-rule or a root icon/color.")
                            .font(.caption).foregroundStyle(.tertiary).padding(.leading, 36)
                    }

                    ForEach(subRules) { sub in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                            CombinedFolderPreview(selectedIconID: sub.iconID, selectedColor: sub.color, size: 22)
                            Text(examplePath(sub))
                                .font(.system(.callout, design: .monospaced))
                            Text("(\(depthLabel(sub)))").font(.caption2).foregroundStyle(.tertiary)
                            if sub.iconID == nil && sub.color == nil {
                                Text("no style").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        .padding(.leading, 14)
                    }
                }

                Divider()

                Text("Each sub-rule matches subfolders within its depth window (level 1 = a direct child of the triggered folder). Add a path regex to constrain by relative path.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("Preview — how this reads", systemImage: "wand.and.stars")
                .font(.subheadline).fontWeight(.medium).padding(.bottom, 4)
        }
    }

}

// MARK: - Shared helpers

/// Shows a single folder preview that merges icon + color:
///  - both set  → custom icon tinted with color
///  - icon only → custom icon as-is
///  - color only → default folder tinted with color
///  - neither   → plain folder outline
struct CombinedFolderPreview: View {
    let selectedIconID: UUID?
    let selectedColor: FolderColor?
    var size: CGFloat = 48
    @EnvironmentObject var iconManager: IconManager
    @State private var image: NSImage?

    private var cacheKey: String {
        "\(selectedIconID?.uuidString ?? "nil")-\(selectedColor?.rawValue ?? "nil")"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: size, height: size)

            if let img = image {
                Image(nsImage: img)
                    .resizable().scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .transition(.opacity)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        }
        .animation(.easeIn(duration: 0.15), value: image != nil)
        .task(id: cacheKey) {
            image = await resolveImage()
        }
    }

    private func resolveImage() async -> NSImage? {
        let iconID = selectedIconID
        let color = selectedColor

        return await Task.detached(priority: .userInitiated) { [iconManager] in
            if let id = iconID, let icon = await iconManager.icon(for: id), let base = await icon.nsImage {
                if let c = color {
                    return await iconManager.previewTintedIcon(base, color: c.nsColor)
                }
                return base
            }
            if let c = color {
                return await iconManager.previewTintedFolder(color: c.nsColor)
            }
            return nil
        }.value
    }
}

struct IconPickerButton: View {
    @Binding var selectedIconID: UUID?
    @Binding var showPicker: Bool
    var label: String = "Apply icon:"
    @EnvironmentObject var iconManager: IconManager

    var body: some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            if let id = selectedIconID, let icon = iconManager.icon(for: id), let img = icon.nsImage {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(icon.name).font(.caption).foregroundStyle(.secondary)
            }
            Button(selectedIconID == nil ? "Choose…" : "Change") { showPicker = true }
                .buttonStyle(.bordered).controlSize(.small)
            if selectedIconID != nil {
                Button { selectedIconID = nil } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                .help("Clear icon")
            }
        }
    }
}

struct ColorSwatch: View {
    let color: FolderColor
    var size: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(nsColor: color.nsColor))
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .help(color.displayName)
    }
}

// MARK: - Row action button (edit mode)

struct RowActionButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovered ? .white : tint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hovered ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
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

struct IconBadge: View {
    let icon: IconModel
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 5) {
            if let img = icon.nsImage {
                Image(nsImage: img).resizable().scaledToFit().frame(width: size, height: size)
            }
            Text(icon.name).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, size > 22 ? 6 : 5)
        .background(.secondary.opacity(0.12), in: Capsule())
    }
}
