import AppKit
import UniformTypeIdentifiers

enum Clipboard {
    /// Puts the meme on the pasteboard as PNG, plus a file URL for apps that
    /// would rather attach a file than paste pixels.
    static func copy(png: Data, file: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let entry = NSPasteboardItem()
        entry.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { entry.setData(tiff, forType: .tiff) }
        entry.setString(file.absoluteString, forType: .fileURL)
        pasteboard.writeObjects([entry])
    }
}
