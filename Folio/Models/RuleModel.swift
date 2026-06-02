import Foundation

// MARK: - Condition

enum ConditionOperator: String, Codable, CaseIterable {
    case contains = "Folder name contains"
    case notContains = "Folder name does not contain"
    case equals = "Folder name equals"
    case startsWith = "Folder name starts with"
    case endsWith = "Folder name ends with"
    case wildcard = "Folder name matches (wildcard)"
    case regex = "Folder name matches (regex)"
    case fileExists = "Folder contains a file/folder named"
    case subfolderContains = "Folder has an item containing"
    // Child-matching operators: evaluate the folder's immediate contents (files & folders).
    case hasChildStartingWith = "Folder has an item starting with"
    case hasChildEndingWith = "Folder has an item ending with"
    case hasChildMatchingWildcard = "Folder has an item matching (wildcard)"
    case hasChildMatchingRegex = "Folder has an item matching (regex)"
}

enum LogicOperator: String, Codable, CaseIterable {
    case and = "AND"
    case or = "OR"
}

struct RuleCondition: Identifiable, Codable, Equatable {
    let id: UUID
    var conditionOperator: ConditionOperator
    var value: String

    init(conditionOperator: ConditionOperator = .contains, value: String = "") {
        self.id = UUID()
        self.conditionOperator = conditionOperator
        self.value = value
    }

    func evaluate(folderURL: URL) -> Bool {
        let name = folderURL.lastPathComponent.lowercased()
        let val = value.lowercased()
        let fm = FileManager.default

        switch conditionOperator {
        case .contains:         return name.contains(val)
        case .notContains:      return !name.contains(val)
        case .equals:           return name == val
        case .startsWith:       return name.hasPrefix(val)
        case .endsWith:         return name.hasSuffix(val)
        case .wildcard:
            return NSPredicate(format: "SELF LIKE[c] %@", value).evaluate(with: folderURL.lastPathComponent)
        case .regex:
            return (try? NSRegularExpression(pattern: value))
                .map { $0.firstMatch(in: folderURL.lastPathComponent,
                    range: NSRange(folderURL.lastPathComponent.startIndex..., in: folderURL.lastPathComponent)) != nil } ?? false
        case .fileExists:
            return fm.fileExists(atPath: folderURL.appendingPathComponent(value).path)
        case .subfolderContains:
            let contents = (try? fm.contentsOfDirectory(atPath: folderURL.path)) ?? []
            return contents.contains { $0.lowercased().contains(val) }
        case .hasChildStartingWith:
            return childNames(of: folderURL).contains { $0.lowercased().hasPrefix(val) }
        case .hasChildEndingWith:
            return childNames(of: folderURL).contains { $0.lowercased().hasSuffix(val) }
        case .hasChildMatchingWildcard:
            let pred = NSPredicate(format: "SELF LIKE[c] %@", value)
            return childNames(of: folderURL).contains { pred.evaluate(with: $0) }
        case .hasChildMatchingRegex:
            guard let re = try? NSRegularExpression(pattern: value) else { return false }
            return childNames(of: folderURL).contains {
                re.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
            }
        }
    }

    private func childNames(of folderURL: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path)) ?? []
    }
}

// MARK: - Individual Rule

struct RuleModel: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var conditions: [RuleCondition]
    var logicOperator: LogicOperator
    var iconID: UUID?
    var color: FolderColor?
    var priority: Int
    var isEnabled: Bool
    var stopOnMatch: Bool

    init(name: String, conditions: [RuleCondition] = [], logic: LogicOperator = .and, iconID: UUID? = nil, priority: Int = 0) {
        self.id = UUID()
        self.name = name
        self.conditions = conditions
        self.logicOperator = logic
        self.iconID = iconID
        self.color = nil
        self.priority = priority
        self.isEnabled = true
        self.stopOnMatch = true
    }

    func evaluate(folderURL: URL) -> Bool {
        guard isEnabled, !conditions.isEmpty else { return false }
        switch logicOperator {
        case .and: return conditions.allSatisfy { $0.evaluate(folderURL: folderURL) }
        case .or:  return conditions.contains { $0.evaluate(folderURL: folderURL) }
        }
    }
}

