import Cocoa

class BubbleTitleBar: NSView {
    static let height: CGFloat = 28

    private let pinButton: NSButton
    private let mobileButton: NSButton
    var isPinned: Bool = false {
        didSet {
            updatePinButton()
        }
    }
    var isMobileViewOn: Bool = false {
        didSet {
            updateMobileButton()
        }
    }
    var onPinToggle: ((Bool) -> Void)?
    var onUserAgentToggle: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?

    private var isDragging = false
    private var dragStartLocation: NSPoint = .zero
    private var currentBackgroundColor: NSColor = .windowBackgroundColor

    override init(frame: NSRect) {
        pinButton = NSButton(frame: .zero)
        mobileButton = NSButton(frame: .zero)
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 12
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] // Top corners only

        setupPinButton()
        setupMobileButton()
    }

    func updateBackgroundColor(_ color: NSColor) {
        currentBackgroundColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.95).cgColor

        // Adjust button colors for contrast
        let brightness = color.brightnessComponent
        pinButton.contentTintColor = isPinned ? .controlAccentColor : (brightness > 0.5 ? .darkGray : .lightGray)
        mobileButton.contentTintColor = isMobileViewOn ? .controlAccentColor : (brightness > 0.5 ? .darkGray : .lightGray)
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
        let brightness = currentBackgroundColor.brightnessComponent
        pinButton.contentTintColor = isPinned ? .controlAccentColor : (brightness > 0.5 ? .darkGray : .lightGray)
    }

    private func setupMobileButton() {
        mobileButton.bezelStyle = .accessoryBarAction
        mobileButton.isBordered = false
        mobileButton.imagePosition = .imageOnly
        mobileButton.target = self
        mobileButton.action = #selector(mobileTapped)
        mobileButton.toolTip = "Toggle mobile view"
        mobileButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mobileButton)

        NSLayoutConstraint.activate([
            mobileButton.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -4),
            mobileButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            mobileButton.widthAnchor.constraint(equalToConstant: 24),
            mobileButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        updateMobileButton()
    }

    private func updateMobileButton() {
        mobileButton.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Toggle mobile view")
        let brightness = currentBackgroundColor.brightnessComponent
        mobileButton.contentTintColor = isMobileViewOn ? .controlAccentColor : (brightness > 0.5 ? .darkGray : .lightGray)
    }

    @objc private func pinTapped() {
        isPinned.toggle()
        onPinToggle?(isPinned)
    }

    @objc private func mobileTapped() {
        onUserAgentToggle?()
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

enum FaviconPlacement {
    case center
    case edge(BubbleEdge)
    case corner(HotCorner)
}

class BubbleContentView: NSView {
    private let snapshotImageView: NSImageView
    private let faviconImageView: NSImageView
    private let webViewContainer: NSView
    private(set) var titleBar: BubbleTitleBar?

    /// Where the icon sits when the bubble background is hidden.
    var faviconPlacement: FaviconPlacement = .center

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
        faviconImageView.wantsLayer = true
        faviconImageView.layer?.cornerRadius = faviconSize * 0.25
        faviconImageView.layer?.masksToBounds = true

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
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hideTitleBar()
    }

    func showFavicon(_ image: NSImage?) {
        faviconImageView.image = image
        faviconImageView.frame = faviconFrame()
        faviconImageView.isHidden = false
        snapshotImageView.isHidden = true
        webViewContainer.isHidden = true
        if SettingsStore.shared.showBubbleBackground {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            // Visually transparent, but not alpha 0 — the window server treats
            // fully transparent pixels as click-through
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.01).cgColor
        }
        hideTitleBar()
    }

    private func faviconFrame() -> NSRect {
        let size = faviconImageView.frame.size
        var origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)

        // With no visible background, sit flush against the screen edge
        if !SettingsStore.shared.showBubbleBackground {
            switch faviconPlacement {
            case .center:
                break
            case .edge(.right):
                origin.x = bounds.width - size.width
            case .edge(.bottom):
                origin.y = 0
            case .corner(.bottomLeft):
                origin = .zero
            case .corner(.bottomRight):
                origin = NSPoint(x: bounds.width - size.width, y: 0)
            }
        }

        return NSRect(origin: origin, size: size)
    }

    func showWebView(_ webView: NSView) {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        showTitleBar()

        // Update container to leave room for title bar (use integral rect to avoid subpixel gaps)
        let titleHeight = BubbleTitleBar.height
        webViewContainer.frame = NSIntegralRect(NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height - titleHeight
        ))

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
