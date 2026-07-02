import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    // ponytail: one live webview per menu bar site, kept for the app's lifetime
    // so pages preserve state between opens; add an unload policy if memory bites
    private var webViewControllers: [UUID: WebViewController] = [:]
    private var currentSite: PinnedSite?
    private var clickOutsideMonitor: Any?
    private var settingsWindow: NSWindow?
    private var defaultMenuBarIcon: NSImage?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupMainMenu()

        // Register global hotkeys
        HotkeyManager.shared.reregisterAll()

        // Show bubbles for bubble-mode sites
        BubbleManager.shared.showBubblesForSites()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sitesChanged),
            name: .pinnedSitesChanged,
            object: nil
        )
    }

    @objc private func sitesChanged() {
        rebuildMenu()
        HotkeyManager.shared.reregisterAll()
        BubbleManager.shared.showBubblesForSites()

        // Drop cached webviews for sites that were removed or moved to bubble mode
        let menuBarIds = Set(SettingsStore.shared.pinnedSites.filter { $0.displayMode == .menuBar }.map(\.id))
        webViewControllers = webViewControllers.filter { menuBarIds.contains($0.key) }
    }

    // MARK: - Status Item & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        defaultMenuBarIcon = createMenuBarIcon()
        if let button = statusItem.button {
            button.image = defaultMenuBarIcon
        }

        rebuildMenu()
    }

    private func createMenuBarIcon() -> NSImage {
        if let bundlePath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
           let image = NSImage(contentsOfFile: bundlePath) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        // Fallback: simple pin shape
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 9, y: 2))
            path.line(to: NSPoint(x: 9, y: 16))
            path.move(to: NSPoint(x: 4, y: 12))
            path.line(to: NSPoint(x: 14, y: 12))
            path.lineWidth = 2.0
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let menuBarSites = SettingsStore.shared.pinnedSites.filter { $0.displayMode == .menuBar }

        for site in menuBarSites {
            let item = NSMenuItem(title: site.name, action: #selector(openSite(_:)), keyEquivalent: "")
            item.representedObject = site

            if !site.shortcut.isEmpty {
                let attributed = NSMutableAttributedString(string: "\(site.name)  \(site.shortcut)")
                let shortcutRange = NSRange(location: site.name.count + 2, length: site.shortcut.count)
                attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: shortcutRange)
                item.attributedTitle = attributed
            }

            menu.addItem(item)
        }

        if !menuBarSites.isEmpty {
            menu.addItem(.separator())
        }

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Itsypin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openSite(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? PinnedSite else { return }
        showPopover(for: site)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsView())
            let panel = NSPanel(contentViewController: hostingController)
            panel.title = "Settings"
            panel.styleMask = [.titled, .closable, .resizable, .nonactivatingPanel]
            panel.center()
            panel.setFrameAutosaveName("SettingsWindow")
            panel.hidesOnDeactivate = false
            settingsWindow = panel
        }

        setupMainMenu()
        popover.performClose(nil)
        settingsWindow?.level = .floating
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.settingsWindow?.level = .normal
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Itsypin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (enables Cmd+C, Cmd+V, Cmd+A, etc.)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Hotkey Callbacks

    func openSiteFromHotkey(_ site: PinnedSite) {
        if site.displayMode == .bubble {
            BubbleManager.shared.expandBubble(for: site.id)
        } else {
            showPopover(for: site)
        }
    }

    func toggleSiteFromHotkey(_ site: PinnedSite) {
        if site.displayMode == .bubble {
            BubbleManager.shared.toggleBubble(for: site.id)
        } else {
            if popover.isShown && currentSite?.id == site.id {
                popover.performClose(nil)
            } else {
                showPopover(for: site)
            }
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func showPopover(for site: PinnedSite) {
        guard let button = statusItem.button else { return }

        if popover.isShown && currentSite?.id == site.id {
            popover.performClose(nil)
            return
        }

        let wasShown = popover.isShown
        currentSite = site
        statusItem.button?.image = statusIcon(for: site)

        let controller = webViewController(for: site)
        controller.loadSite(site) // no-op unless the site's URL or user agent changed
        popover.contentViewController = controller
        popover.contentSize = site.windowSize

        if !wasShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            startClickOutsideMonitor()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            controller.makeWebViewFirstResponder()
        }
    }

    private func webViewController(for site: PinnedSite) -> WebViewController {
        if let existing = webViewControllers[site.id] {
            return existing
        }

        let controller = WebViewController()
        controller.onResize = { [weak self] newSize in
            self?.popover.contentSize = newSize
            SettingsStore.shared.updateSiteSize(id: site.id, size: newSize)
        }
        controller.onFaviconLoaded = { [weak self] favicon in
            guard let self = self, self.currentSite?.id == site.id, self.popover.isShown,
                  self.currentSite?.customIcon == nil else { return }
            if let favicon = favicon {
                self.statusItem.button?.image = favicon
            }
        }
        webViewControllers[site.id] = controller
        return controller
    }

    private func statusIcon(for site: PinnedSite) -> NSImage? {
        if let data = site.customIcon, let image = NSImage(data: data) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return defaultMenuBarIcon
    }

    func popoverDidClose(_ notification: Notification) {
        stopClickOutsideMonitor()
        statusItem.button?.image = defaultMenuBarIcon
    }

    private func startClickOutsideMonitor() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover.isShown == true {
                self?.popover.performClose(nil)
            }
        }
    }

    private func stopClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

}
