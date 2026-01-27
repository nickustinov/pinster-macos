import Cocoa
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var currentWebViewController: WebViewController?
    private var currentSite: PinnedSite?
    private var clickOutsideMonitor: Any?
    private var settingsWindow: NSWindow?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()

        // Register global hotkeys
        HotkeyManager.shared.reregisterAll()

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
    }

    // MARK: - Status Item & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = createMenuBarIcon()
        }

        rebuildMenu()
    }

    private func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let scale: CGFloat = 18.0 / 256.0
            let transform = NSAffineTransform()
            transform.scale(by: scale)

            let path = NSBezierPath()
            // Asterisk shape from SVG
            path.move(to: NSPoint(x: 214.86, y: 256 - 180.12))
            path.curve(to: NSPoint(x: 203.86, y: 256 - 182.86),
                      controlPoint1: NSPoint(x: 214.86 - 2, y: 256 - 180.12 - 3),
                      controlPoint2: NSPoint(x: 203.86 + 3, y: 256 - 182.86 + 1))

            // Simplified: draw the asterisk using lines
            let center = NSPoint(x: 128 * scale, y: 128 * scale)
            let length: CGFloat = 88 * scale
            let armWidth: CGFloat = 8 * scale

            path.removeAllPoints()

            // Draw 6-pointed asterisk
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3 - .pi / 2
                let outer = NSPoint(
                    x: center.x + cos(angle) * length,
                    y: center.y + sin(angle) * length
                )
                path.move(to: center)
                path.line(to: outer)
            }

            path.lineWidth = 3.0
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

        for site in SettingsStore.shared.pinnedSites {
            let item = NSMenuItem(title: site.name, action: #selector(openSite(_:)), keyEquivalent: "")
            item.representedObject = site

            if let keys = site.shortcutKeys, !keys.isTripleTap {
                let modifiers = NSEvent.ModifierFlags(rawValue: keys.modifiers)
                item.keyEquivalentModifierMask = modifiers
                if let char = keyCodeToCharacter(keys.keyCode)?.lowercased() {
                    item.keyEquivalent = char
                }
            }

            menu.addItem(item)
        }

        if !SettingsStore.shared.pinnedSites.isEmpty {
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit itsyweb", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let result = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard result == noErr && length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: - Actions

    @objc private func openSite(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? PinnedSite else { return }
        showPopover(for: site)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            settingsWindow = window
        }

        popover.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Hotkey Callbacks

    func openSiteFromHotkey(_ site: PinnedSite) {
        showPopover(for: site)
    }

    func toggleSiteFromHotkey(_ site: PinnedSite) {
        if popover.isShown && currentSite?.id == site.id {
            popover.performClose(nil)
        } else {
            showPopover(for: site)
        }
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
            currentWebViewController?.loadSite(site)
            popover.contentSize = site.windowSize
            currentSite = site
            return
        }

        if currentWebViewController == nil {
            currentWebViewController = WebViewController()
            currentWebViewController?.onResize = { [weak self] newSize in
                self?.popover.contentSize = newSize
                if let siteId = self?.currentSite?.id {
                    SettingsStore.shared.updateSiteSize(id: siteId, size: newSize)
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
