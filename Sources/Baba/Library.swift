import AppKit
import ImageIO

struct Template: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var slug: String
    var file: String
    var thumb: String
    /// True for images dropped into the `custom` folder rather than crawled.
    var custom = false

    private enum CodingKeys: String, CodingKey { case id, name, slug, file, thumb }
}

/// The downloaded templates, as written by scripts/crawl.py.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    /// `BABA_LIBRARY` points at another folder, handy while developing.
    static let root: URL = {
        if let path = ProcessInfo.processInfo.environment["BABA_LIBRARY"] {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Baba")
    }()

    @Published private(set) var templates: [Template] = []
    @Published private(set) var recents: [String] = UserDefaults.standard.stringArray(forKey: "recents") ?? []

    /// Drop any image in here and it becomes a template; the filename is its name.
    static var customFolder: URL { root.appendingPathComponent("custom") }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]

    private init() { reload() }

    func reload() {
        let data = try? Data(contentsOf: Self.root.appendingPathComponent("index.json"))
        let crawled = data.flatMap { try? JSONDecoder().decode([Template].self, from: $0) } ?? []
        templates = Self.scanCustom() + crawled
    }

    private static func scanCustom() -> [Template] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: customFolder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        func modified(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { modified($0) > modified($1) }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
                return Template(id: "custom/\(url.lastPathComponent)", name: name, slug: name,
                                file: url.lastPathComponent, thumb: url.lastPathComponent, custom: true)
            }
    }

    func fullURL(_ t: Template) -> URL {
        t.custom ? Self.customFolder.appendingPathComponent(t.file)
                 : Self.root.appendingPathComponent("templates/\(t.file)")
    }
    func thumbURL(_ t: Template) -> URL {
        t.custom ? fullURL(t) : Self.root.appendingPathComponent("thumbs/\(t.thumb)")
    }

    func markUsed(_ t: Template) {
        recents = ([t.id] + recents.filter { $0 != t.id }).prefix(12).map { $0 }
        UserDefaults.standard.set(recents, forKey: "recents")
    }

    /// Every word typed must appear in the name. With no query, recents lead.
    func search(_ query: String) -> [Template] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else {
            let byID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
            let recent = recents.compactMap { byID[$0] }
            return recent + templates.filter { !recents.contains($0.id) }
        }
        return templates.filter { t in
            let name = t.name.lowercased()
            return words.allSatisfy { name.contains($0) }
        }
    }
}

/// Thumbnails are small, so they are decoded off the main thread and kept in memory.
enum Thumbs {
    private static let cache = NSCache<NSString, NSImage>()

    static func load(_ url: URL) async -> NSImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { downscaled(url) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// Custom images can be huge, so decode at thumbnail size rather than in full.
    private static func downscaled(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 400,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
