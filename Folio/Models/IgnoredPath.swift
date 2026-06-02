import Foundation

enum IgnoreSource: String, Codable {
    case manual
    case gitignore
}

struct IgnoredPath: Identifiable, Codable, Equatable {
    let id: UUID
    var pattern: String
    var isRecursive: Bool
    var source: IgnoreSource

    init(pattern: String, isRecursive: Bool = false, source: IgnoreSource = .manual) {
        self.id = UUID()
        self.pattern = pattern
        self.isRecursive = isRecursive
        self.source = source
    }

    static func == (lhs: IgnoredPath, rhs: IgnoredPath) -> Bool {
        lhs.id == rhs.id
    }
}
