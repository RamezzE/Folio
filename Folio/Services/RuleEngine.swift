import Foundation
import Combine
import SwiftUI

// MARK: - Evaluation Result

struct EvaluationResult {
    let folderURL: URL
    let iconID: UUID?
    let color: FolderColor?
    let matchedBy: String
    let matchName: String
}

// MARK: - Unified eval item (drives priority ordering)

struct EvalItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case ruleSet, rule }
    var id: UUID
    var kind: Kind
    var order: Int
}

// MARK: - RuleEngine

class RuleEngine: ObservableObject {
    @Published var rules: [RuleModel] = []
    @Published var ruleSets: [RuleSetModel] = []
    @Published var evalOrder: [EvalItem] = []
    
    private let iconManager: IconManager

    private let rulesKey      = "saved_rules_v2"
    private let setsKey       = "saved_rule_sets"
    private let evalOrderKey  = "saved_eval_order"
    private let defaultRulesKey = "default_rules_populated_v1"
    private let defaultRuleSetsKey = "default_rule_sets_populated_v2"
    /// Set to true by "Reset Everything" to permanently suppress default regeneration
    /// until the user explicitly chooses "Restore Defaults".
    static let defaultsSuppressedKey = "defaults_suppressed"

    /// Name of the default rule set whose root icon is wired up once IconManager is ready.
    static let nodeRuleSetName = "Node Project"

    init(iconManager: IconManager) {
        self.iconManager = iconManager
        load()
        populateDefaultRulesIfNeeded()
        populateDefaultRuleSetsIfNeeded()
        rebuildEvalOrderIfNeeded()
    }

    // MARK: - Evaluation (unified priority order)

    func evaluate(folderURL: URL) -> EvaluationResult? {
        // Walk the priority order top-to-bottom. A match whose item has `stopOnMatch`
        // enabled is final and returned immediately. Otherwise the match is held as
        // `pending` and evaluation continues, letting a lower-priority item override it.
        var pending: EvaluationResult? = nil

        for item in evalOrder {
            var matched: EvaluationResult? = nil
            var stopOnMatch = true

            switch item.kind {

            case .ruleSet:
                guard let rs = ruleSets.first(where: { $0.id == item.id && $0.isEnabled }),
                      let anchor = rs.anchorFolder(for: folderURL) else { continue }
                stopOnMatch = rs.stopOnMatch

                let folderPath = folderURL.standardizedFileURL.path
                let isAnchorItself = anchor.path == folderPath

                if isAnchorItself {
                    // This folder is the workspace root — apply its root styling (if any).
                    if rs.rootIconID != nil || rs.rootColor != nil {
                        matched = EvaluationResult(folderURL: folderURL, iconID: rs.rootIconID, color: rs.rootColor,
                                                   matchedBy: "ruleset", matchName: rs.name)
                    }
                } else {
                    // This folder is nested inside the anchored workspace — try sub-rules.
                    let anchorComps = anchor.pathComponents
                    let folderComps = folderURL.standardizedFileURL.pathComponents
                    let depth = folderComps.count - anchorComps.count
                    let relativePath = folderComps.suffix(max(0, depth)).joined(separator: "/")
                    for subRule in rs.rules where (subRule.iconID != nil || subRule.color != nil) {
                        if subRule.matches(folderURL: folderURL, depth: depth, relativePath: relativePath) {
                            matched = EvaluationResult(folderURL: folderURL, iconID: subRule.iconID, color: subRule.color,
                                                       matchedBy: "ruleset",
                                                       matchName: "\(rs.name) → \(subRule.description)")
                            break
                        }
                    }
                }

            case .rule:
                guard let r = rules.first(where: { $0.id == item.id }),
                      r.evaluate(folderURL: folderURL),
                      (r.iconID != nil || r.color != nil) else { continue }
                stopOnMatch = r.stopOnMatch
                matched = EvaluationResult(folderURL: folderURL, iconID: r.iconID, color: r.color,
                                           matchedBy: "rule", matchName: r.name)
            }

            if let matched {
                pending = matched
                if stopOnMatch { return matched }
            }
        }
        return pending
    }

