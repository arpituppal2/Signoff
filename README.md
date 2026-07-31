# Signoff

**macOS menu-bar app · AI-generated email signoffs · 100% private · instant · free and open source.**

Signoff lives in your menu bar. Press `⌃⌘1` and a signoff is generated and copied to clipboard — ready to paste. No app switching. No friction. Zero cloud egress. No account. No subscription. No limits.

Built with Apple Foundation Models on macOS 26+. All generation stays on your device.

---

## Features

- **6 buckets**: Standard, Professional, Unhinged, Custom, My List, Footer — each with its own tone and shortcut
- **Global keyboard shortcuts**: `⌃⌘1–6` to generate from any bucket, from any app
- **Cache-first**: Phrases are pre-cached per bucket — time-to-signoff under 1ms on cache hit
- **Privacy-first**: All generation runs on-device via Apple Foundation Models. No data ever leaves your Mac
- **Completely free** — unlimited generations, no tiers, no accounts, no subscriptions
- **Context-aware generation**: Signoff reads the message you're replying to via Accessibility and tailors the signoff to match — 100% on your Mac
- **Generated, never hardcoded**: Every signoff is produced by an on-device model at request time — nothing is pre-written or read from a static list
- **macOS Shortcuts.app support**: Exposes "Generate Signoff" and "Copy Last Signoff" as AppIntents
- **Accessibility-first**: Full VoiceOver support, keyboard navigation, Reduce Motion respect
- **Sparkle auto-updates**: Signed appcasts, EdDSA-verified delta updates

---

## Requirements

- **macOS 26.0+** (Tahoe or later)
- **Apple Silicon** (M1+) or Intel with Apple Intelligence enabled
- **Apple Intelligence** must be enabled in System Settings → Apple Intelligence & Siri

---

## Installation

### From Release (recommended)

1. Download the latest `Signoff.dmg` from the [Releases](https://github.com/arpituppal2/Signoff/releases) page
2. Drag `Signoff.app` to your Applications folder
3. Launch Signoff — it appears in the menu bar as a ✍️ icon
4. Complete the onboarding tour (permissions, shortcut setup)

### From Source

```bash
git clone https://github.com/arpituppal2/Signoff.git
cd Signoff
swift run
```

---

## ⚠️ macOS Gatekeeper: "App cannot be opened because the developer cannot be verified"

Because Signoff is open source and not notarized by Apple (no paid Developer ID), macOS will block it on first launch. **This is expected.**

**To open anyway:**

1. Right-click (or Control-click) `Signoff.app` in Applications
2. Choose **Open** from the context menu
3. Click **Open** in the dialog that appears
4. Signoff will now launch normally; this only needs to be done once

> Alternatively: `xattr -d com.apple.quarantine /Applications/Signoff.app` in Terminal.

---

## Getting Started

1. **Open the popover**: Click the ✍️ menu bar icon, or press `⌃⌘\`` (backtick)
2. **Select a bucket**: Click any bucket in the list (Standard, Professional, Unhinged, etc.)
3. **Generate**: Click the "Generate" button, or press `⌃⌘1–6` from anywhere
4. **Paste**: The signoff is copied to clipboard — press `⌘V` wherever you need it
5. **Copy last**: Press `⌃⇧C` or click "Copy last" to recopy the most recent signoff

### Default Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌃⌘1` | Generate from Professional bucket |
| `⌃⌘2` | Generate from Standard bucket |
| `⌃⌘3` | Generate from Unhinged bucket |
| `⌃⌘4` | Generate from Custom bucket |
| `⌃⌘5` | Generate from My List bucket |
| `⌃⌘6` | Generate from Footer bucket |
| `⌃⌘\`` | Open popover |
| `⌃⇧C` | Copy last signoff |
| `⌃⌘,` | Open Settings |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  SignoffApp (executable)                                │
│  • NSStatusBar + NSPopover                              │
│  • Sparkle auto-updates                                 │
│  • Global keyboard shortcuts (Carbon Event Tap)         │
├─────────────────────────────────────────────────────────┤
│  SignoffUI (SwiftUI views)                              │
│  • PopoverContentView — main menu-bar surface           │
│  • Brand — design tokens (spacing, typography, color)   │
│  • Onboarding — 4-step first-run tour                   │
│  • Settings — full preference panes                     │
├─────────────────────────────────────────────────────────┤
│  SignoffCore (business logic)                           │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Generation Pipeline                            │    │
│  │  BucketCache → FoundationModelsProvider         │    │
│  │          ↗ ↖                                     │    │
│  │  PostProcessor  PromptComposer                  │    │
│  │  PromptComposer → PromptTemplate (JSON)         │    │
│  ├─────────────────────────────────────────────────┤    │
│  │  Shortcuts · PasteAutomation · CarbonEventTap   │    │
│  │  Persistence (SwiftData) · AppIntents           │    │
│  │  UsageTracker (counter only)                    │    │
│  │  ContextHarvester (AX API)                      │    │
│  │  VoiceProfile (discriminative learning)         │    │
│  └─────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────┤
│  Resources                                              │
│  • Prompts/ — 6 JSON prompt templates per bucket        │
│  • PrivacyInfo.xcprivacy — Apple privacy manifest       │
└─────────────────────────────────────────────────────────┘
```

### Key Design Decisions

- **Cache-first generation**: Each bucket pre-caches up to 5 phrases at startup. `pop()` returns in <1ms. Cache miss falls through to FMF (~100ms with prewarmed sessions).
- **On-device only**: All generation uses Apple Foundation Models. No API keys, no cloud servers, no data egress.
- **Privacy > transparency**: The UI says "Private AI" — not "Foundation Models" or "on-device." Users shouldn't need to know the tech to trust the privacy.
- **Zero-config onboarding**: Launch → grant permissions → done. No accounts, no setup.
- **Free and unlimited**: No tiers, no quotas, no subscriptions. The original paid tier code has been entirely removed.

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Swift 6 |
| Framework | SwiftUI, AppKit |
| AI | Apple FoundationModels (LanguageModelSession, @Generable) |
| Architecture | Swift Package Manager (3 targets) |
| Persistence | SwiftData (SQLite) |
| Shortcuts | Carbon Event Tap (CGEvent.tapCreate) |
| Updates | Sparkle 2 (EdDSA-signed) |
| Minimum OS | macOS 26.0 |
| License | MIT |

---

## Project Structure

```
Sources/
├── SignoffApp/           # Executable target
│   ├── SignoffApp.swift  # @main, menu bar, status item
│   ├── AboutWindow.swift
│   └── AppActivation.swift
├── SignoffUI/            # UI framework target
│   ├── Popover/          # Main popover surface
│   ├── Components/       # Brand tokens, cards, badges
│   ├── Onboarding/       # First-run tour
│   ├── Windows/          # Help overlay, shortcut recorder
│   └── SettingsView.swift
└── SignoffCore/          # Core logic target
    ├── Generation/       # on-device model, cache, prompts
    ├── Shortcuts/        # Carbon event tap, paste automation
    ├── Models/           # Bucket, Profile, UsageTracker, etc.
    ├── Intents/          # macOS Shortcuts.app integration
    └── Persistence/      # SwiftData, migrations
Tests/
├── SignoffCoreTests/     # 105+ unit tests
└── SignoffUITests/       # Brand token validation
```

---

## Contributing

Contributions welcome. Please open an issue first to discuss what you'd like to change.

```bash
# Setup
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