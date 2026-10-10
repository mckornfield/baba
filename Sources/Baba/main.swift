import AppKit

// `Baba --render OUT.png [TEMPLATE-ID] [TOP TEXT] [BOTTOM TEXT]` renders one meme
// headlessly; it exercises the same code the editor's Copy button uses.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render"), args.count > i + 1 {
    let ok: Bool = MainActor.assumeIsolated {
        let library = Library.shared
        let wanted = args.count > i + 2 ? args[i + 2] : nil
        guard let template = library.templates.first(where: { $0.id == wanted }) ?? library.templates.first,
              let base = NSImage(contentsOf: library.fullURL(template))
        else {
            FileHandle.standardError.write(Data("no templates found in \(Library.root.path)\n".utf8))
            return false
        }
        var boxes = TextBox.defaults()
        if args.count > i + 3 { boxes[0].text = args[i + 3] }
        if args.count > i + 4 { boxes[1].text = args[i + 4] }
        guard let png = MemeRenderer.png(base: base, boxes: boxes) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: args[i + 1]))) != nil
    }
    exit(ok ? 0 : 1)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = AppController.shared
    application.run()
}
