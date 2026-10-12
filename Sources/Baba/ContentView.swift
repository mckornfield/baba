import SwiftUI

/// Which screen the popover is on, and the memes in progress. Captions are kept
/// per template and written to disk, so clicking away (or quitting) loses nothing.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()

    /// The meme being edited. Opening the panel returns to it; Back (or Esc)
    /// leaves it, and the next open starts at the picker.
    @Published var template: Template? {
        didSet { if template?.id != oldValue?.id { persist() } }
    }
    /// Bumped on every open so the search field can grab focus again.
    @Published var openCount = 0

    private struct Saved: Codable {
        var current: String?
        var drafts: [String: [TextBox]]
    }

    private var drafts: [String: [TextBox]] = [:]
    private var pending: Task<Void, Never>?
    private static var file: URL { Library.root.appendingPathComponent("drafts.json") }

    private init() {
        guard let data = try? Data(contentsOf: Self.file),
              let saved = try? JSONDecoder().decode(Saved.self, from: data)
        else { return }
        drafts = saved.drafts
        template = saved.current.flatMap { id in Library.shared.templates.first { $0.id == id } }
    }

    /// Called as the panel opens. Stay on the meme in progress; the search box
    /// only needs resetting when showing the picker.
    func opened() { openCount += 1 }

    func draft(for template: Template) -> [TextBox]? { drafts[template.id] }

    func save(_ boxes: [TextBox], for template: Template) {
        guard drafts[template.id] != boxes else { return }
        drafts[template.id] = boxes
        // Dragging changes this many times a second; the disk can wait.
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { persist() }
        }
    }

    func discardDraft(for template: Template) {
        drafts[template.id] = nil
        persist()
    }

    func persist() {
        let saved = Saved(current: template?.id, drafts: drafts)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: Library.root, withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: .atomic)
    }
}

struct ContentView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        Group {
            if let template = session.template {
                EditorView(template: template).id(template.id)
            } else {
                PickerView()
            }
        }
        .frame(width: 440, height: 620)
    }
}

struct PickerView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var session: Session
    @ObservedObject private var crawler = Crawler.shared
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]

    var body: some View {
        let results = library.search(query)
        VStack(spacing: 0) {
            TextField("Search \(library.templates.count) memes", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { if let first = results.first { session.template = first } }
                .padding(12)

            if library.templates.isEmpty {
                EmptyLibrary()
            } else if results.isEmpty {
                Spacer()
                Text("No memes match “\(query)”").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(results) { t in
                            TemplateCell(template: t).onTapGesture { session.template = t }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if crawler.running && !library.templates.isEmpty { CrawlStatus().padding(10).background(.bar) }
        }
        .onAppear { searchFocused = true }
        .onChange(of: session.openCount) { _, _ in
            query = ""
            searchFocused = true
        }
    }
}

struct TemplateCell: View {
    @EnvironmentObject var library: Library
    let template: Template
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(height: 120)
            Text(template.name).font(.caption).lineLimit(1).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .task(id: template.id) { image = await Thumbs.load(library.thumbURL(template)) }
    }
}

struct EmptyLibrary: View {
    @ObservedObject private var crawler = Crawler.shared

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.stack").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No memes yet").font(.headline)
            if crawler.running {
                CrawlStatus().frame(maxWidth: 280)
            } else {
                Text("Baba keeps its own copy of the most popular\nimgflip templates, so it works offline.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Download 1000 memes") { crawler.start() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                if let failure = crawler.failure {
                    Text(failure).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct CrawlStatus: View {
    @ObservedObject private var crawler = Crawler.shared

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(crawler.done), total: Double(max(crawler.target, 1)))
            Text("\(crawler.done) / \(crawler.target)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button("Stop") { crawler.stop() }.buttonStyle(.borderless).font(.caption)
        }
    }
}
