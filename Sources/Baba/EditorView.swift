import SwiftUI

struct EditorView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var session: Session
    let template: Template

    @State private var base: NSImage?
    @State private var boxes = TextBox.defaults()
    @State private var selected: UUID?
    @State private var copied = false
    @FocusState private var focus: UUID?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { session.template = nil } label: { Label("Memes", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(template.name).font(.headline).lineLimit(1)
                Spacer()
                Button { addBox() } label: { Label("Text", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }

            preview.frame(maxHeight: .infinity)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach($boxes) { $box in
                        HStack {
                            TextField("Caption", text: $box.text)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: box.id)
                                .onSubmit { copy() }
                            Button { remove(box.id) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .disabled(boxes.count <= 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 110)

            HStack {
                Label("Drag to chat", systemImage: "hand.draw")
                    .font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
                    .onDrag { dragProvider() }
                    .help("Drag the finished meme into any app")
                Spacer()
                Button(copied ? "Copied" : "Copy") { copy() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .onAppear {
            base = NSImage(contentsOf: library.fullURL(template))
            focus = boxes.first?.id
        }
        .onChange(of: focus) { _, id in if let id { selected = id } }
    }

    // MARK: - Preview

    @ViewBuilder private var preview: some View {
        if let base {
            let pixels = MemeRenderer.pixelSize(of: base)
            GeometryReader { geo in
                let scale = min(geo.size.width / pixels.width, geo.size.height / pixels.height)
                let canvas = CGSize(width: pixels.width * scale, height: pixels.height * scale)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: MemeRenderer.image(base: base, boxes: boxes, size: pixels))
                        .resizable()
                        .frame(width: canvas.width, height: canvas.height)
                    ForEach($boxes) { $box in
                        BoxOverlay(box: $box, canvas: canvas, isSelected: selected == box.id) {
                            selected = box.id
                            focus = box.id
                        }
                    }
                }
                .coordinateSpace(name: "canvas")
                .frame(width: canvas.width, height: canvas.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text("Couldn’t load this image").foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func addBox() {
        let box = TextBox.extra()
        boxes.append(box)
        focus = box.id
    }

    private func remove(_ id: UUID) {
        boxes.removeAll { $0.id == id }
        if selected == id { selected = nil }
    }

    /// Renders at the template's native resolution and writes it where a drop can read it.
    private func export() -> (data: Data, file: URL)? {
        guard let base, let data = MemeRenderer.png(base: base, boxes: boxes) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Baba", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(template.slug).png")
        do { try data.write(to: file) } catch { return nil }
        return (data, file)
    }

    private func copy() {
        guard let out = export() else { return }
        Clipboard.copy(png: out.data, file: out.file)
        library.markUsed(template)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func dragProvider() -> NSItemProvider {
        guard let out = export(), let provider = NSItemProvider(contentsOf: out.file) else {
            return NSItemProvider()
        }
        library.markUsed(template)
        provider.suggestedName = out.file.lastPathComponent
        return provider
    }
}

/// The dashed frame over a caption: drag it to move, drag the corner to resize.
struct BoxOverlay: View {
    @Binding var box: TextBox
    let canvas: CGSize
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var dragStart: CGRect?
    @State private var resizeStart: CGRect?

    private let minSide: CGFloat = 0.06

    var body: some View {
        let w = box.rect.width * canvas.width
        let h = box.rect.height * canvas.height
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .overlay(
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: [5, 3]))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.6))
                )
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            if dragStart == nil { dragStart = box.rect; onSelect() }
                            guard let start = dragStart else { return }
                            let x = start.minX + value.translation.width / canvas.width
                            let y = start.minY + value.translation.height / canvas.height
                            box.rect.origin = CGPoint(
                                x: min(max(x, 0), 1 - start.width),
                                y: min(max(y, 0), 1 - start.height)
                            )
                        }
                        .onEnded { _ in dragStart = nil }
                )
            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .frame(width: 12, height: 12)
                .padding(2)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            if resizeStart == nil { resizeStart = box.rect; onSelect() }
                            guard let start = resizeStart else { return }
                            let width = start.width + value.translation.width / canvas.width
                            let height = start.height + value.translation.height / canvas.height
                            box.rect.size = CGSize(
                                width: min(max(width, minSide), 1 - start.minX),
                                height: min(max(height, minSide), 1 - start.minY)
                            )
                        }
                        .onEnded { _ in resizeStart = nil }
                )
        }
        .frame(width: w, height: h)
        .position(x: box.rect.minX * canvas.width + w / 2, y: box.rect.minY * canvas.height + h / 2)
    }
}
