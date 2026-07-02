import Cocoa

class BubbleManager {
    static let shared = BubbleManager()

    private var bubbleWindows: [UUID: BubbleWindow] = [:]
    private weak var expandedBubble: BubbleWindow?
    private var hotCornerGlobalMonitor: Any?
    private var hotCornerLocalMonitor: Any?

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
                existingWindow.updateSite(site)
                let position = site.bubblePosition ?? nextPosition
                existingWindow.positionOnEdge(edge: edge, position: position)
                if site.hotCorner == nil {
                    existingWindow.orderFront(nil)
                } else if !existingWindow.isExpanded {
                    existingWindow.orderOut(nil)
                }
            } else {
                // Create new bubble; hot corner bubbles stay hidden until triggered
                let position = site.bubblePosition ?? nextPosition
                let bubble = BubbleWindow(site: site)
                bubble.positionOnEdge(edge: edge, position: position)
                if site.hotCorner == nil {
                    bubble.orderFront(nil)
                }
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

        updateHotCornerMonitor()
    }

    // MARK: - Hot Corners

    private func updateHotCornerMonitor() {
        if let monitor = hotCornerGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            hotCornerGlobalMonitor = nil
        }
        if let monitor = hotCornerLocalMonitor {
            NSEvent.removeMonitor(monitor)
            hotCornerLocalMonitor = nil
        }

        guard bubbleWindows.values.contains(where: { $0.site.hotCorner != nil }) else { return }

        hotCornerGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.checkHotCorners()
        }
        hotCornerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.checkHotCorners()
            return event
        }
    }

    private func checkHotCorners() {
        // ponytail: main screen only; per-screen corners if anyone asks
        guard let screen = NSScreen.main else { return }

        let location = NSEvent.mouseLocation
        let zoneSize: CGFloat = 8

        for window in bubbleWindows.values {
            guard let corner = window.site.hotCorner, !window.isExpanded else { continue }

            let frame = screen.frame
            let x = corner == .bottomLeft ? frame.minX : frame.maxX - zoneSize
            let zone = NSRect(x: x, y: frame.minY, width: zoneSize, height: zoneSize)

            if zone.contains(location) {
                window.expandFromHotCorner()
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
    }
}
