import AppKit

/// One caption. The rect is normalised to the image with a top-left origin, so
/// the preview and the full-resolution export share the same layout.
struct TextBox: Identifiable, Equatable, Codable {
    var id = UUID()
    var text = ""
    var rect: CGRect

    static func defaults() -> [TextBox] {
        [
            TextBox(rect: CGRect(x: 0.04, y: 0.02, width: 0.92, height: 0.22)),
            TextBox(rect: CGRect(x: 0.04, y: 0.76, width: 0.92, height: 0.22)),
        ]
    }

    static func extra() -> TextBox {
        TextBox(rect: CGRect(x: 0.04, y: 0.39, width: 0.92, height: 0.22))
    }
}

/// Draws the classic meme look: white Impact capitals with a heavy black outline,
/// shrunk until the text fits its box.
enum MemeRenderer {
    static func font(size: CGFloat) -> NSFont {
        NSFont(name: "Impact", size: size)
            ?? NSFont(name: "Arial-Black", size: size)
            ?? .systemFont(ofSize: size, weight: .black)
    }

    /// A resolution-independent image: AppKit calls the handler again at whatever
    /// size it is displayed, so one function serves the preview and the export.
    static func image(base: NSImage, boxes: [TextBox], size: CGSize) -> NSImage {
        NSImage(size: size, flipped: true) { bounds in
            base.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            for box in boxes { draw(box, in: bounds) }
            return true
        }
    }

    /// The template's native pixel size, which is what the export is rendered at.
    static func pixelSize(of image: NSImage) -> CGSize {
        let best = image.representations.max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        if let best, best.pixelsWide > 0, best.pixelsHigh > 0 {
            return CGSize(width: best.pixelsWide, height: best.pixelsHigh)
        }
        return image.size
    }

    static func png(base: NSImage, boxes: [TextBox]) -> Data? {
        let size = pixelSize(of: base)
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image(base: base, boxes: boxes, size: size).draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func draw(_ box: TextBox, in bounds: CGRect) {
        let text = box.text.uppercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let r = CGRect(
            x: bounds.minX + box.rect.minX * bounds.width,
            y: bounds.minY + box.rect.minY * bounds.height,
            width: box.rect.width * bounds.width,
            height: box.rect.height * bounds.height
        )
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping

        func measure(_ size: CGFloat) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font(size: size), .paragraphStyle: style])
                .boundingRect(with: CGSize(width: r.width, height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin]).height
        }

        var size = min(r.height, bounds.width * 0.14)
        let floor = bounds.width * 0.02
        var height = measure(size)
        while height > r.height, size > floor {
            size *= 0.94
            height = measure(size)
        }

        let target = CGRect(x: r.minX, y: r.minY + (r.height - height) / 2, width: r.width, height: height)
        // The outline is black copies of the text ringed around the original. A
        // real stroke uses miter joins, which spike on sharp letters like A and Y.
        let outline: [NSAttributedString.Key: Any] = [
            .font: font(size: size), .paragraphStyle: style, .foregroundColor: NSColor.black,
        ]
        let fill: [NSAttributedString.Key: Any] = [
            .font: font(size: size), .paragraphStyle: style, .foregroundColor: NSColor.white,
        ]
        let radius = size * 0.05
        let steps = 20
        let black = NSAttributedString(string: text, attributes: outline)
        for i in 0..<steps {
            let angle = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
            black.draw(in: target.offsetBy(dx: cos(angle) * radius, dy: sin(angle) * radius))
        }
        NSAttributedString(string: text, attributes: fill).draw(in: target)
    }
}
