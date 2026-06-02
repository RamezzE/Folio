import Foundation

struct IconCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isBuiltIn: Bool

    init(name: String, isBuiltIn: Bool = false) {
        self.id = UUID()
        self.name = name
        self.isBuiltIn = isBuiltIn
    }

    static var builtInCategories: [IconCategory] {
        [
            IconCategory(name: "Built-In Icons", isBuiltIn: true),
            IconCategory(name: "Frontend", isBuiltIn: true),
            IconCategory(name: "Backend", isBuiltIn: true),
            IconCategory(name: "Database", isBuiltIn: true),
            IconCategory(name: "Cloud", isBuiltIn: true),
            IconCategory(name: "Testing", isBuiltIn: true),
            IconCategory(name: "Languages", isBuiltIn: true),
            IconCategory(name: "Frameworks", isBuiltIn: true),
            IconCategory(name: "Custom", isBuiltIn: true),
        ]
    }
}