    func matchingIconID(for folderURL: URL) -> UUID? {
        evaluate(folderURL: folderURL)?.iconID
    }

    func applyIconsToSubfolders(of projectURL: URL) -> [(URL, UUID)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        let subfolders = contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        var assignments: [(URL, UUID)] = []
        for folder in subfolders {
            guard !assignments.contains(where: { $0.0 == folder }) else { continue }
            for item in evalOrder where item.kind == .ruleSet {
                guard let rs = ruleSets.first(where: { $0.id == item.id && $0.isEnabled }),
                      rs.isTriggered(by: projectURL) else { continue }
                for subRule in rs.rules {
                    if subRule.evaluate(folderURL: folder), let iconID = subRule.iconID {
                        assignments.append((folder, iconID)); break
                    }
                }
                if assignments.contains(where: { $0.0 == folder }) { break }
            }
            if assignments.contains(where: { $0.0 == folder }) { continue }
            if let result = evaluate(folderURL: folder), let iconID = result.iconID {
                assignments.append((folder, iconID))
            }
        }
        return assignments
    }

    // MARK: - Default Rules

    private func populateDefaultRulesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.defaultsSuppressedKey) else { return }
        guard !UserDefaults.standard.bool(forKey: defaultRulesKey) else { return }
        UserDefaults.standard.set(true, forKey: defaultRulesKey)

        // let defaults: [(name: String, patterns: [String])] = [
        //     // ("Frontend",      ["frontend", "client", "web", "ui"]),
        //     // ("Backend",       ["backend", "server", "api", "services"]),
        //     // ("Components",    ["components", "shared-components", "ui-components"]),
        //     // ("Utilities",     ["utils", "utilities", "helpers", "lib"]),
        //     // ("Source",        ["src", "source"]),
        //     // ("Models",        ["models", "entities", "schemas"]),
        //     // ("Supabase",      ["supabase"]),
        //     // ("Firebase",      ["firebase"]),
        //     // ("Database",      ["db", "database", "migrations"]),
        //     // ("Assets",        ["assets", "images", "fonts", "media"]),
        //     // ("Tests",         ["tests", "__tests__", "spec", "specs"]),
        //     // ("Python Env",    ["venv", ".env", "virtualenv"]),
        //     // ("Configuration", ["config", "configs", "settings"]),
        // ]

        // for def in defaults {
        //     let conditions = def.patterns.map { RuleCondition(conditionOperator: .equals, value: $0) }
        //     var rule = RuleModel(name: def.name, conditions: conditions, logic: .or, priority: rules.count)
        //     rule.isEnabled = false
        //     addRule(rule)
        // }
    }

    // MARK: - Default Rule Sets

    private func populateDefaultRuleSetsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.defaultsSuppressedKey) else { return }
        if UserDefaults.standard.bool(forKey: defaultRuleSetsKey) { return }

        // ── Upgrade cleanup ───────────────────────────────────────────────
        // Earlier versions detected a project by its *folder name* (a folder
        // literally named "react"), which breaks the moment the folder is named
        // after the product. These defaults detect by folder *contents* instead.
        // Remove any previously-shipped default sets (matched by the names we've
        // ever shipped) so regenerating doesn't leave duplicates behind. Custom
        // user sets are untouched.
        let shippedNames: Set<String> = [
            "Git Project", "Git Repository", "Monorepo", "Backend Service",
            "Docker", "Docker Project", "Terraform", "Terraform / Infra",
            "Firebase", "Firebase Project", "Supabase", "Supabase Project",
            "Node Project", "React Project", "React / Next.js",
            "Vue Project", "Vue / Nuxt", "Svelte Project", "Svelte",
            "Angular Project", "Angular", "Python Project", "Django Project",
            "Go Project", "Rust Project", "Java Project", "Kotlin Project",
            "C# / .NET Project", "Ruby Project", "PHP Project", "Elixir Project",
            "C / C++ Project", "iOS / Swift Project", "Android Project",
            "Flutter Project",
        ]
        let staleIDs = Set(ruleSets.filter { shippedNames.contains($0.name) }.map(\.id))
        if !staleIDs.isEmpty {
            ruleSets.removeAll { staleIDs.contains($0.id) }
            evalOrder.removeAll { staleIDs.contains($0.id) }
        }

        // ── Trigger builders (content-based — never folder-name based) ────
        // A project root is matched by the marker files/dirs it *contains*, so
        // detection works no matter what the folder itself is named.
        func exists(_ name: String) -> RuleCondition {
            RuleCondition(conditionOperator: .fileExists, value: name)
        }
        func childStarts(_ prefix: String) -> RuleCondition {
            RuleCondition(conditionOperator: .hasChildStartingWith, value: prefix)
        }
        func childEnds(_ suffix: String) -> RuleCondition {
            RuleCondition(conditionOperator: .hasChildEndingWith, value: suffix)
        }

        // ── Sub-rule builder (colors conventional *subfolder* names) ──────
        // Sub-rules still match by name on purpose: folders like src/, tests/,
        // and assets/ follow strong conventions and are never the project name.
        func rule(_ description: String, _ value: String, color: FolderColor, depth: SubRuleDepth = .any) -> RuleSetRule {
            var r = RuleSetRule(description: description,
                                conditions: [RuleCondition(conditionOperator: .equals, value: value)],
                                depthMode: depth)
            r.color = color
            return r
        }

        // ── Icon-set builder ──────────────────────────────────────────────
        func iconSet(name: String, desc: String, triggers: [RuleCondition],
                     type: ProjectType, logic: LogicOperator = .or,
                     subRules: [RuleSetRule] = [], enabled: Bool = true) -> RuleSetModel {
            var s = RuleSetModel(name: name, description: desc,
                                 triggerConditions: triggers,
                                 rules: subRules, priority: ruleSets.count)
            s.triggerLogic = logic
            s.isEnabled = enabled
            s.projectType = type   // lets syncDefaultIconsForRuleSets restore the root icon
            s.rootIconID = iconManager.icon(for: type)?.id
            return s
        }

        // ── Shared subfolder palette (JS/TS web projects) ─────────────────
        // src/components gets a distinct blue only when nested inside src/.
        var srcComponentsRule = RuleSetRule(
            description: "src/components",
            conditions: [RuleCondition(conditionOperator: .equals, value: "components")],
            depthMode: .any)
        srcComponentsRule.color = .blue
        srcComponentsRule.pathRegex = "^src/"

        let commonSubRules: [RuleSetRule] = [
            rule("Source",     "src",        color: .yellow, depth: .directChild),
            srcComponentsRule,
            rule("Components", "components", color: .blue),
            rule("Utils",      "utils",      color: .green),
            rule("Lib",        "lib",        color: .green),
            rule("Assets",     "assets",     color: .orange),
            rule("Public",     "public",     color: .gray),
            rule("Tests",      "tests",      color: .red),
            rule("Hooks",      "hooks",      color: .purple),
            rule("Pages",      "pages",      color: .blue),
            rule("Styles",     "styles",     color: .pink),
            rule("Config",     "config",     color: .gray),
            rule("Scripts",    "scripts",    color: .yellow),
        ]

        // ═══════════════════════════════════════════════════════════════════
        // Sets are added GENERAL → SPECIFIC. The engine lets a lower-priority
        // (more specific) match override a higher one, so broad sets sit on top
        // (Git, Monorepo) and precise frameworks sit below — React overrides
        // Node, Django overrides Python, etc. Reorder freely in the Rules tab.
        // ═══════════════════════════════════════════════════════════════════

        // 1 — Git Repository (broadest: any repo). Color-only, no root icon.
        var gitSet = RuleSetModel(
            name: "Git Repository",
            description: "Any folder containing a .git directory. Colors common development subfolders.",
            triggerConditions: [exists(".git")],
            rules: commonSubRules, priority: ruleSets.count)
        gitSet.isEnabled = true
        addRuleSet(gitSet)

        // 2 — Monorepo / Workspace (a workspace manifest at the root).
        let monoSubRules: [RuleSetRule] = [
            rule("Apps",     "apps",     color: .blue),
            rule("Packages", "packages", color: .purple),
            rule("Shared",   "shared",   color: .green),
            rule("Tools",    "tools",    color: .orange),
            rule("Infra",    "infra",    color: .red),
            rule("Docs",     "docs",     color: .gray),
        ]
        var monoSet = RuleSetModel(
            name: "Monorepo",
            description: "Detected via pnpm-workspace, turbo, nx, or lerna config. Highlights apps/, packages/, shared/.",
            triggerConditions: [
                childStarts("pnpm-workspace"),
                exists("turbo.json"),
                exists("nx.json"),
                exists("lerna.json"),
            ],
            rules: monoSubRules, priority: ruleSets.count)
        monoSet.triggerLogic = .or
        monoSet.isEnabled = true
        addRuleSet(monoSet)

        // 3 — Docker (infra wrapper; a real project icon overrides the root).
        addRuleSet(iconSet(name: "Docker",
                           desc: "Detected via a Dockerfile or a compose file.",
                           triggers: [exists("Dockerfile"), childStarts("docker-compose"), childStarts("compose.")],
                           type: .docker,
                           subRules: [
                               rule("Services", "services",  color: .blue),
                               rule("Volumes",  "volumes",   color: .orange),
                               rule("Configs",  "configs",   color: .gray),
                           ]))

        // 4 — Terraform / Infrastructure (.tf files at the root).
        addRuleSet(iconSet(name: "Terraform",
                           desc: "Detected via .tf files or a .terraform directory.",
                           triggers: [childEnds(".tf"), exists(".terraform")],
                           type: .terraform,
                           subRules: [
                               rule("Modules",   "modules",   color: .blue),
                               rule("Envs",      "envs",      color: .orange),
                               rule("Variables", "variables", color: .gray),
                           ]))

        // 5 — Firebase (firebase.json). Service layer: frameworks override root.
        addRuleSet(iconSet(name: "Firebase",
                           desc: "Detected via firebase.json or .firebaserc.",
                           triggers: [exists("firebase.json"), exists(".firebaserc")],
                           type: .firebase))

        // 6 — Supabase (a supabase/ directory). Colors functions/migrations.
        addRuleSet(iconSet(name: "Supabase",
                           desc: "Detected via a supabase directory.",
                           triggers: [exists("supabase")],
                           type: .supabase,
                           subRules: [
                               rule("Functions",  "functions",  color: .green),
                               rule("Migrations", "migrations", color: .orange),
                               rule("Seed",       "seed",       color: .blue),
                           ]))

        // ── JavaScript / TypeScript stack (Node general → frameworks) ─────

        // 7 — Node Project (package.json).
        addRuleSet(iconSet(name: "Node Project",
                           desc: "Detected via package.json.",
                           triggers: [exists("package.json")],
                           type: .node,
                           subRules: commonSubRules))

        // 8 — React / Next.js (next.config.*). Overrides Node.
        addRuleSet(iconSet(name: "React / Next.js",
                           desc: "Detected via a next.config file.",
                           triggers: [childStarts("next.config")],
                           type: .react,
                           subRules: commonSubRules))

        // 9 — Vue / Nuxt (nuxt.config.* or vue.config.js).
        addRuleSet(iconSet(name: "Vue / Nuxt",
                           desc: "Detected via nuxt.config or vue.config.",
                           triggers: [childStarts("nuxt.config"), exists("vue.config.js")],
                           type: .vue,
                           subRules: commonSubRules))

        // 10 — Svelte / SvelteKit (svelte.config.*).
        addRuleSet(iconSet(name: "Svelte",
                           desc: "Detected via a svelte.config file.",
                           triggers: [childStarts("svelte.config")],
                           type: .svelte,
                           subRules: commonSubRules))

        // 11 — Angular (angular.json).
        addRuleSet(iconSet(name: "Angular",
                           desc: "Detected via angular.json.",
                           triggers: [exists("angular.json")],
                           type: .angular,
                           subRules: commonSubRules))

        // ── Python stack ──────────────────────────────────────────────────

        // 12 — Python Project (requirements / pyproject / setup / Pipfile).
        addRuleSet(iconSet(name: "Python Project",
                           desc: "Detected via requirements.txt, pyproject.toml, setup.py, or Pipfile.",
                           triggers: [exists("requirements.txt"), exists("pyproject.toml"),
                                      exists("setup.py"), exists("Pipfile")],
                           type: .python,
                           subRules: [
                               rule("App",   "app",   color: .blue),
                               rule("Tests", "tests", color: .red),
                               rule("Venv",  "venv",  color: .gray),
                           ]))

        // 13 — Django (manage.py). Overrides Python.
        addRuleSet(iconSet(name: "Django Project",
                           desc: "Detected via manage.py.",
                           triggers: [exists("manage.py")],
                           type: .django,
                           subRules: [
                               rule("Apps",      "apps",      color: .blue),
                               rule("Templates", "templates", color: .orange),
                               rule("Static",    "static",    color: .gray),
                               rule("Media",     "media",     color: .yellow),
                           ]))

        // ── Other languages ───────────────────────────────────────────────

        // 14 — Go (go.mod).
        addRuleSet(iconSet(name: "Go Project",
                           desc: "Detected via go.mod.",
                           triggers: [exists("go.mod")],
                           type: .go,
                           subRules: [
                               rule("Cmd",      "cmd",      color: .blue),
                               rule("Internal", "internal", color: .purple),
                               rule("Pkg",      "pkg",      color: .green),
                           ]))

        // 15 — Rust (Cargo.toml).
        addRuleSet(iconSet(name: "Rust Project",
                           desc: "Detected via Cargo.toml.",
                           triggers: [exists("Cargo.toml")],
                           type: .rust,
                           subRules: [
                               rule("Src",      "src",      color: .orange),
                               rule("Tests",    "tests",    color: .red),
                               rule("Examples", "examples", color: .blue),
                           ]))

        // 16 — Java (pom.xml or build.gradle).
        addRuleSet(iconSet(name: "Java Project",
                           desc: "Detected via pom.xml or build.gradle.",
                           triggers: [exists("pom.xml"), exists("build.gradle")],
                           type: .java,
                           subRules: [
                               rule("Main",      "main",      color: .blue),
                               rule("Test",      "test",      color: .red),
                               rule("Resources", "resources", color: .orange),
                           ]))

        // 17 — Kotlin (Gradle Kotlin DSL). Overrides Java for *.kts builds.
        addRuleSet(iconSet(name: "Kotlin Project",
                           desc: "Detected via build.gradle.kts or settings.gradle.kts.",
                           triggers: [exists("build.gradle.kts"), exists("settings.gradle.kts")],
                           type: .kotlin))

        // 18 — C# / .NET (a .sln or project file).
        addRuleSet(iconSet(name: "C# / .NET Project",
                           desc: "Detected via a .sln, .csproj, or .fsproj file.",
                           triggers: [childEnds(".sln"), childEnds(".csproj"), childEnds(".fsproj")],
                           type: .csharp))

        // 19 — Ruby (Gemfile).
        addRuleSet(iconSet(name: "Ruby Project",
                           desc: "Detected via Gemfile or Rakefile.",
                           triggers: [exists("Gemfile"), exists("Rakefile")],
                           type: .ruby,
                           subRules: [
                               rule("App",  "app",  color: .red),
                               rule("Lib",  "lib",  color: .purple),
                               rule("Spec", "spec", color: .orange),
                           ]))

        // 20 — PHP (composer.json).
        addRuleSet(iconSet(name: "PHP Project",
                           desc: "Detected via composer.json.",
                           triggers: [exists("composer.json")],
                           type: .php))

        // 21 — Elixir (mix.exs).
        addRuleSet(iconSet(name: "Elixir Project",
                           desc: "Detected via mix.exs.",
                           triggers: [exists("mix.exs")],
                           type: .elixir))

        // 22 — C / C++ (CMake or C++ sources).
        addRuleSet(iconSet(name: "C / C++ Project",
                           desc: "Detected via CMakeLists.txt or C++ source files.",
                           triggers: [exists("CMakeLists.txt"), childEnds(".cpp"),
                                      childEnds(".cc"), childEnds(".cxx")],
                           type: .cpp,
                           subRules: [
                               rule("Include", "include", color: .blue),
                               rule("Src",     "src",     color: .yellow),
                               rule("Build",   "build",   color: .gray),
                           ]))

        // 23 — iOS / Swift (Xcode project or SwiftPM package).
        addRuleSet(iconSet(name: "iOS / Swift Project",
                           desc: "Detected via an .xcodeproj, .xcworkspace, or Package.swift.",
                           triggers: [childEnds(".xcodeproj"), childEnds(".xcworkspace"), exists("Package.swift")],
                           type: .ios))

        // 24 — Android (Gradle wrapper alongside an app module).
        addRuleSet(iconSet(name: "Android Project",
                           desc: "Detected via a Gradle wrapper next to an app module.",
                           triggers: [exists("gradlew"), exists("app")],
                           type: .android,
                           logic: .and,
                           subRules: [
                               rule("App",  "app",  color: .green),
                               rule("Java", "java", color: .orange),
                               rule("Res",  "res",  color: .blue),
                           ]))

        // 25 — Flutter (pubspec.yaml).
        addRuleSet(iconSet(name: "Flutter Project",
                           desc: "Detected via pubspec.yaml.",
                           triggers: [exists("pubspec.yaml")],
                           type: .flutter,
                           subRules: [
                               rule("Lib",     "lib",     color: .blue),
                               rule("Test",    "test",    color: .red),
                               rule("Assets",  "assets",  color: .orange),
                               rule("Android", "android", color: .green),
                               rule("iOS",     "ios",     color: .gray),
                           ]))

        UserDefaults.standard.set(true, forKey: defaultRuleSetsKey)
    }

    /// Clears the suppress flag and populated-flags, then immediately re-runs both
    /// populate methods so defaults come back without requiring a relaunch.
    func repopulateDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsSuppressedKey)
        UserDefaults.standard.removeObject(forKey: defaultRulesKey)
        UserDefaults.standard.removeObject(forKey: defaultRuleSetsKey)
        populateDefaultRulesIfNeeded()
        populateDefaultRuleSetsIfNeeded()
        rebuildEvalOrderIfNeeded()
    }

    /// Wires the built-in Node icon onto the default "Node Project" rule set's root,
    /// once IconManager has loaded its built-in icons. Safe to call on every launch.
    func syncDefaultIconsForRuleSets(from iconManager: IconManager) {
        var changed = false

        // Default "Node Project" rule set: wire up the built-in Node icon on first launch.
        if let nodeIcon = iconManager.icon(for: .node) {
            for i in ruleSets.indices
            where ruleSets[i].name == RuleEngine.nodeRuleSetName
                && ruleSets[i].rootIconID == nil
                && !ruleSets[i].hasAnyIcon {
                ruleSets[i].rootIconID = nodeIcon.id
                ruleSets[i].isEnabled = true
                changed = true
            }
        }

        // Rule sets migrated from project templates carry a `projectType`. If their
        // root icon went missing (e.g. icon bundle changed), restore it from the type.
        for i in ruleSets.indices {
            guard let type = ruleSets[i].projectType,
                  ruleSets[i].isEnabled,
                  ruleSets[i].rootIconID == nil,
                  ruleSets[i].rootColor == nil,
                  let icon = iconManager.icon(for: type) else { continue }
            ruleSets[i].rootIconID = icon.id
            changed = true
        }

        if changed { saveRuleSets() }
    }

    // MARK: - Template → Rule Set migration (one-time)


    // MARK: - evalOrder management

    private func rebuildEvalOrderIfNeeded() {
        let existingIDs = Set(evalOrder.map(\.id))
        let allSetIDs      = ruleSets.map  { EvalItem(id: $0.id, kind: .ruleSet,  order: 0) }
        let allRuleIDs     = rules.map     { EvalItem(id: $0.id, kind: .rule,     order: 0) }
        let allItems       = allSetIDs + allRuleIDs

        evalOrder.removeAll { item in
            !allItems.contains(where: { $0.id == item.id })
        }

        var nextOrder = (evalOrder.map(\.order).max() ?? -1) + 1
        for item in allItems where !existingIDs.contains(item.id) {
            evalOrder.append(EvalItem(id: item.id, kind: item.kind, order: nextOrder))
            nextOrder += 1
        }
        saveEvalOrder()
    }

    func moveEvalItems(from offsets: IndexSet, to destination: Int) {
        evalOrder.move(fromOffsets: offsets, toOffset: destination)
        for i in evalOrder.indices { evalOrder[i].order = i }
        saveEvalOrder()
    }

    // MARK: - Icon Usage Queries

    func usages(of iconID: UUID) -> [String] {
        var result: [String] = []
        for rule in rules where rule.iconID == iconID {
            result.append("Individual Rule: \"\(rule.name)\"")
        }
        for rs in ruleSets {
            if rs.rootIconID == iconID { result.append("Rule Set: \"\(rs.name)\" (root icon)") }
            for sub in rs.rules where sub.iconID == iconID {
                result.append("Rule Set: \"\(rs.name)\" → \"\(sub.description)\"")
            }
        }
        return result
    }

    func clearIconReferences(_ iconID: UUID) {
        for i in rules.indices where rules[i].iconID == iconID {
            rules[i].iconID = nil; rules[i].isEnabled = false
        }
        saveRules()
        for i in ruleSets.indices {
            if ruleSets[i].rootIconID == iconID { ruleSets[i].rootIconID = nil }
            for j in ruleSets[i].rules.indices where ruleSets[i].rules[j].iconID == iconID {
                ruleSets[i].rules[j].iconID = nil
            }
            if !ruleSets[i].hasAnyIcon { ruleSets[i].isEnabled = false }
        }
        saveRuleSets()
    }

    // MARK: - Rules CRUD

    func addRule(_ rule: RuleModel) {
        rules.append(rule); saveRules()
        let next = (evalOrder.map(\.order).max() ?? -1) + 1
        evalOrder.append(EvalItem(id: rule.id, kind: .rule, order: next))
        saveEvalOrder()
    }
    func updateRule(_ rule: RuleModel) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) { rules[i] = rule; saveRules() }
    }
    func deleteRule(_ rule: RuleModel) {
        rules.removeAll { $0.id == rule.id }
        evalOrder.removeAll { $0.id == rule.id }
        saveRules(); saveEvalOrder()
    }

    // MARK: - Rule Sets CRUD

    func addRuleSet(_ set: RuleSetModel) {
        ruleSets.append(set); saveRuleSets()
        let next = (evalOrder.map(\.order).max() ?? -1) + 1
        evalOrder.append(EvalItem(id: set.id, kind: .ruleSet, order: next))
        saveEvalOrder()
    }
    func updateRuleSet(_ set: RuleSetModel) {
        if let i = ruleSets.firstIndex(where: { $0.id == set.id }) { ruleSets[i] = set; saveRuleSets() }
    }
    func deleteRuleSet(_ set: RuleSetModel) {
        ruleSets.removeAll { $0.id == set.id }
        evalOrder.removeAll { $0.id == set.id }
        saveRuleSets(); saveEvalOrder()
    }

    // MARK: - Persistence

    private func load() {
        if let d = UserDefaults.standard.data(forKey: rulesKey),
           let v = try? JSONDecoder().decode([RuleModel].self, from: d) { rules = v }
        if let d = UserDefaults.standard.data(forKey: setsKey),
           let v = try? JSONDecoder().decode([RuleSetModel].self, from: d) { ruleSets = v }
        if let d = UserDefaults.standard.data(forKey: evalOrderKey),
           let v = try? JSONDecoder().decode([EvalItem].self, from: d) { evalOrder = v }
    }

    private func saveRules()     { encode(rules,     key: rulesKey) }
    private func saveRuleSets()  { encode(ruleSets,  key: setsKey) }
    private func saveEvalOrder() { encode(evalOrder,  key: evalOrderKey) }
    func saveEvalOrderPublic()   { saveEvalOrder() }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let d = try? JSONEncoder().encode(value) { UserDefaults.standard.set(d, forKey: key) }
    }
}

