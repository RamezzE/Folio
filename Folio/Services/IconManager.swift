import Foundation
import AppKit
import Combine
internal import UniformTypeIdentifiers

struct ApplyResult {
    let success: Bool
    let originalIconData: Data?
}

class IconManager: ObservableObject {
    @Published var icons: [IconModel] = []
    @Published var categories: [IconCategory] = []
    @Published var errors: [ApplyError] = []
    @Published var lastError: String?

    private let storageKey = "saved_icons"
    private let categoriesKey = "saved_icon_categories"

    /// Cache for tinted folder preview images — keyed by NSColor so each
    /// color's CI pipeline runs at most once per app session.
    private var tintedFolderCache: [NSColor: NSImage] = [:]

    init() {
        load()
        loadCategories()
        syncBuiltInCategories()
        syncBuiltInIcons()
    }

    func addIcon(name: String, type: ProjectType?, from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let icon = IconModel(name: name, associatedType: type, imageData: data)
        icons.append(icon)
        save()
    }

    func addIcon(name: String, type: ProjectType?, data: Data) {
        let icon = IconModel(name: name, associatedType: type, imageData: data)
        icons.append(icon)
        save()
    }

    func delete(_ icon: IconModel) {
        if icon.isBuiltIn {
            hideIcon(icon)
        } else {
            icons.removeAll { $0.id == icon.id }
            save()
        }
    }

    func hideIcon(_ icon: IconModel) {
        guard let idx = icons.firstIndex(where: { $0.id == icon.id }) else { return }
        icons[idx].isHidden = true
        save()
    }

    func unhideIcon(_ icon: IconModel) {
        guard let idx = icons.firstIndex(where: { $0.id == icon.id }) else { return }
        icons[idx].isHidden = false
        save()
    }

    /// Bulk delete/hide. Built-ins are hidden; custom icons are hard-deleted.
    func deleteIcons(_ ids: Set<UUID>) {
        for id in ids {
            guard let icon = icons.first(where: { $0.id == id }) else { continue }
            if icon.isBuiltIn {
                if let idx = icons.firstIndex(where: { $0.id == id }) { icons[idx].isHidden = true }
            } else {
                icons.removeAll { $0.id == id }
            }
        }
        save()
    }

    func replace(_ icon: IconModel, with url: URL) {
        guard let data = try? Data(contentsOf: url),
              let idx = icons.firstIndex(of: icon) else { return }
        icons[idx] = IconModel(name: icon.name, associatedType: icon.associatedType, imageData: data)
        save()
    }

    func updateIcon(_ icon: IconModel) {
        if let idx = icons.firstIndex(where: { $0.id == icon.id }) {
            icons[idx] = icon
            save()
        }
    }

    func icon(for id: UUID?) -> IconModel? {
        guard let id else { return nil }
        return icons.first { $0.id == id }
    }

    func icon(for type: ProjectType) -> IconModel? {
        icons.first { $0.associatedType == type }
    }

    // MARK: - Categories

    func addCategory(_ category: IconCategory) {
        categories.append(category)
        saveCategories()
    }

