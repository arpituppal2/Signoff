# Signoff.

**macOS menu-bar app · AI-generated email signoffs · 100% private · instant.**

Signoff lives in your menu bar. Press `⌃⌘1` and a signoff is generated and copied to your clipboard — ready to paste. No app switching. No friction. Zero cloud egress.

Built with Apple Foundation Models on macOS 26+. All generation stays on your device.

---

## Features

- **6 buckets**: Standard, Professional, Unhinged, Custom, My List, Footer — each with its own tone and shortcuts
- **Global keyboard shortcuts**: `⌃⌘1–6` to generate from any bucket, from any app
- **Cache-first**: Phrases are pre-cached per bucket — time-to-signoff under 1ms on cache hit
- **Privacy-first**: All generation runs on-device via Apple Foundation Models. No data ever leaves your Mac
- **100 free signoffs** (no account needed) — unlimited with Signoff Pro ($1/mo, $10/yr, or $30/lifetime)
- **Context-aware generation** (paid tier): Signoff reads the message you're replying to via Accessibility and tailors the signoff to match
- **Smart phrase pool**: 180+ curated signoffs across all buckets, loaded from JSON — nothing hardcoded
- **macOS Shortcuts.app support**: Exposes "Generate Signoff" and "Copy Last Signoff" as AppIntents
- **Accessibility-first**: Full VoiceOver support, keyboard navigation, Reduce Motion respect
- **Sparkle auto-updates**: Signed appcasts, EdDSA-verified delta updates

---

## Requirements

- **macOS 26.0+** (Sequoia or later)
- **Apple Silicon** (M1+) or Intel with Apple Intelligence enabled
- **Apple Intelligence** must be enabled in System Settings → Apple Intelligence & Siri

---

## Installation

### From Release
1. Download the latest `Signoff.dmg` from the [Releases](https://github.com/arpituppal/signoff/releases) page
2. Drag `Signoff.app` to your Applications folder
3. Launch Signoff — it appears in the menu bar as a ✍️ icon
4. Complete the onboarding tour (permissions, shortcut setup)

### From Source
```bash
git clone https://github.com/arpituppal/signoff.git
cd signoff
swift run
```

---

## Getting Started

1. **Open the popover**: Click the ✍️ menu bar icon, or press `⌃⌘\`` (backtick)
2. **Select a bucket**: Click any bucket in the list (Standard, Professional, Unhinged, etc.)
3. **Generate**: Click the "Generate" button, or press `⌃⌘1–6` from anywhere
4. **Paste**: The signoff is copied to your clipboard — press `⌘V` wherever you need it
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
│  │  BucketCache → PhrasePoolLoader → FMProvider    │    │
│  │          ↗ ↖                                     │    │
│  │  PostProcessor  PromptComposer                  │    │
│  │  PromptComposer → PromptTemplate (JSON)         │    │
│  ├─────────────────────────────────────────────────┤    │
│  │  Shortcuts · PasteAutomation · CarbonEventTap   │    │
│  │  Persistence (SwiftData) · AppIntents           │    │
│  │  UsageTracker (100 free / paid tiers)           │    │
│  │  ContextHarvester (AX API for paid tier)        │    │
│  └─────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────┤
│  Resources                                              │
│  • Prompts/ — 6 JSON prompt templates per bucket        │
│  • Pool/ — 180+ curated signoff phrases in JSON         │
│  • PrivacyInfo.xcprivacy — Apple privacy manifest       │
└─────────────────────────────────────────────────────────┘
```

### Key Design Decisions

- **Cache-first generation**: Each bucket pre-caches up to 5 phrases at startup. `pop()` returns in <1ms. Cache miss falls through to FMF (<100ms with prewarmed sessions).
- **On-device only**: All generation uses Apple Foundation Models. No API keys, no cloud servers, no data egress.
- **Privacy > transparency**: The UI says "Private AI" — not "Foundation Models" or "on-device." Users shouldn't need to know the tech to trust the privacy.
- **Zero-config onboarding**: Launch → grant permissions → done. No accounts, no setup.
- **Freemium tiering**: 100 signoffs free, then $1/mo for unlimited + context-aware generation (steals message context from the frontmost app via AX API).

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6 |
| Framework | SwiftUI, AppKit |
| AI | Apple FoundationModels (LanguageModelSession, @Generable) |
| Architecture | Swift Package Manager (3 targets) |
| Persistence | SwiftData (SQLite) |
| Shortcuts | Carbon Event Tap (CGEvent.tapCreate) |
| Updates | Sparkle 2 |
| Minimum OS | macOS 26.0 |
| Distribution | MIT License |

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
    ├── Generation/       # FM provider, cache, pool, prompts
    ├── Shortcuts/        # Carbon event tap, paste automation
    ├── Models/           # Bucket, Profile, UsageTracker, etc.
    ├── Intents/          # macOS Shortcuts.app integration
    ├── Payments/         # Stripe shell
    └── Persistence/      # SwiftData, migrations
Tests/
├── SignoffCoreTests/     # 105+ unit tests
└── SignoffUITests/       # Brand token validation
```

---

## Agentic AI Demo

This project demonstrates **Agentic AI in practice** — an AI agent that lives in the operating system's periphery, reacts to global events (keyboard shortcuts), performs on-device inference with zero latency, and takes action (clipboard + paste automation) without user intervention.

Key agentic capabilities:

- **Always-on**: Runs as a background menu-bar agent, not a foreground app
- **Event-driven**: Global Carbon event tap listens for `⌃⌘1–6` across all apps
- **Autonomous generation**: Generates signoffs using on-device FM without cloud calls
- **Context-aware**: (Paid tier) Reads the user's active message via Accessibility API to tailor output
- **Atomic action**: Generate → copy → (optionally) paste in one seamless flow
- **Self-healing**: 3x retry with backoff on FM failure, corrupt store recovery via in-memory fallback

---

## License

MIT. See [LICENSE](LICENSE).

---

*Built with Swift 6, Apple Foundation Models, and way too much coffee.*
