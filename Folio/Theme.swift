import SwiftUI

enum Theme {
    // MARK: - Accent (ocean blue)
    static let accent     = Color(red: 0.16, green: 0.60, blue: 0.96)
    static let accentSoft = Color(red: 0.34, green: 0.72, blue: 1.00)

    // MARK: - Glass surfaces (ocean-tinted so they don't read as flat gray)
    static let glassTint   = Color(red: 0.16, green: 0.27, blue: 0.46, opacity: 0.34)
    static let glassStroke = Color(white: 1, opacity: 0.10)
    static let glassFill   = Color(red: 0.16, green: 0.27, blue: 0.46, opacity: 0.22)
    static let glassHover  = Color(red: 0.30, green: 0.50, blue: 0.80, opacity: 0.20)
    static let cardFill    = Color(red: 0.16, green: 0.27, blue: 0.46, opacity: 0.30)

    // MARK: - Search / input fields
    static let fieldFill   = Color(red: 0.10, green: 0.18, blue: 0.32, opacity: 0.55)

    // MARK: - Window background (deep ocean charcoal)
    static let bgTop    = Color(red: 0.072, green: 0.090, blue: 0.130)
    static let bgBottom = Color(red: 0.038, green: 0.048, blue: 0.072)

    // MARK: - Sidebar background (a touch lighter / bluer than detail)
    static let sidebarTop    = Color(red: 0.090, green: 0.120, blue: 0.180)
    static let sidebarBottom = Color(red: 0.055, green: 0.075, blue: 0.115)

    // MARK: - Layout tokens
    static let radius:   CGFloat = 12
    static let radiusSm: CGFloat = 8
}

extension View {
    /// Subtle liquid-glass card: frosted material + ocean tint + hairline stroke.
    func glassCard(cornerRadius: CGFloat = Theme.radius) -> some View {
        self
            .background(Theme.glassTint, in: RoundedRectangle(cornerRadius: cornerRadius))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.glassStroke, lineWidth: 0.6)
            )
    }

    /// App-wide ocean gradient with a soft accent glow in the corner.
    func FolioBackground() -> some View {
        self.background {
            ZStack {
                LinearGradient(colors: [Theme.bgTop, Theme.bgBottom],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.accent.opacity(0.12), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 620)
            }
            .ignoresSafeArea()
        }
    }

    /// Sidebar ocean gradient (slightly lighter than the detail pane).
    func sidebarBackground() -> some View {
        self.background {
            ZStack {
                LinearGradient(colors: [Theme.sidebarTop, Theme.sidebarBottom],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.accent.opacity(0.14), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 340)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Page header

/// Consistent title + subtitle header used across all top-level views.
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Reusable themed search field

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var cornerRadius: CGFloat = 9

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accentSoft.opacity(0.9))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.glassStroke, lineWidth: 0.6)
        )
    }
}
