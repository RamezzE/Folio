import Foundation
import AppKit

enum FolderColor: String, Codable, CaseIterable, Identifiable {
    case blue, green, red, orange, purple, yellow, teal, pink, brown, gray

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var nsColor: NSColor {
        switch self {
        case .blue:   return .systemBlue
        case .green:  return .systemGreen
        case .red:    return .systemRed
        case .orange: return .systemOrange
        case .purple: return .systemPurple
        case .yellow: return .systemYellow
        case .teal:   return .systemTeal
        case .pink:   return .systemPink
        case .brown:  return .systemBrown
        case .gray:   return .systemGray
        }
    }
}

/// Wraps either a preset FolderColor or a custom hex color
struct FolderColorChoice: Codable, Equatable {
    var preset: FolderColor?
    var customHex: String?

    var isSet: Bool { preset != nil || customHex != nil }

    var nsColor: NSColor {
        if let preset { return preset.nsColor }
        if let customHex { return NSColor(hex: customHex) ?? .systemBlue }
        return .systemBlue
    }

    var displayName: String {
        if let preset { return preset.displayName }
        if let customHex { return customHex.uppercased() }
        return "None"
    }

    static func from(preset: FolderColor) -> FolderColorChoice {
        FolderColorChoice(preset: preset, customHex: nil)
    }

    static func from(hex: String) -> FolderColorChoice {
        FolderColorChoice(preset: nil, customHex: hex)
    }
}

struct FolderAppearance: Codable, Equatable {
    var iconID: UUID?
    var color: FolderColor?

    var hasAppearance: Bool { iconID != nil || color != nil }
}

// MARK: - NSColor hex support

extension NSColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let val = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >> 8) & 0xFF) / 255.0,
            blue: CGFloat(val & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