    func updateCategory(_ category: IconCategory) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx] = category
            saveCategories()
        }
    }

    func deleteCategory(_ category: IconCategory) {
        guard !category.isBuiltIn else { return }
        for i in icons.indices where icons[i].categoryID == category.id {
            icons[i].categoryID = nil
        }
        categories.removeAll { $0.id == category.id }
        saveCategories()
        save()
    }

    func iconsInCategory(_ categoryID: UUID?) -> [IconModel] {
        if let categoryID {
            return icons.filter { $0.categoryID == categoryID }
        }
        return icons.filter { $0.categoryID == nil }
    }

    // MARK: - Apply Icons

    @discardableResult
    func applyIcon(_ icon: IconModel, to url: URL) -> ApplyResult {
        guard let image = icon.nsImage else {
            recordError(operation: "apply icon", path: url.path, message: "Invalid image data for icon \"\(icon.name)\".")
            return ApplyResult(success: false, originalIconData: nil)
        }
        let originalData = captureOriginalIfCustom(at: url)
        let sized = resizedTo512(image)
        let ok = NSWorkspace.shared.setIcon(sized, forFile: url.path, options: [])
        if !ok {
            recordError(operation: "apply icon", path: url.path, message: "Could not set icon. Check folder permissions.")
        }
        return ApplyResult(success: ok, originalIconData: originalData)
    }

    /// Apply icon first, then tint with color overlay. The icon remains visible under the color.
    @discardableResult
    func applyIconAndColor(_ icon: IconModel, color: NSColor, to url: URL) -> ApplyResult {
        guard let image = icon.nsImage else {
            recordError(operation: "apply icon+color", path: url.path, message: "Invalid image data for icon \"\(icon.name)\".")
            return ApplyResult(success: false, originalIconData: nil)
        }
        let originalData = captureOriginalIfCustom(at: url)
        let sized = resizedTo512(image)
        let tinted = tintImage(sized, with: color)
        let ok = NSWorkspace.shared.setIcon(tinted, forFile: url.path, options: [])
        if !ok {
            recordError(operation: "apply icon+color", path: url.path, message: "Could not set icon. Check folder permissions.")
        }
        return ApplyResult(success: ok, originalIconData: originalData)
    }

    func removeIcon(from url: URL) {
        NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
    }

    // MARK: - Async wrappers
    // The synchronous methods above resize/tint images and call NSWorkspace.setIcon,
    // which is blocking I/O. Running them on the main thread freezes the UI (and the
    // progress bar) when applying to many folders. These wrappers hop to a background
    // queue so callers can `await` per-folder work while the main thread stays free.

    func applyIconAsync(_ icon: IconModel, to url: URL) async -> ApplyResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: self.applyIcon(icon, to: url))
            }
        }
    }

    func applyIconAndColorAsync(_ icon: IconModel, color: NSColor, to url: URL) async -> ApplyResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: self.applyIconAndColor(icon, color: color, to: url))
            }
        }
    }

    func applyColorAsync(_ color: NSColor, to url: URL) async -> ApplyResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: self.applyColor(color, to: url))
            }
        }
    }

    func removeIconAsync(from url: URL) async {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                self.removeIcon(from: url)
                cont.resume()
            }
        }
    }

    // MARK: - Apply Colors

    func applyColor(_ color: NSColor, to url: URL) -> ApplyResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            recordError(operation: "apply color", path: url.path, message: "Folder does not exist.")
            return ApplyResult(success: false, originalIconData: nil)
        }
        let originalData = captureOriginalIfCustom(at: url)
        let folderIcon = defaultFolderIcon()
        let tinted = tintImage(folderIcon, with: color)
        let ok = NSWorkspace.shared.setIcon(tinted, forFile: url.path, options: [])
        if !ok {
            recordError(operation: "apply color", path: url.path, message: "Permission denied.")
        }
        return ApplyResult(success: ok, originalIconData: originalData)
    }

    /// Get a clean default macOS folder icon for tinting
    private func defaultFolderIcon() -> NSImage {
        let icon = NSWorkspace.shared.icon(for: .folder)
        return resizedTo512(icon)
    }

    /// Tint by desaturating then multiplying with target color.
    /// Produces accurate, vivid colors while preserving shape/shading.
    private func tintImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        guard let tiff = image.tiffRepresentation,
              let ciInput = CIImage(data: tiff) else {
            return image
        }

        let targetRGB = color.usingColorSpace(.sRGB) ?? color
        let r = targetRGB.redComponent
        let g = targetRGB.greenComponent
        let b = targetRGB.blueComponent

        // Desaturate to grayscale preserving luminance
        let desat = ciInput.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputBrightnessKey: 0.05,
            kCIInputContrastKey: 1.1
        ])

        // Multiply grayscale by target color
        let colorMatrix = desat.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        // Composite tinted version over original using sourceAtop to keep alpha/shape
        let composited = colorMatrix.applyingFilter("CISourceAtopCompositing", parameters: [
            kCIInputBackgroundImageKey: ciInput
        ])

        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(composited, from: ciInput.extent) else {
            return image
        }

        let result = NSImage(cgImage: cgImage, size: size)
        return result
    }

    /// Generate a preview of the default folder icon tinted with a color.
    /// Results are cached by color so the CI pipeline only runs once per color.
    func previewTintedFolder(color: NSColor) -> NSImage {
        if let cached = tintedFolderCache[color] { return cached }
        let result = tintImage(defaultFolderIcon(), with: color)
        tintedFolderCache[color] = result
        return result
    }

    /// Tint an arbitrary image with the given color using the same CI pipeline.
    func previewTintedIcon(_ image: NSImage, color: NSColor) -> NSImage {
        tintImage(image, with: color)
    }

    // MARK: - Error Management

    func recordError(operation: String, path: String, message: String) {
        let error = ApplyError(operation: operation, folderPath: path, message: message)
        DispatchQueue.main.async { [weak self] in
            self?.errors.append(error)
            self?.lastError = error.description
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                if self?.lastError == error.description { self?.lastError = nil }
            }
        }
    }

    func clearErrors() {
        errors.removeAll()
        lastError = nil
    }

    func dismissError(_ error: ApplyError) {
        errors.removeAll { $0.id == error.id }
    }

    // MARK: - Private

    private func captureOriginalIfCustom(at url: URL) -> Data? {
        guard hasCustomIcon(at: url.path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              png.count <= 524_288 else { return nil }
        return png
    }

    private func hasCustomIcon(at path: String) -> Bool {
        let name = "com.apple.FinderInfo"
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size >= 9 else { return false }
        var buf = [UInt8](repeating: 0, count: size)
        getxattr(path, name, &buf, size, 0, 0)
        return (buf[8] & 0x04) != 0
    }

    private func resizedTo512(_ image: NSImage) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero, operation: .copy, fraction: 1.0)
        out.unlockFocus()
        return out
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(icons) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([IconModel].self, from: data) else { return }
        icons = decoded
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
    }

    private func loadCategories() {
        guard let data = UserDefaults.standard.data(forKey: categoriesKey),
              let decoded = try? JSONDecoder().decode([IconCategory].self, from: data) else { return }
        categories = decoded
    }

    func syncBuiltInIcons() {
        let imageExtensions = ["png", "jpg", "jpeg", "tiff", "icns"]
        let typeMap = Dictionary(
            uniqueKeysWithValues: ProjectType.allCases.filter { $0 != .unknown }.map { ($0.rawValue, $0) }
        )
        let builtInCatID = categories.first(where: { $0.name == "Built-In Icons" })?.id

        // Collect candidate files from DefaultIcons subfolder and bundle root
        var candidateFiles: [URL] = []
        if let dirURL = Bundle.main.resourceURL?.appendingPathComponent("DefaultIcons") {
            candidateFiles += (try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)) ?? []
        }
        if let rootURL = Bundle.main.resourceURL {
            candidateFiles += (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        }

        var foundTypes: Set<ProjectType> = []
        for file in candidateFiles {
            let ext = file.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            let stem = file.deletingPathExtension().lastPathComponent.lowercased()
            guard let type = typeMap[stem], !foundTypes.contains(type) else { continue }
            guard let data = try? Data(contentsOf: file) else { continue }
            foundTypes.insert(type)

            if let idx = icons.firstIndex(where: { $0.isBuiltIn && $0.associatedType == type }) {
                if icons[idx].imageData != data { icons[idx].imageData = data }
                if icons[idx].categoryID == nil { icons[idx].categoryID = builtInCatID }
            } else {
                let icon = IconModel(name: type.displayName, associatedType: type, imageData: data,
                                     categoryID: builtInCatID, isBuiltIn: true)
                icons.append(icon)
            }
        }

        // Remove built-in icons whose bundle image is gone
        icons.removeAll { icon in
            guard icon.isBuiltIn, let type = icon.associatedType else { return icon.isBuiltIn }
            return !foundTypes.contains(type)
        }
        save()
    }

    private func syncBuiltInCategories() {
        let existingNames = Set(categories.filter(\.isBuiltIn).map(\.name))
        for cat in IconCategory.builtInCategories where !existingNames.contains(cat.name) {
            categories.append(cat)
        }
        saveCategories()
    }

    /// Clears all user-added icons and categories, then immediately re-syncs
    /// built-in icons from the bundle. Call this from "Restore Defaults".
    func restoreBuiltIns() {
        icons.removeAll { !$0.isBuiltIn }
        categories.removeAll { !$0.isBuiltIn }
        syncBuiltInCategories()
        syncBuiltInIcons()
    }
}
