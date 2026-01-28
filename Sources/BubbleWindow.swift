import Cocoa
import WebKit

class BubbleWindow: NSWindow {
    static let collapsedSize = NSSize(width: 60, height: 60)
    static let expandedSize = NSSize(width: 420, height: 650)
    private static let hoverDelay: TimeInterval = 0.4
    private static let animationDuration: TimeInterval = 0.2
    private static let dragThreshold: CGFloat = 5

    let site: PinnedSite
    private(set) var isExpanded = false
    private(set) var isPinned = false
    private var isAnimating = false
    private var currentPosition: CGFloat
    private var snapshotImage: NSImage?
    private var faviconImage: NSImage?
    private var webViewController: WebViewController?
    private var hoverTimer: Timer?
    private var bubbleContentView: BubbleContentView!
    private var trackingArea: NSTrackingArea?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dragMonitor: Any?
    private var collapseTimer: Timer?
    private var resizeHandles: [ResizeHandleView] = []
    private var previewWebView: WKWebView?

    private var mouseDownLocation: NSPoint = .zero
    private var isDragging = false
    private var dragStartPosition: CGFloat = 0
    private var expandedWidth: CGFloat?
    private var expandedHeight: CGFloat?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        // When window becomes key, focus the webview
        if isExpanded, let webView = webViewController?.getWebView() {
            makeFirstResponder(webView)
        }
    }

    init(site: PinnedSite) {
        self.site = site
        self.currentPosition = site.bubblePosition ?? 0.5

        super.init(
            contentRect: NSRect(origin: .zero, size: BubbleWindow.collapsedSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        bubbleContentView = BubbleContentView(frame: NSRect(origin: .zero, size: BubbleWindow.collapsedSize))
        contentView = bubbleContentView

        setupTrackingArea()
        loadInitialContent()
    }

    private func loadInitialContent() {
        // Always fetch favicon (used as fallback and for favicon mode)
        fetchFavicon()

        if SettingsStore.shared.showBubblePreviews {
            // Also load page in hidden webview to capture snapshot
            loadPreviewSnapshot()
        }
    }

    private func loadPreviewSnapshot() {
        guard let url = URL(string: site.url) else { return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 650), configuration: config)
        webView.customUserAgent = site.userAgent
        previewWebView = webView

        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
    }

    private func fetchFavicon() {
        guard let url = URL(string: site.url),
              let host = url.host else { return }

        // Try common favicon locations
        let faviconURLs = [
            URL(string: "\(url.scheme ?? "https")://\(host)/favicon.ico"),
            URL(string: "\(url.scheme ?? "https")://\(host)/apple-touch-icon.png"),
            URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
        ].compactMap { $0 }

        tryFetchFavicon(from: faviconURLs, index: 0)
    }

    private func tryFetchFavicon(from urls: [URL], index: Int) {
        guard index < urls.count else { return }

        URLSession.shared.dataTask(with: urls[index]) { [weak self] data, response, _ in
            if let data = data,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    image.size = NSSize(width: 32, height: 32)
                    self?.faviconImage = image
                    if self?.isExpanded == false {
                        self?.bubbleContentView.showFavicon(image)
                    }
                }
            } else {
                // Try next URL
                DispatchQueue.main.async {
                    self?.tryFetchFavicon(from: urls, index: index + 1)
                }
            }
        }.resume()
    }

    deinit {
        hoverTimer?.invalidate()
        collapseTimer?.invalidate()
        stopMonitors()
    }

    private var currentExpandedSize: NSSize {
        NSSize(
            width: expandedWidth ?? BubbleWindow.expandedSize.width,
            height: expandedHeight ?? BubbleWindow.expandedSize.height
        )
    }

    private func setupResizeHandles() {
        guard resizeHandles.isEmpty else { return }

        let handleSize: CGFloat = 16
        let bounds = bubbleContentView.bounds

        // Corner positions: bottomLeft, bottomRight, topLeft, topRight
        let corners: [(NSRect, NSView.AutoresizingMask, ResizeCorner)] = [
            // Bottom-left
            (NSRect(x: 0, y: 0, width: handleSize, height: handleSize),
             [.maxXMargin, .maxYMargin], .bottomLeft),
            // Bottom-right
            (NSRect(x: bounds.width - handleSize, y: 0, width: handleSize, height: handleSize),
             [.minXMargin, .maxYMargin], .bottomRight),
            // Top-left
            (NSRect(x: 0, y: bounds.height - handleSize, width: handleSize, height: handleSize),
             [.maxXMargin, .minYMargin], .topLeft),
            // Top-right
            (NSRect(x: bounds.width - handleSize, y: bounds.height - handleSize, width: handleSize, height: handleSize),
             [.minXMargin, .minYMargin], .topRight),
        ]

        for (frame, mask, corner) in corners {
            let handle = ResizeHandleView(frame: frame)
            handle.autoresizingMask = mask
            handle.corner = corner
            handle.onResizeWithCorner = { [weak self] deltaX, deltaY, corner in
                self?.handleResizeFromCorner(deltaX: deltaX, deltaY: deltaY, corner: corner)
            }
            handle.getCurrentSize = { [weak self] in
                self?.frame.size ?? BubbleWindow.expandedSize
            }
            bubbleContentView.addSubview(handle, positioned: .above, relativeTo: nil)
            resizeHandles.append(handle)
        }
    }

    private func removeResizeHandles() {
        resizeHandles.forEach { $0.removeFromSuperview() }
        resizeHandles.removeAll()
    }

    private func handleResizeFromCorner(deltaX: CGFloat, deltaY: CGFloat, corner: ResizeCorner) {
        guard isExpanded, let screen = NSScreen.main else { return }

        let minSize = NSSize(width: 320, height: 400)
        let maxSize = NSSize(width: screen.visibleFrame.width * 0.8, height: screen.visibleFrame.height * 0.9)

        let currentWidth = frame.width
        let currentHeight = frame.height
        var newOrigin = frame.origin

        var newWidth = currentWidth
        var newHeight = currentHeight

        // Apply deltas based on which corner - opposite corner stays fixed
        switch corner {
        case .bottomLeft:
            // Top-right stays fixed
            newWidth = currentWidth - deltaX
            newHeight = currentHeight - deltaY
            newOrigin.x = frame.maxX - max(minSize.width, min(maxSize.width, newWidth))
            newOrigin.y = frame.maxY - max(minSize.height, min(maxSize.height, newHeight))
        case .bottomRight:
            // Top-left stays fixed
            newWidth = currentWidth + deltaX
            newHeight = currentHeight - deltaY
            newOrigin.y = frame.maxY - max(minSize.height, min(maxSize.height, newHeight))
        case .topLeft:
            // Bottom-right stays fixed
            newWidth = currentWidth - deltaX
            newHeight = currentHeight + deltaY
            newOrigin.x = frame.maxX - max(minSize.width, min(maxSize.width, newWidth))
        case .topRight:
            // Bottom-left stays fixed (origin stays same)
            newWidth = currentWidth + deltaX
            newHeight = currentHeight + deltaY
        }

        // Clamp to min/max
        let clampedWidth = max(minSize.width, min(maxSize.width, newWidth))
        let clampedHeight = max(minSize.height, min(maxSize.height, newHeight))

        expandedWidth = clampedWidth
        expandedHeight = clampedHeight

        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: clampedWidth, height: clampedHeight))
        setFrame(newFrame, display: true)

        bubbleContentView.frame = NSRect(origin: .zero, size: NSSize(width: clampedWidth, height: clampedHeight))
    }

    private func setupTrackingArea() {
        if let existing = trackingArea {
            bubbleContentView.removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bubbleContentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        bubbleContentView.addTrackingArea(trackingArea!)
    }

    private func startMonitors() {
        stopMonitors()

        // Global monitor for mouse position check (when app not focused)
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) { [weak self] _ in
            self?.checkMousePosition()
        }

        // Local monitor for mouse position check and Option+drag (when app focused)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .mouseMoved {
                self.checkMousePosition()
            } else if event.type == .leftMouseDown && event.modifierFlags.contains(.option) {
                self.mouseDownLocation = NSEvent.mouseLocation
                self.dragStartPosition = self.currentPosition
                self.isDragging = false
            } else if event.type == .leftMouseDragged && event.modifierFlags.contains(.option) {
                let currentLocation = NSEvent.mouseLocation
                let distance = hypot(currentLocation.x - self.mouseDownLocation.x, currentLocation.y - self.mouseDownLocation.y)
                if !self.isDragging && distance > BubbleWindow.dragThreshold {
                    self.isDragging = true
                }
                if self.isDragging {
                    self.handleDrag()
                    return nil // Consume the event
                }
            } else if event.type == .leftMouseUp && self.isDragging {
                self.finishDrag()
            }

            return event
        }
    }

    private func stopMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
    }

    private func checkMousePosition() {
        guard isExpanded && !isAnimating && !isDragging && !isPinned else {
            collapseTimer?.invalidate()
            collapseTimer = nil
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let expandedFrame = frame.insetBy(dx: -10, dy: -10)

        if !expandedFrame.contains(mouseLocation) {
            // Start collapse timer if not already running
            if collapseTimer == nil {
                collapseTimer = Timer.scheduledTimer(withTimeInterval: BubbleWindow.hoverDelay, repeats: false) { [weak self] _ in
                    self?.collapseTimer = nil
                    // Double-check mouse is still outside and not pinned
                    guard let self = self, !self.isPinned else { return }
                    let currentMouse = NSEvent.mouseLocation
                    if !self.frame.insetBy(dx: -10, dy: -10).contains(currentMouse) {
                        self.collapse()
                    }
                }
            }
        } else {
            // Mouse is inside, cancel any pending collapse
            collapseTimer?.invalidate()
            collapseTimer = nil
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isExpanded && !isDragging && !isAnimating else { return }

        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: BubbleWindow.hoverDelay, repeats: false) { [weak self] _ in
            guard let self = self, !self.isDragging else { return }
            self.expand()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    override func mouseDown(with event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = nil

        mouseDownLocation = NSEvent.mouseLocation
        dragStartPosition = currentPosition

        // Check if Option key is held for dragging expanded window
        let optionHeld = event.modifierFlags.contains(.option)

        // Ensure the window becomes key and the webview can accept typing on click
        if isExpanded && !optionHeld {
            activateAndFocus()
        }

        if !isExpanded || optionHeld {
            isDragging = false // Will be set true on actual drag
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let optionHeld = event.modifierFlags.contains(.option)

        // For collapsed: always allow drag
        // For expanded: only with Option key
        guard !isExpanded || optionHeld else { return }

        let currentLocation = NSEvent.mouseLocation
        let distance = hypot(currentLocation.x - mouseDownLocation.x, currentLocation.y - mouseDownLocation.y)

        if !isDragging && distance > BubbleWindow.dragThreshold {
            isDragging = true
        }

        if isDragging {
            handleDrag()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            finishDrag()
        }
    }

    private func handleDrag() {
        guard let screen = NSScreen.main else { return }

        let currentLocation = NSEvent.mouseLocation
        let edge = SettingsStore.shared.preferredBubbleEdge
        var newPosition: CGFloat

        let windowHeight = isExpanded ? currentExpandedSize.height : BubbleWindow.collapsedSize.height
        let windowWidth = isExpanded ? currentExpandedSize.width : BubbleWindow.collapsedSize.width

        switch edge {
        case .right:
            let delta = currentLocation.y - mouseDownLocation.y
            let availableHeight = screen.visibleFrame.height - windowHeight
            if availableHeight > 0 {
                newPosition = dragStartPosition + (delta / availableHeight)
            } else {
                newPosition = 0.5
            }
        case .bottom:
            let delta = currentLocation.x - mouseDownLocation.x
            let availableWidth = screen.visibleFrame.width - windowWidth
            if availableWidth > 0 {
                newPosition = dragStartPosition + (delta / availableWidth)
            } else {
                newPosition = 0.5
            }
        }

        newPosition = max(0, min(1, newPosition))
        currentPosition = newPosition
        positionOnEdge(edge: edge, position: newPosition)
    }

    private func finishDrag() {
        isDragging = false
        SettingsStore.shared.updateBubblePosition(id: site.id, position: currentPosition)
    }

    func expand() {
        guard !isExpanded && !isAnimating else { return }

        BubbleManager.shared.willExpandBubble(self)

        if webViewController == nil {
            webViewController = WebViewController()
        }
        webViewController?.loadSite(site)

        isExpanded = true
        isAnimating = true

        let edge = SettingsStore.shared.preferredBubbleEdge

        NSAnimationContext.runAnimationGroup { context in
            context.duration = BubbleWindow.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            let expandedFrame = calculateExpandedFrame(edge: edge, position: currentPosition)
            self.animator().setFrame(expandedFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isAnimating = false

            self.bubbleContentView.frame = NSRect(origin: .zero, size: self.currentExpandedSize)

            if let webView = self.webViewController?.view {
                self.bubbleContentView.showWebView(webView)
            }

            self.setupTitleBarCallbacks()
            self.setupResizeHandles()
            self.startMonitors()
            self.activateAndFocus()
        }
    }

    private func setupTitleBarCallbacks() {
        guard let titleBar = bubbleContentView.titleBar else { return }

        titleBar.isPinned = isPinned

        titleBar.onPinToggle = { [weak self] pinned in
            self?.isPinned = pinned
        }

        titleBar.onDrag = { [weak self] deltaX, deltaY in
            guard let self = self else { return }
            var newOrigin = self.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY
            self.setFrameOrigin(newOrigin)
        }
    }

    private func activateAndFocus() {
        // Ensure the app is a foreground app so key events route here
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        // Make window key
        makeKeyAndOrderFront(nil)

        // Focus webview
        if let webView = webViewController?.getWebView() {
            makeFirstResponder(webView)
            _ = webView.becomeFirstResponder()

            // Use JavaScript to ensure document has focus
            webView.evaluateJavaScript("document.body.focus(); window.focus();", completionHandler: nil)
        }

        // Retry with delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.isExpanded else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            if let webView = self.webViewController?.getWebView() {
                self.makeFirstResponder(webView)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.isExpanded else { return }
            if let webView = self.webViewController?.getWebView() {
                self.makeFirstResponder(webView)
                // Try clicking on first input if exists
                webView.evaluateJavaScript("""
                    var input = document.querySelector('input:not([type=hidden]), textarea');
                    if (input) input.focus();
                """, completionHandler: nil)
            }
        }
    }

    func collapse() {
        guard isExpanded && !isAnimating else { return }

        isAnimating = true
        collapseTimer?.invalidate()
        collapseTimer = nil
        stopMonitors()
        removeResizeHandles()

        takeSnapshot { [weak self] in
            self?.performCollapse()
        }
    }

    private func takeSnapshot(completion: @escaping () -> Void) {
        guard let webViewController = webViewController,
              let webView = webViewController.view.subviews.first(where: { $0 is WKWebView }) as? WKWebView else {
            completion()
            return
        }

        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            if let image = image {
                self?.snapshotImage = image
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func performCollapse() {
        isExpanded = false
        isPinned = false

        let edge = SettingsStore.shared.preferredBubbleEdge

        // Show snapshot or favicon based on settings
        if SettingsStore.shared.showBubblePreviews {
            bubbleContentView.showSnapshot(snapshotImage)
        } else {
            bubbleContentView.showFavicon(faviconImage)
        }
        bubbleContentView.frame = NSRect(origin: .zero, size: BubbleWindow.collapsedSize)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = BubbleWindow.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            let collapsedFrame = calculateCollapsedFrame(edge: edge, position: currentPosition)
            self.animator().setFrame(collapsedFrame, display: true)
        } completionHandler: { [weak self] in
            self?.isAnimating = false
            if let self = self {
                BubbleManager.shared.bubbleDidCollapse(self)
            }
        }
    }

    func positionOnEdge(edge: BubbleEdge, position: CGFloat) {
        currentPosition = position
        let newFrame = isExpanded
            ? calculateExpandedFrame(edge: edge, position: position)
            : calculateCollapsedFrame(edge: edge, position: position)
        setFrame(newFrame, display: true)
    }

    private func calculateCollapsedFrame(edge: BubbleEdge, position: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: BubbleWindow.collapsedSize)
        }

        let visibleFrame = screen.visibleFrame
        let size = BubbleWindow.collapsedSize
        var origin = NSPoint.zero

        switch edge {
        case .right:
            origin.x = visibleFrame.maxX - size.width
            origin.y = visibleFrame.origin.y + (visibleFrame.height - size.height) * position
        case .bottom:
            origin.x = visibleFrame.origin.x + (visibleFrame.width - size.width) * position
            origin.y = visibleFrame.origin.y
        }

        return NSRect(origin: origin, size: size)
    }

    private func calculateExpandedFrame(edge: BubbleEdge, position: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: currentExpandedSize)
        }

        let visibleFrame = screen.visibleFrame
        let size = currentExpandedSize
        var origin = NSPoint.zero

        switch edge {
        case .right:
            origin.x = visibleFrame.maxX - size.width
            origin.y = visibleFrame.origin.y + (visibleFrame.height - size.height) * position
            origin.y = max(visibleFrame.origin.y, min(origin.y, visibleFrame.maxY - size.height))
        case .bottom:
            origin.y = visibleFrame.origin.y
            origin.x = visibleFrame.origin.x + (visibleFrame.width - size.width) * position
            origin.x = max(visibleFrame.origin.x, min(origin.x, visibleFrame.maxX - size.width))
        }

        return NSRect(origin: origin, size: size)
    }

    func prepareForRemoval() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        collapseTimer?.invalidate()
        collapseTimer = nil
        stopMonitors()
        removeResizeHandles()
        webViewController = nil
        previewWebView = nil
    }

    func refreshCollapsedContent() {
        guard !isExpanded else { return }

        if SettingsStore.shared.showBubblePreviews {
            if let snapshot = snapshotImage {
                bubbleContentView.showSnapshot(snapshot)
            } else {
                // No snapshot yet, load one
                loadPreviewSnapshot()
            }
        } else {
            if let favicon = faviconImage {
                bubbleContentView.showFavicon(favicon)
            } else {
                // No favicon yet, fetch one
                fetchFavicon()
            }
        }
    }
}

// MARK: - WKNavigationDelegate for initial preview capture

extension BubbleWindow: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Only handle preview webview loading
        guard webView === previewWebView else { return }

        // Wait a moment for page to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.captureInitialSnapshot()
        }
    }

    private func captureInitialSnapshot() {
        guard let webView = previewWebView else { return }

        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self = self else { return }

            if let image = image {
                self.snapshotImage = image
                // Update display if not expanded
                if !self.isExpanded && SettingsStore.shared.showBubblePreviews {
                    self.bubbleContentView.showSnapshot(image)
                }
            }

            // Clean up preview webview
            self.previewWebView = nil
        }
    }
}
