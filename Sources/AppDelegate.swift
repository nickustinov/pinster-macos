import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var currentWebViewController: WebViewController?
    private var currentSite: PinnedSite?
    private var clickOutsideMonitor: Any?
    private var settingsWindow: NSWindow?
    private var defaultMenuBarIcon: NSImage?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setAppIcon()
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

    private func setAppIcon() {
        // Prefer bundled icon (release builds), fall back to Assets for dev runs.
        if let bundlePath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: bundlePath) {
            NSApp.applicationIconImage = image
            return
        }

        let devPaths = [
            FileManager.default.currentDirectoryPath + "/Assets/AppIcon.icns",
            (ProcessInfo.processInfo.environment["PWD"] ?? "") + "/Assets/AppIcon.icns"
        ]

        for path in devPaths {
            if let image = NSImage(contentsOfFile: path) {
                NSApp.applicationIconImage = image
                return
            }
        }
    }

    @objc private func sitesChanged() {
        rebuildMenu()
        HotkeyManager.shared.reregisterAll()
        BubbleManager.shared.showBubblesForSites()
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
        // Try to load from bundle first (for release builds)
        if let bundlePath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
           let image = NSImage(contentsOfFile: bundlePath) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        // Fallback: load from Assets folder (for development)
        let devPaths = [
            FileManager.default.currentDirectoryPath + "/Assets/MenuBarIcon.png",
            (ProcessInfo.processInfo.environment["PWD"] ?? "") + "/Assets/MenuBarIcon.png"
        ]

        for path in devPaths {
            if let image = NSImage(contentsOfFile: path) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }

        // Final fallback: simple pin shape
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
        menu.addItem(NSMenuItem(title: "Quit Pinster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

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

        // Allow keyboard input without showing dock icon
        settingsWindow?.perform(Selector(("_setPreventsActivation:")), with: NSNumber(value: false))

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
        appMenu.addItem(NSMenuItem(title: "Quit Pinster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

        if popover.isShown {
            if currentSite?.id == site.id {
                popover.performClose(nil)
                return
            }
            // Reset to default icon when switching sites
            statusItem.button?.image = defaultMenuBarIcon
            currentWebViewController?.loadSite(site)
            popover.contentSize = site.windowSize
            currentSite = site
            return
        }

        // Reset to default icon when opening popover
        statusItem.button?.image = defaultMenuBarIcon

        if currentWebViewController == nil {
            currentWebViewController = WebViewController()
            currentWebViewController?.onResize = { [weak self] newSize in
                self?.popover.contentSize = newSize
                if let siteId = self?.currentSite?.id {
                    SettingsStore.shared.updateSiteSize(id: siteId, size: newSize)
                }
            }
            currentWebViewController?.onFaviconLoaded = { [weak self] favicon in
                guard let self = self, self.popover.isShown else { return }
                if let favicon = favicon {
                    self.statusItem.button?.image = favicon
                }
            }
        }

        currentSite = site
        currentWebViewController?.loadSite(site)
        popover.contentViewController = currentWebViewController
        popover.contentSize = site.windowSize

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.currentWebViewController?.makeWebViewFirstResponder()
        }

        startClickOutsideMonitor()
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
