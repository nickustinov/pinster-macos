import Cocoa
import WebKit

// MARK: - Resize Handle View

class ResizeHandleView: NSView {
    private let minSize = NSSize(width: 320, height: 400)
    private var isResizing = false
    private var initialMouseLocation: NSPoint = .zero
    private var initialSize: NSSize = .zero

    var onResize: ((NSSize) -> Void)?
    var getCurrentSize: (() -> NSSize)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only respond to clicks in our bounds, pass through everything else
        let localPoint = convert(point, from: superview)
        if bounds.contains(localPoint) {
            return super.hitTest(point)
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()

        let path = NSBezierPath()
        for i in 0..<3 {
            let offset = CGFloat(i) * 4 + 4
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + offset))
        }
        path.lineWidth = 1.5
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        isResizing = true
        initialMouseLocation = NSEvent.mouseLocation
        initialSize = getCurrentSize?() ?? frame.size
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing else { return }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = initialMouseLocation.y - currentLocation.y

        var newWidth = initialSize.width + deltaX
        var newHeight = initialSize.height + deltaY

        newWidth = max(minSize.width, newWidth)
        newHeight = max(minSize.height, newHeight)

        onResize?(NSSize(width: newWidth, height: newHeight))
    }

    override func mouseUp(with event: NSEvent) {
        isResizing = false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    // Don't intercept scroll events
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

// MARK: - WebView Controller

class WebViewController: NSViewController, WKUIDelegate, WKNavigationDelegate {
    private var webView: WKWebView!
    private var loadingOverlay: NSView!
    private var spinner: NSProgressIndicator!
    private var containerView: NSView!
    private var resizeHandle: ResizeHandleView!
    private var authWindow: NSWindow?
    private var authWebView: WKWebView?
    private var currentHost: String?

    var onResize: ((NSSize) -> Void)?
    var onFaviconLoaded: ((NSImage?) -> Void)?

    override func loadView() {
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 650))
        containerView.wantsLayer = true

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: containerView.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        containerView.addSubview(webView)

        loadingOverlay = NSView(frame: containerView.bounds)
        loadingOverlay.autoresizingMask = [.width, .height]
        loadingOverlay.wantsLayer = true
        loadingOverlay.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.addSubview(spinner)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor)
        ])

        containerView.addSubview(loadingOverlay)
        loadingOverlay.isHidden = true

        // Resize handle on top (small corner area only)
        resizeHandle = ResizeHandleView(frame: NSRect(x: containerView.bounds.width - 16, y: 0, width: 16, height: 16))
        resizeHandle.autoresizingMask = [.minXMargin, .maxYMargin]
        resizeHandle.onResize = { [weak self] newSize in
            self?.onResize?(newSize)
        }
        resizeHandle.getCurrentSize = { [weak self] in
            self?.view.frame.size ?? NSSize(width: 420, height: 650)
        }
        containerView.addSubview(resizeHandle)

        self.view = containerView
    }

    func makeWebViewFirstResponder() {
        view.window?.makeFirstResponder(webView)
    }

    func loadSite(_ site: PinnedSite) {
        guard let url = URL(string: site.url) else { return }

        // Ensure view is loaded
        _ = self.view

        let newHost = url.host

        // Update user agent
        webView.customUserAgent = site.userAgent

        // Only reload if switching to a different site
        if currentHost == newHost {
            // Still fetch favicon for already-loaded site
            fetchFavicon()
            return
        }

        showLoading()
        currentHost = newHost
        webView.load(URLRequest(url: url))
    }

    private func showLoading() {
        loadingOverlay.isHidden = false
        spinner.startAnimation(nil)
    }

    private func hideLoading() {
        spinner.stopAnimation(nil)
        loadingOverlay.isHidden = true
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {

        let authWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 700), configuration: configuration)
        authWebView.customUserAgent = self.webView.customUserAgent
        authWebView.uiDelegate = self
        authWebView.navigationDelegate = self

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = authWebView
        window.title = "Sign in"
        window.center()
        window.isReleasedWhenClosed = false

        // Close popover before showing auth window
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.closePopover()
        }

        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Reset to normal level after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            window.level = .normal
        }

        self.authWindow = window
        self.authWebView = authWebView

        return authWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView == authWebView {
            closeAuthWindow()
        }
    }

    private func closeAuthWindow() {
        authWindow?.close()
        authWindow = nil
        authWebView = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView == self.webView {
            showLoading()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView == self.webView {
            hideLoading()
            fetchFavicon()
        }

        if webView == authWebView,
           let url = webView.url,
           url.host?.contains("claude.ai") == true || url.host?.contains("anthropic") == true {
            closeAuthWindow()
            self.webView.reload()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView == self.webView {
            hideLoading()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView == self.webView {
            hideLoading()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - Favicon

    private func fetchFavicon() {
        let js = """
        (function() {
            var link = document.querySelector("link[rel*='icon']");
            if (link) return link.href;
            return window.location.origin + '/favicon.ico';
        })()
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let urlString = result as? String,
                  let url = URL(string: urlString) else {
                self?.onFaviconLoaded?(nil)
                return
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
                DispatchQueue.main.async {
                    if let data = data, let image = NSImage(data: data) {
                        image.size = NSSize(width: 18, height: 18)
                        image.isTemplate = false
                        self?.onFaviconLoaded?(image)
                    } else {
                        self?.onFaviconLoaded?(nil)
                    }
                }
            }.resume()
        }
    }
}
