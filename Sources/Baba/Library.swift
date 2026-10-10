import AppKit

struct Template: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var slug: String
    var file: String
    var thumb: String
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

    private init() { reload() }

    func reload() {
        let data = try? Data(contentsOf: Self.root.appendingPathComponent("index.json"))
        templates = data.flatMap { try? JSONDecoder().decode([Template].self, from: $0) } ?? []
    }

    func fullURL(_ t: Template) -> URL { Self.root.appendingPathComponent("templates/\(t.file)") }
    func thumbURL(_ t: Template) -> URL { Self.root.appendingPathComponent("thumbs/\(t.thumb)") }

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
        let image = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
