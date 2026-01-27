import Cocoa
import Carbon.HIToolbox

class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeys: [UInt32: (id: EventHotKeyID, ref: EventHotKeyRef?, site: PinnedSite)] = [:]
    private var nextId: UInt32 = 1

    // Triple-tap tracking
    private var modifierPressTimestamps: [String: [Date]] = [:]
    private let tripleTapWindow: TimeInterval = 0.5
    private var localEventMonitor: Any?

    private init() {
        installCarbonHandler()
        installTripleTapMonitor()
    }

    // MARK: - Carbon Hotkeys (works without Accessibility permission)

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                HotkeyManager.shared.handleHotkey(id: hotkeyID.id)
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    private func handleHotkey(id: UInt32) {
        guard let hotkey = hotkeys[id] else { return }
        DispatchQueue.main.async {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.openSiteFromHotkey(hotkey.site)
            }
        }
    }

    func register(site: PinnedSite) {
        guard let keys = site.shortcutKeys, !keys.isTripleTap else { return }

        let id = nextId
        nextId += 1

        let hotkeyID = EventHotKeyID(signature: OSType(0x4954_5359), id: id) // "ITSY"
        var hotkeyRef: EventHotKeyRef?

        let modifiers = carbonModifiers(from: NSEvent.ModifierFlags(rawValue: keys.modifiers))

        let status = RegisterEventHotKey(
            UInt32(keys.keyCode),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr {
            hotkeys[id] = (hotkeyID, hotkeyRef, site)
        }
    }

    func unregisterAll() {
        for (_, hotkey) in hotkeys {
            if let ref = hotkey.ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeys.removeAll()
        nextId = 1
    }

    func reregisterAll() {
        unregisterAll()
        for site in SettingsStore.shared.pinnedSites {
            register(site: site)
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    // MARK: - Triple-tap Monitor

    private func installTripleTapMonitor() {
        // Global monitor for when app is not focused (may need Accessibility permission)
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Local monitor for when app is focused
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        var pressedModifier: String?
        if flags == .option { pressedModifier = "option" }
        else if flags == .control { pressedModifier = "control" }
        else if flags == .shift { pressedModifier = "shift" }

        guard let modifier = pressedModifier else { return }

        let now = Date()
        var timestamps = modifierPressTimestamps[modifier] ?? []
        timestamps.append(now)
        timestamps = timestamps.filter { now.timeIntervalSince($0) < tripleTapWindow }
        modifierPressTimestamps[modifier] = timestamps

        if timestamps.count >= 3 {
            modifierPressTimestamps[modifier] = []

            let sites = SettingsStore.shared.pinnedSites
            if let site = sites.first(where: {
                $0.shortcutKeys?.isTripleTap == true && $0.shortcutKeys?.tapModifier == modifier
            }) {
                DispatchQueue.main.async {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.toggleSiteFromHotkey(site)
                    }
                }
            }
        }
    }

    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
