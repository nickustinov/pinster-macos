# Itsyweb

A lightweight macOS menu bar application for quick access to pinned websites.

## What it does

Itsyweb lives in your menu bar and lets you open frequently used websites in floating popover windows. No need to switch to a browser — just click the menu bar icon or use a keyboard shortcut.

Features:
- **Menu bar integration** — Always accessible from the status bar
- **Pinned sites** — Save your favorite websites for quick access
- **Global hotkeys** — Open sites with keyboard shortcuts (no Accessibility permission required)
- **Triple-tap shortcuts** — Press a modifier key three times rapidly (e.g., ⌥⌥⌥)
- **Resizable popovers** — Drag the corner to resize the window
- **Mobile view** — Render sites with a mobile user agent for compact layouts
- **Launch at login** — Start automatically when you log in

## Requirements

- macOS 13 or later
- Swift 5.9 or later (for building)

## Building

```bash
# Build release binary
swift build --configuration release

# The binary will be at .build/release/itsyweb
```

To create an app bundle, you can wrap the binary in a standard macOS `.app` structure with the included `Info.plist`.

## Usage

1. Run the app — it appears as a ✳ icon in your menu bar
2. Click the icon to see your pinned sites
3. Click a site to open it in a popover window
4. Use ⌘, to open settings and manage your sites

### Default shortcut

By default, Claude.ai is pinned with a triple-tap Option (⌥⌥⌥) shortcut.

### Adding sites

1. Open Settings (⌘,)
2. Click the + button
3. Enter the site name and URL
4. Optionally record a keyboard shortcut
5. Click Save

## Architecture

```
Sources/
├── main.swift              # App entry point
├── AppDelegate.swift       # Status bar, menu, popover management
├── Models.swift            # PinnedSite and ShortcutKeys data models
├── SettingsStore.swift     # UserDefaults persistence
├── SettingsView.swift      # SwiftUI settings interface
├── WebViewController.swift # WKWebView with resize handle
└── HotkeyManager.swift     # Global hotkey registration (Carbon Events)
```

## Dependencies

None — uses only standard macOS frameworks:
- Cocoa
- SwiftUI
- WebKit
- Carbon.HIToolbox
- ServiceManagement

## License

MIT License

Copyright (c) 2026 Nick Ustinov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
