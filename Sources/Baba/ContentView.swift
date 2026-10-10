import SwiftUI

/// Which screen the popover is on. Opening the panel always returns to the picker.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()
    @Published var template: Template?
    /// Bumped on every open so the search field can grab focus again.
    @Published var openCount = 0

    func reset() {
        template = nil
        openCount += 1
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
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.stack").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No templates yet").font(.headline)
            Text("Download them from imgflip with:").foregroundStyle(.secondary)
            Text("scripts/crawl.py").font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Text("then reopen Baba.").foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
