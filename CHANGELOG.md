# Changelog

## 2.0.0 – 2026-07-02

Pinster is now **Itsypin** – new name, new bundle id (`com.itsypin.app`), same app. Settings from previous Pinster installs migrate automatically.

### New

- Pages keep their state between opens – one webview per menu bar site instead of a shared one
- Native file uploads (`<input type="file">` opens the system file picker)
- Native `alert()`, `confirm()`, and `prompt()` dialogs
- Hot corner reveal for floating bubbles – hide a bubble entirely and open it by moving the cursor into a screen corner
- Auto-unload collapsed bubble pages after configurable inactivity (never/5/10/30 minutes)
- Bubble size slider (40–100 px)
- Optional bubble background – icon-only by default, with the icon flush to the screen edge and rounded corners
- Per-site custom icons, used in both bubbles and the menu bar
- Mobile/desktop user agent toggle in the bubble title bar
- Right-click context menu: back/forward, open link in browser, open page in browser
- App Store build support – sandboxed entitlements and a separate `itsypin-appstore` scheme

### Fixed

- Bubble favicons: the page's real favicon replaces the guessed one after first expand, and a letter badge appears when no favicon can be fetched, so bubbles are never blank
- Switching between two pinned sites on the same host now loads the right page
- Editing a site's URL or user agent applies immediately instead of requiring a relaunch
- Sign-in popups activate the app so password managers can offer autofill
- Sign-in popups close automatically when returning to any site's domain (was hardcoded to Claude)
- Resizing or dragging no longer rebuilds menus, hotkeys, and bubbles on every mouse tick
- App Transport Security exception narrowed to web content only

### Changed

- Default site is Claude in the menu bar on triple-tap Command (⌘⌘⌘); the ChatGPT bubble default is gone
- Version 2.0.0, build 20001
- Project generated with XcodeGen from `project.yml`; Swift Package Manager setup removed
- Removed private API usage (`_setPreventsActivation:`)
- App icon moved into an asset catalog

## 1.2.2 and earlier

See the [release history](https://github.com/nickustinov/itsypin-macos/releases) from the Pinster era.
