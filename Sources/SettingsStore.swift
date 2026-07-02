import Cocoa
import ServiceManagement

extension Notification.Name {
    static let pinnedSitesChanged = Notification.Name("pinnedSitesChanged")
    static let bubbleSettingsChanged = Notification.Name("bubbleSettingsChanged")
}

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var launchAtLogin: Bool = false {
        didSet {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    @Published var pinnedSites: [PinnedSite] = [] {
        didSet {
            saveSites()
            if !suppressChangeNotification {
                NotificationCenter.default.post(name: .pinnedSitesChanged, object: nil)
            }
        }
    }

    private var suppressChangeNotification = false

    @Published var preferredBubbleEdge: BubbleEdge = .right {
        didSet {
            UserDefaults.standard.set(preferredBubbleEdge.rawValue, forKey: bubbleEdgeKey)
            NotificationCenter.default.post(name: .bubbleSettingsChanged, object: nil)
        }
    }

    @Published var showBubblePreviews: Bool = false {
        didSet {
            UserDefaults.standard.set(showBubblePreviews, forKey: bubblePreviewsKey)
            NotificationCenter.default.post(name: .bubbleSettingsChanged, object: nil)
        }
    }

    private let sitesKey = "pinnedSites"
    private let bubbleEdgeKey = "preferredBubbleEdge"
    private let bubblePreviewsKey = "showBubblePreviews"

    private init() {
        loadSites()
        loadBubbleEdge()
        loadBubblePreviews()
        syncLaunchAtLoginStatus()

        if pinnedSites.isEmpty {
            pinnedSites = [
                PinnedSite(
                    name: "Claude",
                    url: "https://claude.ai",
                    shortcut: "⌥⌥⌥",
                    shortcutKeys: ShortcutKeys(modifiers: 0, keyCode: 0, isTripleTap: true, tapModifier: "option"),
                    useMobileUserAgent: false,
                    displayMode: .menuBar
                ),
                PinnedSite(
                    name: "ChatGPT",
                    url: "https://chatgpt.com",
                    shortcut: "⌘⌘⌘",
                    shortcutKeys: ShortcutKeys(modifiers: 0, keyCode: 0, isTripleTap: true, tapModifier: "command"),
                    useMobileUserAgent: false,
                    displayMode: .bubble
                )
            ]
        }
    }

    func syncLaunchAtLoginStatus() {
        let enabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != enabled {
            launchAtLogin = enabled
        }
    }

    private func loadSites() {
        // ponytail: falls back to the pre-rename com.pinster.app domain once;
        // the didSet save then persists sites under the new bundle id
        let data = UserDefaults.standard.data(forKey: sitesKey)
            ?? UserDefaults(suiteName: "com.pinster.app")?.data(forKey: sitesKey)
        guard let data,
              let sites = try? JSONDecoder().decode([PinnedSite].self, from: data) else {
            return
        }
        pinnedSites = sites
    }

    private func saveSites() {
        guard let data = try? JSONEncoder().encode(pinnedSites) else { return }
        UserDefaults.standard.set(data, forKey: sitesKey)
    }

    private func loadBubbleEdge() {
        if let edgeString = UserDefaults.standard.string(forKey: bubbleEdgeKey),
           let edge = BubbleEdge(rawValue: edgeString) {
            preferredBubbleEdge = edge
        }
    }

    private func loadBubblePreviews() {
        if UserDefaults.standard.object(forKey: bubblePreviewsKey) != nil {
            showBubblePreviews = UserDefaults.standard.bool(forKey: bubblePreviewsKey)
        }
    }

    func updateBubblePosition(id: UUID, position: CGFloat) {
        if let index = pinnedSites.firstIndex(where: { $0.id == id }) {
            withoutChangeNotification {
                pinnedSites[index].bubblePosition = position
            }
        }
    }

    func addSite(_ site: PinnedSite) {
        pinnedSites.append(site)
    }

    func removeSite(id: UUID) {
        pinnedSites.removeAll { $0.id == id }
    }

    func updateSite(_ site: PinnedSite) {
        if let index = pinnedSites.firstIndex(where: { $0.id == site.id }) {
            pinnedSites[index] = site
        }
    }

    func updateSiteSize(id: UUID, size: NSSize) {
        if let index = pinnedSites.firstIndex(where: { $0.id == id }) {
            withoutChangeNotification {
                pinnedSites[index].windowWidth = size.width
                pinnedSites[index].windowHeight = size.height
            }
        }
    }

    // Geometry updates fire on every mouse tick during drags and resizes;
    // posting pinnedSitesChanged for them would rebuild menus, re-register
    // hotkeys, and reposition bubbles mid-gesture.
    private func withoutChangeNotification(_ mutate: () -> Void) {
        suppressChangeNotification = true
        mutate()
        suppressChangeNotification = false
    }
}
