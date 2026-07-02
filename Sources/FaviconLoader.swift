import Cocoa

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
