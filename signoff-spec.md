# Signoff — Product Specification

> **Status:** Draft v1  
> **Date:** 2026-07-24  
> **Target:** macOS 26+, Apple Silicon (M/A series)  
> **Stack:** Swift + SwiftUI, Xcode 27, AppKit interop where needed  
> **Generation:** Apple Foundation Models framework only (zero cloud, zero hardcoded phrases)

---

## Table of Contents

1. [Product Definition](#1-product-definition)
2. [Architecture Overview](#2-architecture-overview)
3. [Foundation Models Integration](#3-foundation-models-integration)
4. [Buckets & Tone System](#4-buckets--tone-system)
5. [Personalization Model](#5-personalization-model)
6. [Core User Flows](#6-core-user-flows)
7. [Keyboard Shortcuts](#7-keyboard-shortcuts)
8. [Liquid Glass & Visual Identity](#8-liquid-glass--visual-identity)
9. [Data Storage & Privacy](#9-data-storage--privacy)
10. [Settings Window](#10-settings-window)
11. [Permission Model](#11-permission-model)
12. [Error Handling](#12-error-handling)
13. [Non-Negotiables](#13-non-negotiables)
14. [Implementation Priorities](#14-implementation-priorities)

---

## 1. Product Definition

Signoff is a native macOS menu bar application that generates short "signoff" phrases for outgoing messages, emails, and chats using on-device Apple Foundation Models with zero cloud egress. It targets Apple Silicon Macs running macOS 26+ and is built with Xcode 27, Swift, SwiftUI, and AppKit integration where necessary.

Signoff must feel like a finished Apple-quality app, not a prototype: every surface is functional, settings work, onboarding is re-openable, and interaction is animated and guided.

### Core Principles

- **Foundation Models only** — all generation uses Apple's on-device `FoundationModels` framework (`LanguageModelSession`, `Generable`, `@Guide`). No hardcoded phrase pools, no third-party APIs, no bundled fallback JSON. If FM is unavailable, show an actionable error state with retry logic.
- **On-device privacy** — all data stays in the app's sandboxed container. No cloud sync, no analytics, no remote logging in v1.
- **Apple-quality UI** — Liquid Glass materials, smooth animations, macOS HIG compliance. No flat "AI slop" design.
- **Simple and focused** — generates signoffs, stores them in buckets, surface them instantly. Stripped of over-engineering.
- **Nothing hardcoded** — all bucket definitions, tone grammars, and prompt templates are configurable.

---

## 2. Architecture Overview

### Modules (logical separation)

| Module | Responsibility |
|--------|---------------|
| **FoundationModelsClient** | Wraps `LanguageModelSession` creation, prompt construction, structured output decoding, and session prewarming. The only generation path. |
| **PromptGrammar / Buckets** | Bucket definitions, tone system configuration, prompt assembly rules stored in SwiftData models. |
| **SignoffEngine** | Orchestrates generation requests, applies personalization, handles retry with backoff, returns structured signoff objects. |
| **UI Surfaces** | MenuBarPopover, SettingsWindow, Onboarding flow, HistoryView, BucketEditor. |
| **Permissions & System** | Clipboard access, global shortcut monitoring (Carbon event tap with Input Monitoring permission), Accessibility paste automation, permission state management. |
| **Persistence** | SwiftData models: `Bucket`, `Profile`, `SignoffGeneration`, `AppSettings`. Local sandbox container only. |

### App Form Factor

1. **Menu bar status item** — primary surface. Click opens popover anchored to the status item.
2. **Popover** — `NSPopover` with `.transient` behavior. Contains bucket selector, generate/copy controls, signoff preview, and status line.
3. **Settings window** — separate `WindowGroup` with toolbar-pane layout (General, Profile, Buckets, Shortcuts, Privacy, Advanced, History).

### Retained from Current Codebase

- `StatusBarController` + `NSStatusItem` setup (icon changed to `signature` SF Symbol)
- `NSPopover` with `.transient` behavior (NSHostingController root = `PopoverContentView`)
- `CarbonEventTap` for global shortcut listening
- `PasteAutomation` for Accessibility-based ⌘V synthesis
- `PersistenceController` with SwiftData (Streamlined)
- `AboutWindowController`, `HelpOverlayWindowController`
- Sparkle update checking

### Removed from Current Codebase

- **Bundled phrase pools** — `BundledProvider`, all JSON pool files, `BundledPool.swift`, fallback to hardcoded phrases
- **Provider fallback chain** — `ProviderFallback.swift`, `MockGenerationProvider`, `GenerationProviderKind` (simplified)
- **MetricKit subscriber** (not needed in v1)
- **CelebrationCapsuleCoordinator** (over-engineered for v1)
- **FirstLaunchOverlay** (duplicated onboarding)
- **A11yExplainerCoordinator** (onboarding handles permissions explanation)
- **TipKit integration** (over-engineered tips system)
- **SignoffMenuState bridge** (simplify CommandMenu)
- **PostProcessor stop-word filtering, Jaccard deduplication, emoji injection** (FM handles quality)
- **`CacheManager`** for recent texts (FM session handles context)

---

## 3. Foundation Models Integration

### API Surface

Uses Apple's `FoundationModels` framework as already imported in the current codebase:

```swift
import FoundationModels

// Session creation
let session = LanguageModelSession(instructions: instructions)

// Structured output via @Generable
@Generable(description: "A short email signoff phrase.")
struct SignoffOutput: Sendable {
    @Guide(description: "A single short email signoff of 3–14 words ending with . ! or ?. No quotes, no recipient name, no markdown, no leading 'I'.")
    var text: String
}

// Generation
let response = try await session.respond(
    to: prompt,
    generating: SignoffOutput.self,
    options: GenerationOptions(temperature: 0.7, maximumResponseTokens: 64)
)
return response.content.text
```

### Session Pool

- Prewarm sessions per-bucket at app launch (non-blocking, utility priority).
- Each bucket gets its own `LanguageModelSession` with stable instructions.
- On context-window overflow, create a fresh session automatically.
- Singleton `FoundationModelsSessionPool` (actor) managing session lifecycle.

### Prompt Architecture

- **Instructions** (stable, per-bucket): system prompt + rules defining the bucket's tone, constraints, and style. These are set at session creation and never change.
- **Prompt** (per-request): user variant + positive/negative examples + profile context + avoidance list.
- **Prompt prefix** (stable head of prompt used for `session.prewarm(promptPrefix:)`).

### Prompt Rules (Applied for All Buckets)

- Output only the signoff phrase — no quotes, labels, or explanation.
- One sentence, 3–14 words.
- Never include recipient or sender names.
- Never start with "I" or "I'm".
- End with a period, exclamation mark, or question mark.

### Retry Strategy

When Foundation Models fail:
1. **Immediate retry** with same parameters (handles transient failures).
2. **Second retry** with slightly higher temperature (0.8 → 0.9) for variety.
3. If all retries fail, show an actionable error card to the user.

Error card should show:
- What went wrong (Apple Intelligence not enabled, model not downloaded, device not eligible, etc.)
- A "Retry" button
- A link to the relevant System Settings pane when applicable

---

## 4. Buckets & Tone System

### Bucket Set

Hybrid of spec buckets and current codebase — keep 5-6 buckets, renamed/restructured to match the spec's tone ladder:

| # | Name | Tone | Emotion | CYNICAL Gate | SF Symbol |
|---|------|------|---------|-------------|-----------|
| 1 | **Professional** | Polite, composed, "Apple Mail friendly," minimal slang. Workplace/formal use. | Calm | No | `person.text.rectangle.fill` |
| 2 | **Standard** | Light, upbeat, accessible warm humor. Everyday messages and casual chats. | Warm | No | `text.alignleft` |
| 3 | **Unhinged** | High-energy, playful chaos, internet humor, surreal imagery, meta-references. | Deranged/Chaos | Yes (opt-in) | `bolt.fill` |
| 4 | **[Reserved/Apple Intelligence Safe]** | Firmly within Apple Intelligence constraints, entirely safe and brand-aligned, "smart assistant" voice. | Safe | No | TBD |
| 5 | **Custom** | User-defined via prompt instructions. Duplicate-able for creating new buckets. | Variable | Configurable | `asterisk.circle.fill` |
| 6 | **Footer** | Postfix mode only (name, full signature block). Not a generation bucket. | N/A | No | `signature` |

### CYNICAL Content Gate

- Bucket 3 (Unhinged) can contain profanity, darker humor, and surreal imagery.
- CYNICAL content is **opt-in only** via a per-bucket toggle in Settings → Buckets.
- The toggle is explicitly labeled: "Allow unhinged/cynical content (may include mild profanity)."
- Default: OFF.
- The toggle controls what the Instructions tell the FM model — when off, the prompt instructs the model to stay within safe constraints.

### Bucket Configuration

Each bucket stores (in SwiftData):
- `id`, `name`, `iconSymbol` (SF Symbol name)
- `sortOrder`, `isEnabled`
- `isCustom` (true for user-duplicated buckets)
- `toneDescription` — short text describing the bucket's style for prompt building
- `temperature` — FM generation temperature (0.0–1.0)
- `emojiEnabled` — per-bucket emoji toggle
- `cynicalOptIn` — CYNICAL gate for Unhinged bucket
- `customInstructions` — user-supplied prompt customizations (for Custom bucket type)
- `postfixMode` — nothing / name / fullFooter (for Footer bucket)
- `createdAt`, `updatedAt`

### Custom Buckets

Users can duplicate any existing bucket to create a new one. The duplicate inherits:
- The parent's tone description and temperature
- A new name (default: "{Parent Name} Copy")
- Editable tone description, temperature, icon, and custom instructions
- Custom buckets appear in the popover and shortcut system just like pre-defined ones

---

## 5. Personalization Model

### Profile Fields (Full)

| Field | Type | Max Length | Required |
|-------|------|-----------|----------|
| Name | String | 100 chars | No |
| Title | String? | 100 chars | No |
| Company | String? | 100 chars | No |
| Email | String? | 254 chars | No |
| Phone | String? | 50 chars | No |
| Website | String? | 500 chars | No |
| Self-description | String | 500 chars | No |

### Self-Description Usage

The 500-character field is injected into the FM prompt as context to tailor signoffs:
- "Voice: {self-description}"
- The model is instructed to stay within bucket and tone constraints regardless of self-description.
- Never injected into Instructions (keeps session prewarming stable).

### Emoji Toggle

Per-bucket setting (not global). Controls whether FM-generated phrases can include emoji.
- Default: OFF for Professional, ON for Standard and Unhinged.
- Configurable in Settings → Buckets or per-bucket in the popover context menu.

### Name/Footer Behavior

Configurable per-bucket:
- `nothing` — just the signoff phrase.
- `name` — appends "\n\n—{Name}" after the signoff.
- `fullFooter` — appends the full contact block (name, title, company, email, phone, website).

---

## 6. Core User Flows

### 6.1 Onboarding

Multi-step sequence on first launch (re-openable from Settings → Advanced → "Re-run Onboarding"):

1. **Welcome** — One-sentence explanation of Signoff + a short animated example (a signoff morphing into view).
2. **Profile** — Collect self-description (500-char field) + name. Simple, focused, one step.
3. **Accessibility Permission** — Explain why Signoff needs Accessibility (to paste signoffs at your cursor). Separate step with clear plain-language explanation.
4. **Input Monitoring Permission** — Explain why global shortcuts need this. Separate step.
5. **Bucket Preview** — Quick visual tour of each bucket with sample phrases, showing the tone ladder.

Onboarding flows into the popover on completion. Not required again once completed.

### 6.2 Generating a Signoff

From the menu bar popover:

1. **Bucket selector** — Horizontal strip of bucket icons/labels with glass highlight on the active bucket.
2. **Generate button** — Labeled "Generate" (not "Next"). Generates a new signoff in the selected bucket.
3. **Signoff preview** — The generated phrase animates into view (subtle slide + fade, not a hard text swap).
4. **Copy button** — Copies the phrase to clipboard.
5. **Paste** — If Accessibility is granted, the phrase is automatically pasted at the cursor after generation.

Popover stays open after generate. User can generate again in the same bucket or switch buckets. Popover closes on click-outside or Escape.

### 6.3 Global Shortcut Generation

- Pressing ⌃⌘` (Control+Command+Backtick) opens/shows the popover.
- Pressing ⌃⌘1–6 generates a signoff in the corresponding bucket directly, without opening the popover.
- When accessibility is granted, the generated signoff is pasted automatically.
- When the shortcut fires but Input Monitoring is denied, show a prompt directing the user to enable it.

### 6.4 Copy Last

- ⌃⇧C (Control+Shift+C) or button in popover copies the most recent signoff to clipboard without generating a new one.
- If no recent signoffs exist, the button is disabled.

### 6.5 History

7-day generation history in Settings with:
- **Chronological list** grouped by bucket
- **Search** across all signoff text
- **Filter by bucket** (show only Professional, only Standard, etc.)
- **Favorites** — star individual signoffs for quick access
- **Re-copy** — click any history entry to copy it to clipboard
- **Delete** — swipe or button to remove individual entries from history

---

## 7. Keyboard Shortcuts

### Default Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌃⌘` (Ctrl+Cmd+Backtick) | Open/show popover (toggle visibility) |
| ⌃⌘1 | Generate in Bucket 1 (Professional) |
| ⌃⌘2 | Generate in Bucket 2 (Standard) |
| ⌃⌘3 | Generate in Bucket 3 (Unhinged) |
| ⌃⌘4 | Generate in Bucket 4 |
| ⌃⌘5 | Generate in Bucket 5 (Custom) |
| ⌃⌘6 | Generate in Bucket 6 (Footer) |
| ⌃⇧C (Ctrl+Shift+C) | Copy last signoff |

### Modifier Options

- Default modifier: `cmdCtrl` (⌃⌘)
- Fallback modifier: `optCmd` (⌥⌘) — available when ⌃⌘ conflicts with Mission Control/Spaces
- Configurable in Settings → Shortcuts

### Shortcut Behavior

- Shortcuts work only when Input Monitoring permission is granted.
- If permission is missing, pressing a shortcut should prompt the user to enable it (direct link to System Settings → Privacy & Security → Input Monitoring).
- Conflicts with system shortcuts are detected and surfaced in Settings with a banner.

---

## 8. Liquid Glass & Visual Identity

### Design System

- **Menu bar icon:** `signature` SF Symbol as template image (system tints for light/dark).
- **Color palette:** Minimal. System accent color for interactive elements. Default text colors. No custom brand colors on functional chrome. Amber accent reserved for the "Signoff." period mark only.
- **Typography:** System fonts with rounded design variant for headings. Monospace for signoff preview text.

### Where Liquid Glass Appears

- **Popover background:** NSPopover supplies the default system glass. No manual glass overlay needed.
- **Bucket selector strip:** Subtle `.ultraThinMaterial` background to distinguish from content area.
- **Controls (Generate/Copy buttons):** Default system button styles (`.borderedProminent`, `.bordered`). No custom button chrome.
- **Signoff preview card:** Flat elevated surface inside the glass popover (no material stacking — avoids chrome-on-chrome).

### Where Glass Does NOT Appear

- **Signoff text content area** — kept fully opaque for readability.
- **Settings window** — standard macOS settings appearance (grouped Form style).

### Reduce Transparency Compliance

- All `Material` usage automatically respects system Reduce Transparency settings (SwiftUI handles this).
- No custom blur logic.

### Motion & Animation

- **Bucket switching:** Subtle opacity + short translation animation.
- **Signoff reveal:** Text slides in with fade (200ms ease-out).
- **Generate button loading:** Period pulse animation while generating.
- All animations respect `accessibilityReduceMotion` (instant transitions when enabled).

---

## 9. Data Storage & Privacy

### Storage Model

- **SwiftData** with `ModelContainer` in the app's sandboxed Application Support directory.
- **Models:**
  - `Bucket` — 6 pre-defined + user-duplicated custom buckets
  - `UserProfile` — name, title, company, email, phone, website, self-description
  - `SignoffGeneration` — bucketId, text, provider, timestamp, latencyMs, isFavorite
  - `AppSettings` — popover width, color scheme, shortcut hints, onboarding state, shortcut bindings, launch at login, shows status item
- **No cloud sync, no analytics, no remote logging** in v1.

### Store Resilience

Three-tier store open: primary on-disk → quarantine+retry → in-memory fallback. Never `fatalError` on corrupt store. Surface recovery state in popover for one-shot dismissal.

### Permissions

- **Accessibility** — required for automated paste (CGEvent post of ⌘V). Requested in onboarding with clear explanation.
- **Input Monitoring** — required for global shortcut listening (Carbon event tap). Requested in onboarding as separate step.
- **Clipboard** — write only. No clipboard reading.

---

## 10. Settings Window

Accessible from menu bar app menu → "Settings…" and popover → "Open Settings."

### Panes

| Pane | Contents |
|------|----------|
| **General** | Color scheme (system/light/dark), Show shortcut hints toggle, Show in menu bar toggle (with Quit link when hidden), Launch at login toggle |
| **Profile** | Name, Title, Company, Email, Phone, Website fields + Self-description text area (500 char limit) |
| **Buckets** | Per-bucket enable/disable toggles, emoji toggle, CYNICAL opt-in toggle (Unhinged only), custom bucket creation |
| **Shortcuts** | Shortcut recorder per bucket, Pause shortcuts toggle, conflict banner, Reset to defaults button |
| **Privacy** | Foundation Models status indicator (available/unavailable), Apple Intelligence settings link |
| **Advanced** | Verbose logging toggle, Re-run Onboarding button, Help links |
| **History** | 7-day generation log with search, filter by bucket, favorites, re-copy, delete |

---

## 11. Permission Model

### Permission States

| Permission | Required For | Onboarding Step | Revocable |
|-----------|-------------|-----------------|-----------|
| **Accessibility** | Automated paste (⌘V synthesis) | Step 3 | Yes — System Settings |
| **Input Monitoring** | Global shortcut listening | Step 4 | Yes — System Settings |

### Permission Missing Behavior

- **Generate without Accessibility:** Copy button works. User manually presses ⌘V. Show a one-time tip explaining how to paste.
- **Shortcuts without Input Monitoring:** Shortcuts are non-functional. Popover-only generation. Show a persistent status line: "Enable Input Monitoring for global shortcuts."
- Both states have actionable fix cards that open the relevant System Settings pane.

---

## 12. Error Handling

### Foundation Models Unavailable

Shown as an `ErrorFixCard` in the popover:

| Scenario | Action |
|----------|--------|
| Apple Intelligence not enabled | "Open Apple Intelligence Settings" button → deep link to System Settings |
| Model not downloaded | "Check Again" button + "Apple Intelligence is downloading" message |
| Device not eligible | Informational: "This Mac doesn't support Apple Intelligence. Signoff requires Apple Silicon (M-series)." |
| Temporary failure | Auto-retry 2x with backoff, then show "Retry" button |
| Session busy | Wait and retry once |

### Store Errors

| Scenario | User Message |
|----------|-------------|
| Corrupt store reset | "Local history was reset after a store recovery." (dismissible card) |
| In-memory fallback | "Local history is temporarily unavailable — Signoff is running without saving." (dismissible card) |

---

## 13. Non-Negotiables

1. **No dead surfaces** — every visible button, toggle, and link must have working behavior.
2. **Onboarding** must complete cleanly, be replayable, and have no broken flows.
3. **Settings window** must always display meaningful content — never an empty shell.
4. **Foundation Models only** — no hardcoded phrase fallbacks. If FM is unavailable, show errors/retry.
5. **Liquid Glass** — use system popover glass + subtle materials on chrome. No flat AI-slop design.
6. **Nothing hardcoded** — all bucket definitions, tones, and prompt parameters are in SwiftData and configurable.
7. **⌃⌘` opens popover** — this is the primary invocation shortcut. ⌃⌘1-6 for individual buckets.
8. **Generate stays open** — popover remains after generating a signoff. Users can keep generating.
9. **Per-bucket emoji toggle** — not a single global setting.
10. **All 7 profile fields** — name, title, company, email, phone, website, self-description.
11. **Both permissions** — Accessibility + Input Monitoring with separate onboarding steps.
12. **Rich history** — searchable, filterable, favorites, re-copy, delete in Settings.

---

## 14. Implementation Priorities

### P0 — Core Functionality (Must Have)

1. Foundation Models client + session pool (port from existing codebase)
2. Bucket model with 6 pre-defined buckets + Custom bucket support
3. Menu bar popover with bucket selector + Generate button
4. Copy + Paste automation (Accessibility)
5. Keyboard shortcuts (⌃⌘` + ⌃⌘1-6)
6. Onboarding flow (5 steps)
7. Settings window with all panes
8. History with search/filter/favorites
9. Per-bucket emoji toggle
10. CYNICAL opt-in gate
11. Error handling for FM unavailability with retry + actionable cards

### P1 — Quality & Polish

1. Remove bundled phrase pools and all related fallback code
2. Animation on signoff reveal and bucket switching
3. Liquid Glass materials on chrome surfaces
4. `signature` SF Symbol as menu bar icon
5. Sparkle update integration (port from existing)
6. Store resilience (corrupt → quarantine → in-memory)
7. Reduce Transparency / Reduce Motion compliance

### P2 — Stretch

1. Custom bucket creation (duplicate existing)
2. Footer bucket with full signature block
3. Per-bucket temperature and tone configuration in Settings
4. Dark mode refinement
5. Accessibility VoiceOver labels on all surfaces
6. Keyboard-only navigation of popover

### Removed from v1

- MetricKit subscription
- TipKit tips system
- CelebrationCapsuleCoordinator
- FirstLaunchOverlay
- A11yExplainerCoordinator
- BundledProvider / fallback chain
- PostProcessor stop word / Jaccard dedup / emoji injection
- CacheManager for recent texts
- MockGenerationProvider
- SignoffMenuState bridge
