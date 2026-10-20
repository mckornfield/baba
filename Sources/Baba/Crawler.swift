import Foundation

/// Downloads templates from imgflip's listing, most popular first. This is the
/// in-app twin of scripts/crawl.py and writes the same files: it is resumable,
/// skipping anything already on disk.
@MainActor
final class Crawler: ObservableObject {
    static let shared = Crawler()

    @Published private(set) var running = false
    @Published private(set) var done = 0
    @Published private(set) var target = 0
    @Published private(set) var failure: String?

    private var task: Task<Void, Never>?
    private init() {}

    func start(count: Int = 1000) {
        guard !running else { return }
        running = true
        done = 0
        target = count
        failure = nil
        task = Task {
            do {
                try await run(count: count)
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
            }
            running = false
            Library.shared.reload()
        }
    }

    func stop() { task?.cancel() }

    // MARK: - Work

    private func run(count: Int) async throws {
        let root = Library.root
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("templates"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("thumbs"), withIntermediateDirectories: true)

        var entries: [Template] = []
        var seen = Library.excludedIDs()
        var page = 1
        while entries.count < count {
            try Task.checkCancellation()
            guard let body = try await Net.fetch("https://imgflip.com/memetemplates?page=\(page)"),
                  let html = String(data: body, encoding: .utf8)
            else { throw CrawlError.listing(page) }
            let found = Self.parse(html).filter { seen.insert($0.id).inserted }
            if found.isEmpty { break }

            // A page's images download a few at a time; the pages themselves
            // are walked one by one, which keeps the load on imgflip modest.
            let fresh = Array(found.prefix(count - entries.count))
            var batch: [Int: Template] = [:]
            try await withThrowingTaskGroup(of: (Int, Template?).self) { group in
                var next = 0
                func add() {
                    guard next < fresh.count else { return }
                    let (i, item) = (next, fresh[next])
                    next += 1
                    group.addTask { (i, try await Self.download(item, into: root)) }
                }
                for _ in 0..<min(6, fresh.count) { add() }
                while let (i, template) = try await group.next() {
                    batch[i] = template
                    add()
                }
            }
            entries += fresh.indices.compactMap { batch[$0] }
            done = entries.count
            try Self.writeIndex(entries, to: root)
            Library.shared.reload()
            page += 1
            try await Task.sleep(for: .milliseconds(250))
        }
        if entries.isEmpty { throw CrawlError.nothing }
    }

    private static let box = try! NSRegularExpression(
        pattern: #"<h3 class="mt-title">\s*<a [^>]*href="/meme/([^"]+)">([^<]+)</a>.*?src="//i\.imgflip\.com/4/([A-Za-z0-9]+)\.(jpg|png|gif|jpeg)""#,
        options: [.dotMatchesLineSeparators]
    )

    /// Listing entries; `file` is a placeholder until the original's extension is found.
    private static func parse(_ html: String) -> [Template] {
        let ns = html as NSString
        return box.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { m in
            let slug = ns.substring(with: m.range(at: 1))
            // Newer templates are /meme/<number>/<Name>.
            return Template(
                id: ns.substring(with: m.range(at: 3)),
                name: unescape(ns.substring(with: m.range(at: 2))).trimmingCharacters(in: .whitespaces),
                slug: String(slug.split(separator: "/").last ?? Substring(slug)),
                file: "", thumb: "\(ns.substring(with: m.range(at: 3))).\(ns.substring(with: m.range(at: 4)))"
            )
        }
    }

    /// Fetches the thumbnail and original. Nil if imgflip has no original to give.
    private static func download(_ t: Template, into root: URL) async throws -> Template? {
        let thumbs = root.appendingPathComponent("thumbs"), full = root.appendingPathComponent("templates")
        guard try await fetchIfMissing("https://i.imgflip.com/4/\(t.thumb)", to: thumbs.appendingPathComponent(t.thumb))
        else { return nil }
        // The original's extension is not always the thumbnail's.
        for ext in ["jpg", "png", "gif", "jpeg"] {
            let name = "\(t.id).\(ext)"
            if try await fetchIfMissing("https://i.imgflip.com/\(name)", to: full.appendingPathComponent(name)) {
                var done = t
                done.file = name
                return done
            }
        }
        return nil
    }

    private static func fetchIfMissing(_ url: String, to path: URL) async throws -> Bool {
        if let size = (try? path.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 { return true }
        guard let data = try await Net.fetch(url), !data.isEmpty else { return false }
        try data.write(to: path)
        return true
    }

    private static func writeIndex(_ entries: [Template], to root: URL) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: root.appendingPathComponent("index.json"), options: .atomic)
    }

    private static func unescape(_ s: String) -> String {
        var out = s
        for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out
    }
}

enum CrawlError: LocalizedError {
    case listing(Int), nothing
    var errorDescription: String? {
        switch self {
        case .listing(let page): "Couldn’t load imgflip’s template list (page \(page)). Check your connection."
        case .nothing: "imgflip returned no templates."
        }
    }
}

enum Net {
    /// The body, or nil on a 404. Other failures are retried, then thrown.
    static func fetch(_ url: String) async throws -> Data? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (Baba local meme library)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<4 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                if status == 404 { return nil }
                if status < 400 { return data }
                if attempt == 3 { throw URLError(.badServerResponse) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt == 3 { throw error }
            }
            try await Task.sleep(for: .seconds(2 * Double(attempt + 1)))
        }
        return nil
    }
}
