# Signoff

**macOS menu-bar app · AI-generated email signoffs · 100% private · free and open source.**

Signoff lives in your menu bar. Press `⌃⌘1` and a signoff is generated on your Mac and copied to your clipboard — ready to paste. No app switching, no friction, zero cloud egress, no account, no subscription, no limits.

Built with Apple Foundation Models on macOS 26+. Every signoff is drafted by the on-device model at request time — nothing is hardcoded, nothing ever leaves your Mac.

---

## Features

- **3 voices**: Normal, Professional, and Cynical — each with its own tone and shortcut
- **After signoff**: Set a line in Settings that always appears below your paste — pronouns, a phone number, or a tagline
- **Global keyboard shortcuts**: `⌃⌥1–3` generate from any voice, from any app; `⌃⌥\`` opens the menu bar
- **On-device only**: All generation runs via Apple Foundation Models. No API keys, no servers, no data egress
- **Generated, never hardcoded**: Every signoff is produced by the on-device model at request time — nothing is read from a static phrasebook
- **macOS Shortcuts.app**: "Generate Signoff" and "Copy Last Signoff" are exposed as AppIntents
- **Accessibility-first**: Full VoiceOver support, keyboard navigation, Reduce Motion respect throughout
- **Auto-updates**: Checks a lightweight JSON appcast feed daily for new versions (feed URL configured at build time)
- **Completely free** — unlimited generations, no tiers, no accounts, no subscriptions

---

## Requirements

- **macOS 26.0+** (Tahoe or later)
- **Apple Silicon** (M1+) with **Apple Intelligence** enabled in System Settings → Apple Intelligence & Siri

---

## Installation

### From Homebrew (recommended)

```bash
brew install --cask arpituppal2/tap/signoff
```

> The Homebrew cask installs the unsigned release DMG without setting macOS's
> quarantine flag, so Signoff launches without the "damaged" warning.

### From Release

1. Download the latest `Signoff.dmg` from the [Releases](https://github.com/arpituppal2/Signoff/releases) page
2. Drag `Signoff.app` to your Applications folder
3. Launch Signoff — it appears in the menu bar as a ✍️ icon
4. Grant Accessibility and Input Monitoring (prompted in the menu, or System Settings → Privacy & Security)

### From Source

```bash
git clone https://github.com/arpituppal2/Signoff.git
cd Signoff
swift run
```

---

## ⚠️ macOS Gatekeeper: "App is damaged and should be ejected"

Signoff is open source and not notarized by Apple (no paid Developer ID), so a
manually downloaded release is blocked by Gatekeeper on first launch. **This is expected.**

**To open a manually downloaded copy:**

1. Right-click (or Control-click) `Signoff.app` in Applications
2. Choose **Open** from the context menu
3. Click **Open** in the dialog that appears
4. Signoff will now launch normally; this only needs to be done once

> Alternatively: `xattr -dr com.apple.quarantine /Applications/Signoff.app` in Terminal.

> Installing via Homebrew (`brew install --cask arpituppal2/tap/signoff`) avoids this entirely.

---

## Getting Started

1. **Open the menu**: Click the ✍️ menu-bar icon (or press `⌃⌥\`` from anywhere)
2. **Select a voice**: Pick one of the three voices — Normal, Professional, or Cynical
3. **Generate**: Click **Generate**, or press `⌃⌥1–3` from anywhere
4. **Paste**: The signoff lands at your cursor (or is copied — press `⌘V`)
5. **Copy last**: Press `⌃⇧C` or use "Copy Last" to recopy the most recent signoff

### Default Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌃⌥\`` | Open the menu bar |
| `⌃⌥1` | Generate from Normal |
| `⌃⌥2` | Generate from Professional |
| `⌃⌥3` | Generate from Cynical |
| `⌃⇧C` | Copy last signoff |
| `⌃⌘,` | Open Settings |

> Customize shortcuts in **Settings → Shortcuts**, or switch the whole set to `⌥⌘1–3` if `⌃⌥` clashes with another app.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  SignoffApp (executable)                                │
│  • MenuBarExtra (.window) + app commands                │
│  • Global keyboard shortcuts (Carbon Event Tap)         │
│  • UpdateChecker (JSON appcast feed)                     │
├─────────────────────────────────────────────────────────┤
│  SignoffUI (SwiftUI)                                    │
│  • SignoffMenuContent — main menu-bar surface           │
│  • Brand — design tokens (Ink-on-Paper, typography)     │
│  • Settings — full preference panes                     │
├─────────────────────────────────────────────────────────┤
│  SignoffCore (business logic)                           │
│  Generation: BucketCache → FoundationModelsProvider     │
│              ← PromptComposer → PromptTemplate (JSON)   │
│              → PostProcessor                             │
│  Shortcuts · PasteAutomation · CarbonEventTap           │
│  Persistence (SwiftData) · AppIntents                   │
│  UsageTracker (counter)                                 │
└─────────────────────────────────────────────────────────┘
```

### Key Design Decisions

- **On-device only**: All generation uses Apple Foundation Models. No API keys, no cloud servers, no data egress. If the on-device model isn't ready, generation fails honestly rather than serving something pre-written.
- **Generated, never hardcoded**: There is no static phrasebook. Every signoff is produced by the model at request time.
- **Cache-first**: Each bucket pre-caches a small set of phrases at startup; cache hits return in under a millisecond, misses fall through to a live model call on a prewarmed session.
- **Rich popover, not a plain menu**: Per Apple HIG, the menu-bar surface is a `MenuBarExtra` in `.window` style — it hosts the rich popover content (scroll view, toast overlay, custom buttons, cards) that an `NSMenu` (`.menu` style) silently strips.
- **Privacy > transparency**: The UI says "100% private" — users shouldn't need to know the underlying tech to trust it.

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Swift 6 (Strict Concurrency) |
| UI | SwiftUI, AppKit |
| AI | Apple Foundation Models (LanguageModelSession, @Generable) |
| Architecture | Swift Package Manager (3 targets) |
| Persistence | SwiftData (SQLite) |
| Shortcuts | Carbon Event Tap (CGEvent.tapCreate) |
| Updates | UpdateChecker (JSON appcast feed) |
| Minimum OS | macOS 26.0 |
| License | MIT |

---

## Project Structure

```
Sources/
├── SignoffApp/           # Executable target — @main, MenuBarExtra, carbon shortcuts
├── SignoffUI/            # UI framework
│   ├── Popover/          # Menu-bar surfaces (SignoffMenuContent, PopoverContentView)
│   ├── Components/       # Brand tokens, cards, badges
│   ├── Windows/          # Help overlay, shortcut recorder
│   └── SettingsView.swift
└── SignoffCore/          # Business logic
    ├── Generation/       # on-device model, cache, prompts
    ├── Shortcuts/        # Carbon event tap, paste automation, permissions
    ├── Models/           # Bucket, AppSettings, UsageTracker, etc.
    ├── Intents/          # macOS Shortcuts.app integration
    └── Persistence/      # SwiftData, migrations
Tests/
├── SignoffCoreTests/     # unit tests
└── SignoffUITests/       # brand-token validation
```

---

## Contributing

Contributions welcome. Please open an issue first to discuss what you'd like to change.

```bash
git clone https://github.com/arpituppal2/Signoff.git
cd Signoff
swift build
swift test
```

---

## License

MIT. See [LICENSE](LICENSE).

---

*Built with Swift 6, Apple Foundation Models, and way too much coffee.*
