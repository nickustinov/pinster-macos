# Itsypin

[![Downloads](https://img.shields.io/github/downloads/nickustinov/itsypin-macos/total.svg)](https://github.com/nickustinov/itsypin-macos/releases)
[![Release](https://img.shields.io/github/v/release/nickustinov/itsypin-macos)](https://github.com/nickustinov/itsypin-macos/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift 5.9](https://img.shields.io/badge/swift-5.9-orange.svg)](https://swift.org)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-brightgreen.svg)](https://www.apple.com/macos/)

A lightweight macOS menu bar application for quick access to pinned websites.

![Itsypin demo](Assets/demo-v3.gif)

## Download

Download the latest release from [Releases](https://github.com/nickustinov/itsypin-macos/releases).

## What it does

Itsypin lives in your menu bar and lets you open frequently used websites in floating popover windows or as floating bubbles on the screen edge. No need to switch to a browser — just click the menu bar icon, hover over a bubble, or use a keyboard shortcut.

Features:
- **Menu bar integration** — Access sites from the status bar dropdown
- **Floating bubbles** — Pin sites as always-visible bubbles on screen edge (right or bottom)
- **Hover to expand** — Bubbles expand to full window on hover, collapse when you move away
- **Option-drag** — Reposition expanded floating windows by holding Option and dragging
- **Favicon or preview** — Bubbles show site favicon or page preview (configurable)
- **Global hotkeys** — Open sites with keyboard shortcuts (no Accessibility permission required)
- **Triple-tap shortcuts** — Press a modifier key three times rapidly (e.g., ⌥⌥⌥)
- **Resizable windows** — Drag any corner to resize
- **Favicon in menu bar** — Shows site favicon while popover is open
- **Mobile view** — Render sites with a mobile user agent, switchable from the bubble title bar
- **Pages stay loaded** — Sites keep their state between opens; optional auto-unload for collapsed bubbles
- **Hot corners** — Hide a bubble entirely and reveal it by moving the cursor into a screen corner
- **Custom icons** — Replace the fetched favicon with your own image per site
- **File uploads and dialogs** — Native file picker, alert/confirm/prompt support
- **Open in browser** — Right-click any link or page to open it in your default browser
- **Launch at login** — Start automatically when you log in

## Requirements

- macOS 13 or later

## Installation

### Homebrew

```bash
brew tap nickustinov/tap
brew install --cask itsypin
```

### Manual

1. Download `Itsypin-x.x.x.dmg` from Releases
2. Open the DMG and drag Itsypin to Applications
3. Launch from Applications — it appears as an icon in your menu bar

## Usage

1. Click the menu bar icon to see your pinned sites
2. Click a site to open it in a popover window
3. Click Settings to manage your sites

### Default sites

- **Claude** — menu bar, triple-tap Command (⌘⌘⌘)

### Adding sites

1. Open Settings
2. Click the + button in the Pinned sites header
3. Enter the site name and URL
4. Optionally record a keyboard shortcut
5. Click Save

## Building from source

Requirements: Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
# Generate the Xcode project
xcodegen generate

# Build, sign, and package the DMG
./scripts/build-release.sh

# Output: dist/Itsypin.app and dist/Itsypin-x.x.x.dmg
```

For development, open `itsypin.xcodeproj` and run the `itsypin` scheme.

### App Store build

The `itsypin-appstore` scheme uses the `Release-AppStore` configuration with
sandboxed entitlements (`Sources/itsypin.entitlements`). Select it in Xcode,
then Product > Archive and upload via the Organizer.

## Architecture

The Xcode project is generated from `project.yml` with XcodeGen. Direct
(DMG) builds use `Sources/itsypin-direct.entitlements`; App Store builds
use the sandboxed `Sources/itsypin.entitlements`.

```
project.yml                 # XcodeGen project definition (single version source)
Assets/                     # App icon asset catalog and menu bar icon
Sources/
├── main.swift              # App entry point
├── AppDelegate.swift       # Status bar, menu, popover management
├── Models.swift            # PinnedSite and ShortcutKeys data models
├── SettingsStore.swift     # UserDefaults persistence
├── SettingsView.swift      # SwiftUI settings interface
├── WebViewController.swift # WKWebView with resize handle
├── FaviconLoader.swift     # Shared favicon download with fallbacks
├── HotkeyManager.swift     # Global hotkey registration (Carbon Events)
├── BubbleWindow.swift      # Floating bubble window
├── BubbleContentView.swift # Bubble content (favicon/preview)
└── BubbleManager.swift     # Manages all floating bubbles
```

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
