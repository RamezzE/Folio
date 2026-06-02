import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var historyManager: HistoryManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)
            // App header
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Folio")
                        .font(.system(size: 14, weight: .bold))
                    Text("Folder Icon Manager")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 30)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.2)

            // Nav items
            VStack(spacing: 3) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    SidebarNavRow(
                        item: item,
                        isSelected: appState.selectedTab == item,
                        badge: item == .history ? historyManager.entries.count : 0
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appState.selectedTab = item
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)

            Spacer()

            Divider().opacity(0.2)

            // Settings at bottom
            Button {
                appState.showSettings = true
            } label: {
                SidebarSettingsLabel()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 185, idealWidth: 205)
        // Own a fixed top inset (the header's .padding(.top, 30) clears the
        // window traffic lights). Ignoring the container's top safe area keeps
        // that inset constant so the header doesn't jump when the sidebar is
        // collapsed and reopened.
        .ignoresSafeArea(.container, edges: .top)
        .sidebarBackground()
    }
}

struct SidebarSettingsLabel: View {
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 15))
                .foregroundStyle(isHovered ? Theme.accent : Color.secondary)
                .frame(width: 24, alignment: .center)
            Text("Settings")
                .font(.system(size: 13.5, weight: isHovered ? .semibold : .regular))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Theme.glassHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

struct SidebarNavRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let badge: Int
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Left accent pill — slides in when selected
                Capsule()
                    .fill(isSelected ? Theme.accent : Color.clear)
                    .frame(width: 3, height: 18)
                    .padding(.trailing, 9)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)

                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                    .frame(width: 22, alignment: .center)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                Text(item.rawValue)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                    .padding(.leading, 9)

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            isSelected
                                ? Theme.accent.opacity(0.18)
                                : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                }
            }
            .padding(.vertical, 9)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? Theme.accent.opacity(0.12)
                            : isHovered ? Theme.glassHover : Color.clear
                    )
                    .animation(.easeInOut(duration: 0.12), value: isSelected)
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
