import Foundation

struct ApplyError: Identifiable {
    let id = UUID()
    let operation: String
    let folderPath: String
    let message: String
    let timestamp: Date

    init(operation: String, folderPath: String, message: String) {
        self.operation = operation
        self.folderPath = folderPath
        self.message = message
        self.timestamp = Date()
    }

    var description: String {
        "Failed to \(operation).\nFolder: \(folderPath)\nReason: \(message)"
    }
}
