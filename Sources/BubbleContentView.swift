import Cocoa

class BubbleTitleBar: NSView {
    static let height: CGFloat = 28

    private let pinButton: NSButton
    var isPinned: Bool = false {
        didSet {
            updatePinButton()
        }
    }
    var onPinToggle: ((Bool) -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?

    private var isDragging = false
    private var dragStartLocation: NSPoint = .zero

    override init(frame: NSRect) {
        pinButton = NSButton(frame: .zero)
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor

        setupPinButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPinButton() {
        pinButton.bezelStyle = .accessoryBarAction
        pinButton.isBordered = false
        pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")
        pinButton.imagePosition = .imageOnly
        pinButton.target = self
        pinButton.action = #selector(pinTapped)
        pinButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(pinButton)

        NSLayoutConstraint.activate([
            pinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 24),
            pinButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        updatePinButton()
    }

    private func updatePinButton() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pin")
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func pinTapped() {
        isPinned.toggle()
        onPinToggle?(isPinned)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = NSEvent.mouseLocation
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - dragStartLocation.x
        let deltaY = currentLocation.y - dragStartLocation.y
        dragStartLocation = currentLocation
        onDrag?(deltaX, deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}

class BubbleContentView: NSView {
    private let snapshotImageView: NSImageView
    private let faviconImageView: NSImageView
    private let webViewContainer: NSView
    private(set) var titleBar: BubbleTitleBar?

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
        hideTitleBar()
    }

    func showFavicon(_ image: NSImage?) {
        faviconImageView.image = image
        faviconImageView.isHidden = false
        snapshotImageView.isHidden = true
        webViewContainer.isHidden = true
        hideTitleBar()
    }

    func showWebView(_ webView: NSView) {
        showTitleBar()

        // Update container to leave room for title bar
        let titleHeight = BubbleTitleBar.height
        webViewContainer.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height - titleHeight
        )

        webView.frame = webViewContainer.bounds
        webView.autoresizingMask = [.width, .height]

        webViewContainer.subviews.forEach { $0.removeFromSuperview() }
        webViewContainer.addSubview(webView)

        snapshotImageView.isHidden = true
        faviconImageView.isHidden = true
        webViewContainer.isHidden = false
    }

    private func showTitleBar() {
        if titleBar == nil {
            let titleHeight = BubbleTitleBar.height
            let bar = BubbleTitleBar(frame: NSRect(
                x: 0,
                y: bounds.height - titleHeight,
                width: bounds.width,
                height: titleHeight
            ))
            bar.autoresizingMask = [.width, .minYMargin]
            addSubview(bar)
            titleBar = bar
        }
        titleBar?.isHidden = false
    }

    private func hideTitleBar() {
        titleBar?.isHidden = true
    }

    func getWebViewContainer() -> NSView {
        return webViewContainer
    }
}
