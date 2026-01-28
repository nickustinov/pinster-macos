import Cocoa

class BubbleContentView: NSView {
    private let snapshotImageView: NSImageView
    private let faviconImageView: NSImageView
    private let webViewContainer: NSView

    override init(frame: NSRect) {
        snapshotImageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        snapshotImageView.imageScaling = .scaleProportionallyUpOrDown
        snapshotImageView.autoresizingMask = [.width, .height]

        // Favicon is centered and fixed size
        let faviconSize: CGFloat = 32
        faviconImageView = NSImageView(frame: NSRect(
            x: (frame.width - faviconSize) / 2,
            y: (frame.height - faviconSize) / 2,
            width: faviconSize,
            height: faviconSize
        ))
        faviconImageView.imageScaling = .scaleProportionallyUpOrDown
        faviconImageView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]

        webViewContainer = NSView(frame: NSRect(origin: .zero, size: frame.size))
        webViewContainer.autoresizingMask = [.width, .height]

        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addSubview(snapshotImageView)
        addSubview(faviconImageView)
        addSubview(webViewContainer)

        snapshotImageView.isHidden = true
        faviconImageView.isHidden = true
        webViewContainer.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // When collapsed (webViewContainer hidden), return self to handle mouse events
        // This prevents image views from intercepting clicks
        if webViewContainer.isHidden {
            return bounds.contains(point) ? self : nil
        }
        return super.hitTest(point)
    }

    func showSnapshot(_ image: NSImage?) {
        snapshotImageView.image = image
        snapshotImageView.isHidden = false
        faviconImageView.isHidden = true
        webViewContainer.isHidden = true
    }

    func showFavicon(_ image: NSImage?) {
        faviconImageView.image = image
        faviconImageView.isHidden = false
        snapshotImageView.isHidden = true
        webViewContainer.isHidden = true
    }

    func showWebView(_ webView: NSView) {
        // Update container to match our bounds
        webViewContainer.frame = bounds

        webView.frame = webViewContainer.bounds
        webView.autoresizingMask = [.width, .height]

        webViewContainer.subviews.forEach { $0.removeFromSuperview() }
        webViewContainer.addSubview(webView)

        snapshotImageView.isHidden = true
        faviconImageView.isHidden = true
        webViewContainer.isHidden = false
    }

    func getWebViewContainer() -> NSView {
        return webViewContainer
    }
}
