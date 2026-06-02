import Foundation
import AppKit

struct IconModel: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var associatedType: ProjectType?
    var imageData: Data
    var createdAt: Date
    var tags: [String]
    var categoryID: UUID?
    var isBuiltIn: Bool = false
    /// Built-in icons can be hidden by the user without being truly deleted.
    /// Custom icons are hard-deleted; this flag is only meaningful for isBuiltIn == true.
    var isHidden: Bool = false

    init(name: String, associatedType: ProjectType? = nil, imageData: Data, tags: [String] = [], categoryID: UUID? = nil, isBuiltIn: Bool = false) {
        self.id = UUID()
        self.name = name
        self.associatedType = associatedType
        self.imageData = imageData
        self.createdAt = Date()
        self.tags = tags
        self.categoryID = categoryID
        self.isBuiltIn = isBuiltIn
    }

    var nsImage: NSImage? {
        NSImage(data: imageData)
    }
}
