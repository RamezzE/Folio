import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var iconManager: IconManager
    @EnvironmentObject var ruleEngine: RuleEngine
    @EnvironmentObject var appState: AppState
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Header
                PageHeader(title: "Dashboard", subtitle: "Welcome back — here's what's happening.")
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                // Stats row — equal-width cards
                HStack(spacing: 14) {
                    StatCard(
                        title: "Icons Saved",
                        value: "\(iconManager.icons.count)",
                        icon: "photo.on.rectangle.angled",
                        color: .blue,
                        delay: 0.05
                    ) { appState.selectedTab = .icons }
                    .frame(maxWidth: .infinity)

                    StatCard(
                        title: "Rules Active",
                        value: "\(ruleEngine.rules.filter(\.isEnabled).count + ruleEngine.ruleSets.filter(\.isEnabled).count)",
                        detail: "\(ruleEngine.rules.filter(\.isEnabled).count) rules · \(ruleEngine.ruleSets.filter(\.isEnabled).count) sets",
                        icon: "slider.horizontal.3",
                        color: .purple,
                        delay: 0.1
                    ) { appState.selectedTab = .rules }
                    .frame(maxWidth: .infinity)

                    StatCard(
                        title: "Changes Made",
                        value: "\(historyManager.entries.count)",
                        icon: "clock.arrow.circlepath",
                        color: .orange,
                        delay: 0.15
                    ) { appState.selectedTab = .history }
                    .frame(maxWidth: .infinity)
                }

                // Quick actions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Start")
                        .font(.headline)

                    HStack(spacing: 12) {
                        QuickActionCard(
                            title: "Apply",
                            subtitle: "Choose a folder and apply rules",
                            icon: "paintbrush.fill",
                            color: .blue
                        ) { appState.selectedTab = .projects }

                        QuickActionCard(
                            title: "Create Rule",
                            subtitle: "Auto-assign icons by folder name",
                            icon: "plus.rectangle.on.rectangle",
                            color: .purple
                        ) { appState.selectedTab = .rules }
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: appeared)

                // Drag & drop tip
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                    Text("Tip: Drag any PNG, JPEG, TIFF, or ICNS image anywhere in this window to instantly add it to your Icon Library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .glassCard(cornerRadius: 10)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)

                // Recent history
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent Activity")
                            .font(.headline)
                        Spacer()
                        if !historyManager.entries.isEmpty {
                            Button("View All") { appState.selectedTab = .history }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if historyManager.entries.isEmpty {
                        ContentUnavailableView(
                            "No activity yet",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Apply icons to folders to see a history of changes here.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(historyManager.entries.prefix(5).enumerated()), id: \.element.id) { idx, entry in
                                HistoryRow(entry: entry, iconManager: iconManager)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 6)
                                    .animation(.easeOut(duration: 0.3).delay(0.2 + Double(idx) * 0.05), value: appeared)
                            }
                        }
                    }
                }
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.18), value: appeared)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .onDisappear { appeared = false }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let iconManager: IconManager

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if entry.action == .revert {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.title2).foregroundStyle(.orange)
                } else if let id = entry.appliedIconID,
                          let icon = iconManager.icon(for: id),
                          let img = icon.nsImage {
                    Image(nsImage: img)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "folder.fill")
                        .font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.folderName).font(.subheadline).fontWeight(.medium)
                Text(entry.appliedIconName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.timeAgo).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    let icon: String
    let color: Color
    var delay: Double = 0
    let action: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var appeared = false
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(color.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Spacer()
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.7))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.45))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(Theme.glassTint, in: RoundedRectangle(cornerRadius: 14))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isHovered ? color.opacity(0.4) : Theme.glassStroke, lineWidth: isHovered ? 1.0 : 0.5)
            )
            .shadow(color: .black.opacity(isHovered ? 0.22 : 0.10), radius: isHovered ? 12 : 5, y: isHovered ? 6 : 3)
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.25), value: isHovered)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.easeOut(duration: 0.35).delay(delay), value: appeared)
        .onAppear {
            withAnimation { appeared = true }
        }
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.semibold)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Theme.glassTint, in: RoundedRectangle(cornerRadius: 12))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovered ? color.opacity(0.4) : Theme.glassStroke, lineWidth: isHovered ? 1.0 : 0.5)
            )
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.2), value: isHovered)
    }
}
