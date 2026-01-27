import Cocoa
import ServiceManagement

extension Notification.Name {
    static let pinnedSitesChanged = Notification.Name("pinnedSitesChanged")
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
            NotificationCenter.default.post(name: .pinnedSitesChanged, object: nil)
        }
    }

    private let sitesKey = "pinnedSites"

    private init() {
        loadSites()
        syncLaunchAtLoginStatus()

        if pinnedSites.isEmpty {
            pinnedSites = [
                PinnedSite(
                    name: "Claude",
                    url: "https://claude.ai",
                    shortcut: "⌥⌥⌥",
                    shortcutKeys: ShortcutKeys(modifiers: 0, keyCode: 0, isTripleTap: true, tapModifier: "option"),
                    useMobileUserAgent: false
                )
            ]
        }
    }

    func syncLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func loadSites() {
        guard let data = UserDefaults.standard.data(forKey: sitesKey),
              let sites = try? JSONDecoder().decode([PinnedSite].self, from: data) else {
            return
        }
        pinnedSites = sites
    }

    private func saveSites() {
        guard let data = try? JSONEncoder().encode(pinnedSites) else { return }
        UserDefaults.standard.set(data, forKey: sitesKey)
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
            pinnedSites[index].windowWidth = size.width
            pinnedSites[index].windowHeight = size.height
        }
    }
}
