import Cocoa

class BubbleManager {
    static let shared = BubbleManager()

    private var bubbleWindows: [UUID: BubbleWindow] = [:]
    private weak var expandedBubble: BubbleWindow?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pinnedSitesChanged),
            name: .pinnedSitesChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bubbleSettingsChanged),
            name: .bubbleSettingsChanged,
            object: nil
        )
    }

    @objc private func pinnedSitesChanged() {
        showBubblesForSites()
    }

    @objc private func bubbleSettingsChanged() {
        repositionAllBubbles()
        refreshAllBubbleContent()
    }

    private func refreshAllBubbleContent() {
        for (_, window) in bubbleWindows {
            window.refreshCollapsedContent()
        }
    }

    func showBubblesForSites() {
        let sites = SettingsStore.shared.pinnedSites
        let bubbleSites = sites.filter { $0.displayMode == .bubble }

        // Remove bubbles for sites that no longer exist or changed to menuBar mode
        let bubbleSiteIds = Set(bubbleSites.map { $0.id })
        let idsToRemove = bubbleWindows.keys.filter { !bubbleSiteIds.contains($0) }
        for id in idsToRemove {
            if let window = bubbleWindows.removeValue(forKey: id) {
                if expandedBubble === window {
                    expandedBubble = nil
                }
                window.prepareForRemoval()
                window.orderOut(nil)
            }
        }

        // Create or update bubbles for bubble-mode sites
        let edge = SettingsStore.shared.preferredBubbleEdge
        var nextPosition: CGFloat = 0.1

        for site in bubbleSites {
            if let existingWindow = bubbleWindows[site.id] {
                // Update position if needed
                let position = site.bubblePosition ?? nextPosition
                existingWindow.positionOnEdge(edge: edge, position: position)
            } else {
                // Create new bubble
                let position = site.bubblePosition ?? nextPosition
                let bubble = BubbleWindow(site: site)
                bubble.positionOnEdge(edge: edge, position: position)
                bubble.orderFront(nil)
                bubbleWindows[site.id] = bubble

                // Save auto-assigned position if not set
                if site.bubblePosition == nil {
                    SettingsStore.shared.updateBubblePosition(id: site.id, position: position)
                }
            }

            nextPosition += 0.15
            if nextPosition > 0.9 {
                nextPosition = 0.1
            }
        }
    }

    private func repositionAllBubbles() {
        let edge = SettingsStore.shared.preferredBubbleEdge

        for (id, window) in bubbleWindows {
            if let site = SettingsStore.shared.pinnedSites.first(where: { $0.id == id }) {
                let position = site.bubblePosition ?? 0.5
                window.positionOnEdge(edge: edge, position: position)
            }
        }
    }

    func willExpandBubble(_ bubble: BubbleWindow) {
        // Collapse currently expanded bubble first
        if let expanded = expandedBubble, expanded !== bubble {
            expanded.collapse()
        }
        expandedBubble = bubble
        setActivationPolicyForBubble(expanded: true)
    }

    func expandBubble(for siteId: UUID) {
        bubbleWindows[siteId]?.expand()
    }

    func collapseBubble(for siteId: UUID) {
        bubbleWindows[siteId]?.collapse()
    }

    func toggleBubble(for siteId: UUID) {
        guard let bubble = bubbleWindows[siteId] else { return }

        if bubble.isExpanded {
            bubble.collapse()
        } else {
            bubble.expand()
        }
    }

    func isBubbleExpanded(for siteId: UUID) -> Bool {
        return bubbleWindows[siteId]?.isExpanded ?? false
    }

    func bubbleDidCollapse(_ bubble: BubbleWindow) {
        if expandedBubble === bubble {
            expandedBubble = nil
        }
        setActivationPolicyForBubble(expanded: false)
    }

    private func setActivationPolicyForBubble(expanded: Bool) {
        if expanded {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                setAppIcon()
            }
            return
        }

        // Keep regular policy if any visible titled window is open (e.g., Settings)
        let hasVisibleTitledWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled)
        }
        guard !hasVisibleTitledWindow else { return }

        if NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func setAppIcon() {
        // Prefer bundled icon (release builds)
        if let bundlePath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: bundlePath) {
            NSApp.applicationIconImage = image
            return
        }

        // Fallback: load from Assets folder (for development)
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
}
