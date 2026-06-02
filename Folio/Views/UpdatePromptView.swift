import SwiftUI

/// Startup "an update is available" modal. Offers three choices:
///   • Download & Install — fetches the release asset and opens it.
///   • Remind Me Later    — dismiss; the prompt reappears on the next launch.
///   • Skip This Version  — remember this version and never prompt for it again.
struct UpdatePromptView: View {
    let release: AvailableRelease
    @ObservedObject var updater: UpdateChecker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            VStack(spacing: 6) {
                Text("Update Available")
                    .font(.title2).fontWeight(.semibold)
                Text("Folio \(release.version) is available — you have \(UpdateChecker.currentVersion).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                NSWorkspace.shared.open(release.htmlURL)
            } label: {
                Text("View release notes")
                    .font(.caption)
            }
            .buttonStyle(.link)

            VStack(spacing: 10) {
                Button {
                    Task {
                        await updater.downloadAndInstall(release)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if updater.isDownloading {
                            ProgressView().controlSize(.small)
                            Text("Downloading…")
                        } else {
                            Text("Download & Install")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(updater.isDownloading)

                Button {
                    dismiss()
                } label: {
                    Text("Remind Me Later").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(updater.isDownloading)

                Button {
                    UpdateChecker.skip(version: release.version)
                    dismiss()
                } label: {
                    Text("Skip This Version").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(updater.isDownloading)
            }
        }
        .padding(28)
        .frame(width: 380)
        .FolioBackground()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}