// MARK: - Rule Set

/// How deep (relative to the rule set's trigger/anchor folder) a sub-rule is allowed to match.
/// Depth 1 = a direct child of the anchored folder, 2 = a grandchild, etc.
enum SubRuleDepth: String, Codable, CaseIterable {
    case any          = "Any depth"
    case directChild  = "Direct child"
    case exact        = "Exact level"
    case range        = "Depth range"
}

struct RuleSetRule: Identifiable, Codable, Equatable {
    let id: UUID
    var description: String
    var conditions: [RuleCondition]
    var logicOperator: LogicOperator
    var iconID: UUID?
    var color: FolderColor?
    var applyToSubfolders: Bool
    var depthMode: SubRuleDepth
    var exactDepth: Int
    var minDepth: Int
    var maxDepth: Int
    /// Optional regex matched against the folder's path *relative to the anchor*
    /// (e.g. "src/components"). Empty/nil means no path constraint.
    var pathRegex: String?

    init(description: String, conditions: [RuleCondition] = [], logic: LogicOperator = .and,
         iconID: UUID? = nil, applyToSubfolders: Bool = false,
         depthMode: SubRuleDepth = .directChild, exactDepth: Int = 2,
         minDepth: Int = 1, maxDepth: Int = 3, pathRegex: String? = nil) {
        self.id = UUID()
        self.description = description
        self.conditions = conditions
        self.logicOperator = logic
        self.iconID = iconID
        self.color = nil
        self.applyToSubfolders = applyToSubfolders
        self.depthMode = depthMode
        self.exactDepth = exactDepth
        self.minDepth = minDepth
        self.maxDepth = maxDepth
        self.pathRegex = pathRegex
    }

    // Backward-compatible decoding: older saved sub-rules only had `applyToSubfolders`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        description = try c.decode(String.self, forKey: .description)
        conditions = try c.decode([RuleCondition].self, forKey: .conditions)
        logicOperator = try c.decode(LogicOperator.self, forKey: .logicOperator)
        iconID = try c.decodeIfPresent(UUID.self, forKey: .iconID)
        color = try c.decodeIfPresent(FolderColor.self, forKey: .color)
        let applyToSub = try c.decodeIfPresent(Bool.self, forKey: .applyToSubfolders) ?? false
        applyToSubfolders = applyToSub
        depthMode = try c.decodeIfPresent(SubRuleDepth.self, forKey: .depthMode)
            ?? (applyToSub ? .any : .directChild)
        exactDepth = try c.decodeIfPresent(Int.self, forKey: .exactDepth) ?? 2
        minDepth = try c.decodeIfPresent(Int.self, forKey: .minDepth) ?? 1
        maxDepth = try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 3
        pathRegex = try c.decodeIfPresent(String.self, forKey: .pathRegex)
    }

    /// Whether a folder at `depth` levels below the anchor is within this rule's depth window.
    func depthMatches(_ depth: Int) -> Bool {
        switch depthMode {
        case .any:          return depth >= 1
        case .directChild:  return depth == 1
        case .exact:        return depth == max(1, exactDepth)
        case .range:        return depth >= min(minDepth, maxDepth) && depth <= max(minDepth, maxDepth)
        }
    }

    private func pathMatches(_ relativePath: String) -> Bool {
        guard let rx = pathRegex, !rx.isEmpty else { return true }
        guard let re = try? NSRegularExpression(pattern: rx) else { return false }
        return re.firstMatch(in: relativePath,
                             range: NSRange(relativePath.startIndex..., in: relativePath)) != nil
    }

    private func conditionsMatch(folderURL: URL) -> Bool {
        guard !conditions.isEmpty else { return true }   // depth/path-only rule
        switch logicOperator {
        case .and: return conditions.allSatisfy { $0.evaluate(folderURL: folderURL) }
        case .or:  return conditions.contains { $0.evaluate(folderURL: folderURL) }
        }
    }

    /// Full match used by the engine: depth window + optional path regex + name conditions.
    func matches(folderURL: URL, depth: Int, relativePath: String) -> Bool {
        depthMatches(depth) && pathMatches(relativePath) && conditionsMatch(folderURL: folderURL)
    }

    func evaluate(folderURL: URL) -> Bool {
        guard !conditions.isEmpty else { return false }
        return conditionsMatch(folderURL: folderURL)
    }
}

