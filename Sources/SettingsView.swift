import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var showingAddSite = false
    @State private var editingSite: PinnedSite?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $store.launchAtLogin)
            }

            Section {
                ForEach(store.pinnedSites) { site in
                    HStack {
                        Image(systemName: site.useMobileUserAgent ? "iphone" : "globe")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name)
                                .fontWeight(.medium)
                            Text(site.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !site.shortcut.isEmpty {
                            Text(site.shortcut)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary)
                                .cornerRadius(6)
                        }

                        Button {
                            editingSite = site
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)

                        Button(role: .destructive) {
                            store.removeSite(id: site.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    showingAddSite = true
                } label: {
                    Label("Add site", systemImage: "plus")
                }
            } header: {
                Text("Pinned sites")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
        .sheet(isPresented: $showingAddSite) {
            AddEditSiteView(site: nil) { newSite in
                store.addSite(newSite)
            }
        }
        .sheet(item: $editingSite) { site in
            AddEditSiteView(site: site) { updatedSite in
                store.updateSite(updatedSite)
            }
        }
        .onAppear {
            store.syncLaunchAtLoginStatus()
        }
    }
}

// MARK: - Add/Edit Site View

struct AddEditSiteView: View {
    let site: PinnedSite?
    let onSave: (PinnedSite) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var shortcut: String = ""
    @State private var shortcutKeys: ShortcutKeys?
    @State private var useMobileUserAgent: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)
                TextField("URL", text: $url)

                ShortcutRecorderView(shortcut: $shortcut, shortcutKeys: $shortcutKeys)

                Toggle("Use mobile view", isOn: $useMobileUserAgent)
                    .help("Uses iPhone user agent for compact mobile layouts")
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(site == nil ? "Add" : "Save") {
                    saveSite()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || url.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
        .onAppear {
            if let site = site {
                name = site.name
                url = site.url
                shortcut = site.shortcut
                shortcutKeys = site.shortcutKeys
                useMobileUserAgent = site.useMobileUserAgent
            }
        }
    }

    private func saveSite() {
        let newSite = PinnedSite(
            id: site?.id ?? UUID(),
            name: name,
            url: url.hasPrefix("http") ? url : "https://\(url)",
            shortcut: shortcut,
            shortcutKeys: shortcutKeys,
            useMobileUserAgent: useMobileUserAgent,
            windowWidth: site?.windowWidth,
            windowHeight: site?.windowHeight
        )
        onSave(newSite)
    }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorderView: View {
    @Binding var shortcut: String
    @Binding var shortcutKeys: ShortcutKeys?
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text("Shortcut")

            Spacer()

            Button {
                if isRecording {
                    isRecording = false
                } else {
                    isRecording = true
                }
            } label: {
                if isRecording {
                    Text("Press keys...")
                        .foregroundStyle(.orange)
                } else if shortcut.isEmpty {
                    Text("Click to record")
                        .foregroundStyle(.secondary)
                } else {
                    Text(shortcut)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .buttonStyle(.bordered)
            .background(
                ShortcutRecorderHelper(
                    isRecording: $isRecording,
                    shortcut: $shortcut,
                    shortcutKeys: $shortcutKeys
                )
            )

            if !shortcut.isEmpty {
                Button {
                    shortcut = ""
                    shortcutKeys = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct ShortcutRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var shortcut: String
    @Binding var shortcutKeys: ShortcutKeys?

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutRecorded = { keys, displayString in
            shortcut = displayString
            shortcutKeys = keys
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? ShortcutRecorderNSView {
            view.isRecording = isRecording
        }
    }
}

class ShortcutRecorderNSView: NSView {
    var isRecording = false
    var onShortcutRecorded: ((ShortcutKeys, String) -> Void)?

    private var monitor: Any?
    private var tripleTapTimestamps: [Date] = []

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupMonitor()
    }

    private func setupMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            if event.type == .flagsChanged {
                // Track modifier triple-taps
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                var modifier: String?

                if flags == .option { modifier = "option" }
                else if flags == .control { modifier = "control" }
                else if flags == .shift { modifier = "shift" }

                if let mod = modifier {
                    let now = Date()
                    self.tripleTapTimestamps.append(now)
                    self.tripleTapTimestamps = self.tripleTapTimestamps.filter { now.timeIntervalSince($0) < 0.5 }

                    if self.tripleTapTimestamps.count >= 3 {
                        self.tripleTapTimestamps.removeAll()
                        let symbol = mod == "option" ? "⌥" : mod == "control" ? "⌃" : "⇧"
                        let keys = ShortcutKeys(modifiers: 0, keyCode: 0, isTripleTap: true, tapModifier: mod)
                        self.onShortcutRecorded?(keys, "\(symbol)\(symbol)\(symbol)")
                        return nil
                    }
                }
                return event
            }

            if event.type == .keyDown {
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                // Require at least one modifier for key shortcuts
                guard !modifiers.isEmpty else { return event }

                let keyCode = event.keyCode
                let displayString = self.shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
                let keys = ShortcutKeys(
                    modifiers: modifiers.rawValue,
                    keyCode: keyCode,
                    isTripleTap: false,
                    tapModifier: nil
                )
                self.onShortcutRecorded?(keys, displayString)
                return nil
            }

            return event
        }
    }

    private func shortcutDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""

        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }

        result += keyCodeToString(keyCode)

        return result
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let char = keyCodeToCharacter(keyCode) {
                return char.uppercased()
            }
            return "?"
        }
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

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
