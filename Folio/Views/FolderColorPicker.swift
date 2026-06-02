import SwiftUI

struct FolderColorPicker: View {
    @Binding var selectedColor: FolderColor?
    @EnvironmentObject var iconManager: IconManager
    @State private var previewImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Folder color:").foregroundStyle(.secondary)

                Picker("Color", selection: $selectedColor) {
                    Text("None").tag(Optional<FolderColor>.none)
                    ForEach(FolderColor.allCases) { color in
                        HStack {
                            Circle().fill(Color(nsColor: color.nsColor)).frame(width: 10, height: 10)
                            Text(color.displayName)
                        }.tag(Optional(color))
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 140)

                if selectedColor != nil {
                    Button { selectedColor = nil } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                // Swatches
                HStack(spacing: 4) {
                    ForEach(FolderColor.allCases) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: color.nsColor))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(color.displayName)
                    }
                }

                // Live preview — rendered asynchronously so it never stalls the main thread.
                if selectedColor != nil {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 36, height: 36)

                        if let img = previewImage {
                            Image(nsImage: img)
                                .resizable().scaledToFit()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeIn(duration: 0.15), value: previewImage != nil)
                }
            }
        }
        .task(id: selectedColor) {
            guard let color = selectedColor else { previewImage = nil; return }
            let nsColor = color.nsColor
            // Grab a copy of the cached/computed image on the main actor, then
            // do nothing else async so we never call a @MainActor method from a
            // detached context (which is a Swift 6 error).
            let img = iconManager.previewTintedFolder(color: nsColor)
            if selectedColor?.nsColor == nsColor { previewImage = img }
        }
    }
}
