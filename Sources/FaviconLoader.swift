import Cocoa

extension NSImage {
    /// PNG data downscaled so the longest edge is at most `maxDimension` pixels.
    func pngData(maxDimension: CGFloat) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

enum FaviconLoader {
    /// Downloads the first URL in `urls` that yields a decodable image,
    /// resized to `size` points. Calls `completion` on the main queue.
    static func fetch(from urls: [URL], size: CGFloat, completion: @escaping (NSImage?) -> Void) {
        guard let url = urls.first else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, _ in
            let statusOK = (response as? HTTPURLResponse).map { $0.statusCode == 200 } ?? true
            if let data, statusOK, let image = NSImage(data: data) {
                image.size = NSSize(width: size, height: size)
                DispatchQueue.main.async { completion(image) }
            } else {
                fetch(from: Array(urls.dropFirst()), size: size, completion: completion)
            }
        }.resume()
    }
}