struct RuleSetModel: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var triggerConditions: [RuleCondition]
    var triggerLogic: LogicOperator
    var rules: [RuleSetRule]
    var rootIconID: UUID?
    var rootColor: FolderColor?
    var priority: Int
    var isEnabled: Bool
    var applyRecursively: Bool
    /// When true, a folder matched by this rule set is "finished" — no lower-priority
    /// rule sets or rules are evaluated for it. When false, the rule set still applies
    /// its styling but evaluation continues, so a lower-priority match can override it.
    var stopOnMatch: Bool
    /// Set on rule sets converted from built-in project templates, so a matching
    /// built-in icon can be auto-assigned to the root once IconManager is ready.
    var projectType: ProjectType?

    init(name: String, description: String = "", triggerConditions: [RuleCondition] = [], rules: [RuleSetRule] = [], priority: Int = 0) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.triggerConditions = triggerConditions
        self.triggerLogic = .and
        self.rules = rules
        self.rootIconID = nil
        self.rootColor = nil
        self.priority = priority
        self.isEnabled = true
        self.applyRecursively = true
        self.stopOnMatch = false
        self.projectType = nil
    }

    // Backward-compatible decoding: `projectType` was added later.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        triggerConditions = try c.decode([RuleCondition].self, forKey: .triggerConditions)
        triggerLogic = try c.decode(LogicOperator.self, forKey: .triggerLogic)
        rules = try c.decode([RuleSetRule].self, forKey: .rules)
        rootIconID = try c.decodeIfPresent(UUID.self, forKey: .rootIconID)
        rootColor = try c.decodeIfPresent(FolderColor.self, forKey: .rootColor)
        priority = try c.decode(Int.self, forKey: .priority)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        applyRecursively = try c.decodeIfPresent(Bool.self, forKey: .applyRecursively) ?? true
        stopOnMatch = try c.decodeIfPresent(Bool.self, forKey: .stopOnMatch) ?? false
        projectType = try c.decodeIfPresent(ProjectType.self, forKey: .projectType)
    }

    var hasAnyIcon: Bool {
        rootIconID != nil || rootColor != nil || rules.contains { $0.iconID != nil || $0.color != nil }
    }

    func isTriggered(by folderURL: URL) -> Bool {
        guard isEnabled, !triggerConditions.isEmpty else { return false }
        return triggerMatches(folderURL)
    }

    /// True when `folderURL` itself satisfies the trigger conditions (ignores `isEnabled`).
    func triggerMatches(_ folderURL: URL) -> Bool {
        guard !triggerConditions.isEmpty else { return false }
        switch triggerLogic {
        case .and: return triggerConditions.allSatisfy { $0.evaluate(folderURL: folderURL) }
        case .or:  return triggerConditions.contains { $0.evaluate(folderURL: folderURL) }
        }
    }

    /// Walks up from `folderURL` (inclusive) and returns the nearest ancestor-or-self
    /// folder that satisfies the trigger — the "workspace root" this set anchors to.
    /// Returns `nil` when no ancestor within `maxDepth` levels triggers the set.
    func anchorFolder(for folderURL: URL, maxDepth: Int = 40) -> URL? {
        guard isEnabled, !triggerConditions.isEmpty else { return nil }
        var current = folderURL.standardizedFileURL
        var depth = 0
        while depth <= maxDepth {
            if triggerMatches(current) { return current }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }   // reached filesystem root
            current = parent
            depth += 1
        }
        return nil
    }
}

