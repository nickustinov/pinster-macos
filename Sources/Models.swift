import Cocoa

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
let githubURL = "https://github.com/nickustinov/pinster-macos"

struct PinnedSite: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var shortcut: String
    var shortcutKeys: ShortcutKeys?
    var useMobileUserAgent: Bool
    var windowWidth: Double?
    var windowHeight: Double?
    var displayMode: DisplayMode
    var bubblePosition: CGFloat?

    init(id: UUID = UUID(), name: String, url: String, shortcut: String = "", shortcutKeys: ShortcutKeys? = nil, useMobileUserAgent: Bool = false, windowWidth: Double? = nil, windowHeight: Double? = nil, displayMode: DisplayMode = .menuBar, bubblePosition: CGFloat? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.shortcut = shortcut
        self.shortcutKeys = shortcutKeys
        self.useMobileUserAgent = useMobileUserAgent
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.displayMode = displayMode
        self.bubblePosition = bubblePosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        shortcut = try container.decode(String.self, forKey: .shortcut)
        shortcutKeys = try container.decodeIfPresent(ShortcutKeys.self, forKey: .shortcutKeys)
        useMobileUserAgent = try container.decode(Bool.self, forKey: .useMobileUserAgent)
        windowWidth = try container.decodeIfPresent(Double.self, forKey: .windowWidth)
        windowHeight = try container.decodeIfPresent(Double.self, forKey: .windowHeight)
        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? .menuBar
        bubblePosition = try container.decodeIfPresent(CGFloat.self, forKey: .bubblePosition)
    }

    var userAgent: String {
        if useMobileUserAgent {
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        }
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    var windowSize: NSSize {
        NSSize(width: windowWidth ?? 420, height: windowHeight ?? 650)
    }
}

struct ShortcutKeys: Codable, Equatable {
    var modifiers: UInt
    var keyCode: UInt16
    var isTripleTap: Bool
    var tapModifier: String?
}

enum DisplayMode: String, Codable, CaseIterable {
    case menuBar
    case bubble
}

enum BubbleEdge: String, Codable, CaseIterable {
    case right
    case bottom
}

