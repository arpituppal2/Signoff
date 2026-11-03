# Signoff — Master Spec

> ⚠️ **CORRECTIONS (2026-08-27, post-audit):** this spec was written against an
> imagined codebase and has now been reconciled with reality:
> - The "OpenAI / Anthropic providers" claimed here DID NOT EXIST until 2026-08-27
>   (`CloudProviders.swift`). They are now real AND primary (FM = offline fallback).
> - There is NO Sparkle SPM dependency. `SparkleIntegration` wraps a proprietary
>   `UpdateChecker`. Adopting real Sparkle is an open decision (needs EdDSA keys).
> - Test count claims ("86+ meaningful / all passing") were never verified. Run
>   `swift test` before quoting numbers. Several FM-generation tests are long-running.
> - StoreKit 2: still deferred. Do not claim verified.
> - The 3B-era scaffolding (banned-word graveyard, salad/skeleton validators,
>   24-attempt retry budgets, BucketCache/refill pipeline) was DELETED in the
>   2026-08-27 ponytail-audit — sections describing it are historical.
> - Distribution remains Developer-ID direct; see docs/CLOUD_PLAN.md for the
>   dev-key + Pro proxy architecture.

## TL;DR (read this first, 30 seconds)

**What:** Signoff is a macOS menu-bar app that generates polite sign-off text in any focused text field via a global keyboard shortcut (⌃⌘1–6).
**v1.0 ship scope (remaining):** designer App Icon (amber placeholder exists) + signed Sparkle `appcast` publish (keys) + notarized DMG + provider timeout **toast** (5s timeout already on disk) + coverage gaps. Host entry, status bar, onboarding, Settings, Keychain-backed cloud providers, and **license-file Pro** (Ed25519 `.signofflicense`) are **already on disk**. **StoreKit 2 is deferred** until a Mac App Store pivot — do not claim it verified.
**Effort (historical estimate):** ~20 engineer-days was the pre-rebuild bid; much of §17 #1–#7 is landed — re-estimate from the open rows only.
**Hardest open items:** notarization/signing chain + signed Sparkle appcast publish (keys) + designer App Icon / BrandColors.
**Risk:** Sparkle EdDSA key loss = total update breakage. Mitigate by storing the private key in 1Password with an offline backup.
**Distribute via:** Developer ID + notarized DMG + Sparkle. Mac App Store pivot is deferred (sandboxing would break the Carbon event-tap pipeline).

---

## Quick reference

| Field | Value |
|---|---|
| Project | `/Users/arpituppal/Downloads/Signoff/` |
| Targets | macOS 26.0 · Swift 6 (strict concurrency) · SwiftPM · Apple Silicon |
| Distribution | Developer ID + Sparkle (NOT Mac App Store) |
| Current state (disk) | Host app + status bar + TipKit tips attached + license Pro + cloud providers with Keychain. **No** StoreKit. Amber `Assets.xcassets` AppIcon placeholder + `AppIcon.icns` on disk (designer art + BrandColors still open). **14** XCTest source files under `Tests/` (method count ≠ coverage; do not claim “all passing” without a fresh `swift test`). |

---

## What's NOT in this spec

This spec is a **living backlog**, not marketing copy. Out of scope (link to canonical sources instead):

- **Full OpenAI / Anthropic API request + response schemas** — see [OpenAI API](https://platform.openai.com/docs/api-reference) + [Anthropic Messages API](https://docs.anthropic.com/en/api/messages) (linked in §8)
- **Sparkle `appcast.xml` schema** — see [Sparkle Publishing](https://sparkle-project.org/documentation/publishing/) (linked in §11)
- **visionOS `RealityView` code** — deferred to v2.0 (§15)
- **iOS / iPadOS companion architecture** — deferred to v2.0 (§15)
- **Full privacy manifest reference** — see [Privacy Manifest Files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- **WWDC session transcripts** — see [Apple Developer Videos](https://developer.apple.com/videos/)
- **Exhaustive test inventory** — see `Tests/SignoffCoreTests/` + `Tests/SignoffUITests/` (14 files on disk; re-count before quoting numbers)

---

## 1. Executive Summary

Signoff is a macOS menu-bar app that generates short, polite sign-off text in any focused text field via a global keyboard shortcut (⌃⌘1–6). The popover, host `@main` (`Sources/SignoffApp/SignoffApp.swift` with `SignoffDelegate` + `StatusBarController`), floating onboarding panel, `SettingsView`, TipKit tips + `Tips.configure()`, Keychain-backed OpenAI/Anthropic URLSession providers, and license-file Pro are **present on disk**.

**Do not claim:** SignoffApp / status bar “deleted,” StoreKit 2 verified, TipKit “complete” as a finished product surface, or inflated “86+ meaningful tests / all passing.”

**Still open for v1.0 ship:** designer Icon Composer art + BrandColors colorsets, signed Sparkle appcast publish (script exists; needs EdDSA keys — see `docs/SPARKLE.md`), notarization, provider timeout user toast (5s timeout already on disk), Settings WelcomeTip, popover section decomp (still monolithic `PopoverContentView`; empty `Sections/` dir), and honest test/coverage work.

The v1.0.1 polish layer adds CloudKit sync, deeper App Intents / Siri, and accessibility deep-dive. v2.0 expands to iOS/iPadOS/visionOS/watchOS companions.

**Hard constraint:** Signoff ships via Developer ID + Sparkle. The Mac App Store path is **deferred** — it would require a full Sandboxing audit, a new app target with `com.apple.security.app-sandbox` entitlement, and IAP review rework. The current direct-distribution path lets the Accessibility (`AXIsProcessTrusted`) + Carbon event-tap shortcut pipeline work without sandbox restrictions.

---

## 2. Current State Snapshot (disk-checked — living backlog)

| Layer | Status | File(s) |
|---|---|---|
| Brand tokens (Color, Font, Spacing, Layout, Semantic) | ✅ Present | `Sources/SignoffUI/Components/Brand.swift` |
| Liquid Glass surface (`.regularMaterial`) | ✅ Present | `Sources/SignoffUI/Components/CardStyles.swift` |
| Button styles (Primary, Ghost, Danger) + Reduce Motion | ⚠️ Present; still `.easeOut` (TASK-32 → `signatureSpring`) | `Sources/SignoffUI/Components/ButtonStyles.swift` |
| Popover | ✅ Present (monolithic; empty `Popover/Sections/` dir) | `Sources/SignoffUI/Popover/PopoverContentView.swift` |
| Bucket model + tier-gated defaults | ✅ Present | `Sources/SignoffCore/Models/Bucket.swift` |
| PostProcessor (incl. `dedupe(_:against:)`) | ✅ Present | `Sources/SignoffCore/Generation/PostProcessor.swift` |
| Provider chain (FM → OpenAI → Anthropic → Bundled) | ✅ URLSession + Keychain; `noAPIKey` only when key missing | `Sources/SignoffCore/Generation/Providers.swift` + `Keychain/KeychainStore.swift` |
| Foundation Models | ✅ `#if canImport(FoundationModels)` + prewarm from launch | `Providers.swift` / session pool |
| OpenAI / Anthropic | ⚠️ Real impls; `cloudTimeoutSeconds = 5` on disk; user-visible timeout toast still open (TASK-4/36) | `Providers.swift` |
| License Pro (`EntitlementManager`, `.signofflicense`) | ✅ Present | `Sources/SignoffCore/License/` + `Models/RevenueTypes.swift` (free = **10 gen/week**) |
| StoreKit 2 | ❌ Deferred (MAS) | Empty `Revenue/`; **never** claim verified |
| Sparkle | ⚠️ Runtime `SparkleIntegration` + SPM dep; `tools/generate-appcast.sh` real but signed publish needs keys | `Package.swift`, `SparkleIntegration.swift`, `docs/SPARKLE.md` |
| Privacy Manifest | ✅ Present | `Resources/PrivacyInfo.xcprivacy` (+ copy under `SignoffApp/`) |
| TipKit | ⚠️ **Wired, not “done”** — 3 tips + `.popoverTip` + `Tips.configure()`; Settings `WelcomeTip` still open | `Tips/SignoffTips.swift`, `SignoffApp.swift`, `PopoverContentView.swift` |
| Asset catalog (`.xcassets`) | ⚠️ Amber AppIcon placeholder; BrandColors colorsets missing | `Resources/Assets.xcassets` + `AppIcon.icns` |
| Host (`@main`, delegate, status bar, menus) | ✅ Present (single file; no separate `AppDelegate.swift`) | `Sources/SignoffApp/SignoffApp.swift` |
| Onboarding | ✅ Floating `NSPanel` + 4 steps | `Onboarding/OnboardingWindowController.swift` + `Steps/` |
| Settings | ⚠️ `SettingsView` TabView (7 panes); empty `Settings/{Sidebar,Panes}` dirs only | `Sources/SignoffUI/SettingsView.swift` |
| Tests | ⚠️ **14** XCTest files on disk; do **not** quote “86+ meaningful / all passing / ≥220” | `Tests/SignoffCoreTests/` + `Tests/SignoffUITests/` |

---

## 3. Spec Conventions

- **Phase tiers:**
  - **v1.0 (ship-blocker):** Must land before v1.0 ships. Tracked in §17.
  - **v1.0.1 (polish):** Lands in the first post-launch sprint. Tracked in §18.
  - **v2.0 (new surface):** Multi-quarter roadmap item. Tracked in §19.
- **File paths:** Always relative to the project root (`/Users/arpituppal/Downloads/Signoff/`).
- **Version gates:** When an API requires a specific macOS / Xcode version, cite it explicitly.
- **Status icons:** ✅ complete · ⚠️ partial · ❌ missing/deleted.

---

## 4. Core App Lifecycle & Entry Point — **v1.0 (landed on disk)**

**Status:** ✅ `Sources/SignoffApp/SignoffApp.swift` is `@main` with `Settings` scene, `.commands`, `SignoffDelegate` (`NSApplicationDelegate`), `try? Tips.configure()`, `SparkleIntegration.shared.startIfNeeded()`, AppState init, onboarding present, MetricKit subscribe. There is **no** separate `AppDelegate.swift` — do not claim it deleted or require a recreate.

**Remaining backlog:**
1. Optional: split `SignoffDelegate` / `StatusBarController` into their own files for readability (not a ship-blocker)
2. Keep Sparkle fail-closed until real appcast tooling exists (`docs/SPARKLE.md`)
3. Settings `WelcomeTip` (TipKit) still open — see §18 #7

**Apple guidance:** [SwiftUI App lifecycle](https://developer.apple.com/documentation/swiftui/app) · [Sparkle SPUStandardUpdaterController](https://sparkle-project.org/documentation/)

§22 skeletons are **historical reference only** — prefer the live `SignoffApp.swift`.

---

## 5. Menu-Bar Architecture & Liquid Glass Popover — **v1.0 (landed on disk)**

**Status:** ✅ `StatusBarController` lives in `SignoffApp.swift` (`NSStatusItem` + `NSPopover` + right-click menu with Settings…). Popover UI is `PopoverContentView` (not decomposed into `Popover/Sections/*`). **HIG hide:** Settings → General `Show in menu bar` persists `AppSettings.showsStatusItem`; controller sets `NSStatusItem.isVisible`. When hidden, Quit is in that pane; Settings via `SettingsSceneOpener` / app reopen / ⌘, (Dock-less LSUIElement kept).

**Remaining backlog:**
1. Optional decomp into `Popover/Sections/*` (TASK-1) — layout works without it
2. Keep Liquid Glass / no double-shadow contract with `NSPopover`
3. VoiceOver / Voice Control deep audit (v1.0.1)

**Apple guidance:** [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) · [NSPopover](https://developer.apple.com/documentation/appkit/nspopover) · [HIG Status Bar Apps](https://developer.apple.com/design/human-interface-guidelines/status-bar-apps) · [HIG Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)

---

## 6. First-run Onboarding & Permissions — **v1.0 (landed on disk)**

**Status:** ✅ Floating `NSPanel` via `OnboardingWindowController` + steps under `Onboarding/Steps/` (Welcome → Permissions → Profile → CheatSheet). Shown when `hasCompletedOnboarding == false`. Re-run from Help menu exists.

**Remaining backlog:** sensory-feedback polish on permission grant; A11y banner if user skipped; keep copy aligned to ⌃⌘1–6.

**Apple guidance:** [HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) · [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1460728-axisprocesstrustedwithoptions)

---

## 7. Settings Dashboard — **v1.0 (landed; tree differs from old SPECS)**

**Status:** ✅ `SettingsView` TabView panes (General / Profile / Buckets / Shortcuts / Privacy / License / Advanced) wired from `SignoffApp` Settings scene. License drop-zone + Keychain key fields live here. **Not** the aspirational `Settings/{Sidebar,Panes}` package tree.

**Remaining backlog:**
1. Settings `WelcomeTip` (TipKit) — still open
2. Optional split into Sidebar + Panes files (TASK-2) — UX works today
3. Shortcut recorder polish if Carbon remapping UX is thin

**Apple guidance:** [HIG Settings](https://developer.apple.com/design/human-interface-guidelines/settings) · [Settings scene](https://developer.apple.com/documentation/swiftui/settings) · [@AppStorage](https://developer.apple.com/documentation/swiftui/appstorage)

---

## 8. Network Adapters & Foundation Models — **v1.0 (mostly landed)**

**Status:** ✅ `OpenAIProvider` / `AnthropicProvider` use `URLSession` + `KeychainStore` (`CloudProviderKeychain`). `noAPIKey` is thrown when the key is absent or the HTTP status indicates auth failure — **not** a placeholder stub. Foundation Models is `#if canImport` gated with launch prewarm. Bundled fallback works.

**Remaining backlog:**
1. User-visible timeout toast (TASK-4 / TASK-36); disk already uses `cloudTimeoutSeconds = 5`
2. Dedicated provider unit tests file if coverage gaps remain after `swift test`
3. Keep keys out of logs / UserDefaults (already Keychain-first)

**Apple guidance:** [FoundationModels](https://developer.apple.com/documentation/foundationmodels) · [URLSession](https://developer.apple.com/documentation/foundation/urlsession) · [SecItem](https://developer.apple.com/documentation/security/keychain_services)

---

## 9. Revenue & Licensing — **v1.0 (license file; StoreKit deferred)**

**Why:** Pro unlocks via offline Ed25519 `.signofflicense` files (`LicenseActivator` / `LicenseVerifier`). There is **no** `StoreKitManager` on disk — claiming StoreKit 2 as verified is dishonest. Free tier quota is **`LicenseFeatures.freeDefault.generationsPerWeek = 10`**. Global shortcuts default to **⌃⌘1–6** (`ShortcutManager.defaults()`).

**Spec (matches disk):**
1. `Sources/SignoffCore/License/EntitlementManager.swift` — `isPro`, `bucketAllowed`, quota
2. `LicenseActivator` + `LicenseVerifier` — activate / verify license files on-device
3. `LicenseMigrationCard` — **must not mint stubs** (migration disabled until a real issuer path exists)
4. Free buckets: Standard + List; Pro unlocks all six + cloud providers + export

**Deferred (Mac App Store pivot):** StoreKit 2 `Product` / `Transaction.updates`, `Resources/Signoff.storekit`, `SubscriptionStoreView`.

**Apple guidance (when MAS lands):** [StoreKit 2](https://developer.apple.com/documentation/storekit/in-app_purchases) · For v1.0 direct distribution see Developer ID + Sparkle in §11 / `docs/SPARKLE.md`.

---

## 10. Asset Catalog & Brand Design — **v1.0**

**Why:** `Brand.Color.amber` aliases `.signoffAmber` (a SwiftUI Color extension in `SignoffCore/Models/Color+Extensions.swift`). The status bar template image is `NSImage(systemSymbolName: "sparkles")` — fine. `Resources/Assets.xcassets/AppIcon.appiconset` + amber `AppIcon.icns` placeholder exist (`./tools/generate-placeholder-icon.sh`); designer Icon Composer art, onboarding hero, and App Store marketing assets are still open.

**Spec:**
1. **`Resources/Assets.xcassets`** (scaffold ✅):
   - `AppIcon.appiconset` — placeholder PNGs + `AppIcon.icns` via `./tools/generate-placeholder-icon.sh`; replace with Icon Composer (per [Apple Icon Composer docs](https://developer.apple.com/design/resources/#icon-composer))
   - `BrandColors.colorset/` — still TODO: `signoffAmber`, `signoffPaper`, `signoffCharcoal`, `signoffInk`, `signoffMist`, `signoffSlate`, `signoffBlock`, `signoffSuccess`, `signoffCaution` (each with light + dark mode variants)
2. **Status bar template image**: ensure the SF Symbol `sparkles` renders as a template — `NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Signoff")?.isTemplate = true`
3. **Onboarding hero**: a 1024×1024 PNG of the brand wordmark "Signoff." in `.signoffAmber` on `.signoffPaper` background
4. **App Store screenshots**: 1280×800 (mac), 1920×1080, 2560×1600 — capture from the actual app + onboarding

**Apple guidance:** [Icon Composer](https://developer.apple.com/design/resources/#icon-composer) · [App Icon HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons) · [SF Symbols](https://developer.apple.com/sf-symbols/)

---

## 11. Notarization, Sparkle & Security — **v1.0**

**Why:** Signoff ships via Developer ID + Sparkle. `PrivacyInfo.xcprivacy` is on disk. Runtime Sparkle start is in `SparkleIntegration` (called from `SignoffDelegate`) — **not** missing. `tools/generate-appcast.sh` exists (scaffold + signed-feed paths). What is still open: EdDSA key ops + hosting a signed `appcast.xml`, notarized DMG. See `docs/SPARKLE.md` (fail closed without SDK/secrets/keys).

**Spec (backlog):**
1. Keep privacy reason codes aligned with Required Reason API taxonomy
2. Entitlements at `Sources/SignoffApp/Signoff.entitlements` — **no** App Sandbox
3. Hardened Runtime + `notarytool` staple on ship DMG
4. Real `appcast.xml` + EdDSA keys (do not lose private key)
5. Keychain for provider API keys (already) + Sparkle signing secrets in 1Password

**Apple guidance:** [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution) · [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime) · [Sparkle 2](https://sparkle-project.org/documentation/) · [Privacy Manifest](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)

---

## 12. Data Sync & CloudKit — **v1.0.1**

**Why:** Pro users want their custom buckets + recent history available across their Macs. The current `Bucket` model is `@Model` (SwiftData) but not CloudKit-backed.

**Spec:**
1. **Migrate the SwiftData container** to `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.signoff"))`
2. **Handle CloudKit sync errors** via `ModelContext`'s `autosaveEnabled` + remote-change notifications
3. **Backfill iCloud opt-in** in onboarding (Step 4: Permissions → add an "Sync to iCloud" toggle)

**Apple guidance:** [SwiftData + CloudKit](https://developer.apple.com/documentation/swiftdata) · [NSPersistentCloudKitContainer](https://developer.apple.com/documentation/coredata/mirroring_a_core_data_store_with_cloudkit)

---

## 13. Voice Control & Accessibility Deep-Dive — **v1.0.1**

**Why:** The popover already has Reduce Motion, sensory feedback, and basic accessibility labels. But Voice Control, Full Keyboard Access, and Switch Control need explicit support.

**Spec:**
1. **Tab order audit** in the popover: Generate button → Copy last button → bucket list (each row)
2. **`.accessibilityAction(named: "Generate", action: { ... })`** on the popover body so Voice Control users can trigger generation by name
3. **`.accessibilityAction(named: "Copy last", ...)`** on the popover body
4. **Switch Control scanning**: ensure all rows have `.accessibilityElement(children: .contain)` (already on the popover body)
5. **Accessibility audit** in `Tests/SignoffUITests/AccessibilityTests.swift`:
   - `testAllInteractiveElements_HaveAccessibilityLabels`
   - `testVoiceControlCommands_AreRecognized` (using XCUITest `.accessibilityAction(named:)` matching)
6. **Localization infrastructure** (deferred from §16.4): `Localizable.strings` + `String(localized:)` + `LocalizedStringResource` for App Intents parameters. v1.0 supports en only; v1.0.1 adds ja, zh-Hans, de, fr, es.

**Apple guidance:** [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) · [SwiftUI Accessibility](https://developer.apple.com/documentation/swiftui/view-accessibility) · [Accessibility Inspector](https://developer.apple.com/documentation/xcode/accessibility-inspector)

---

## 14. App Intents Automation — **v1.0.1**

**Why:** Expose Signoff to Spotlight, Shortcuts, and Siri so users can say "Hey Siri, generate a professional signoff" and have it paste.

**Spec:**
1. **Verify `SignoffShortcutsProvider`** at `Sources/SignoffCore/Shortcuts/SignoffShortcutsProvider.swift` registers both `GenerateSignoffIntent` + `CopyLastIntent` with valid invocation phrases
2. **Add `@Parameter` summaries** so Siri reads them right: `"Generate a signoff in the [Bucket] bucket"`
3. **Add `IndexedEntity` conformance** to `Bucket` so Spotlight can search buckets
4. **Test** in `Tests/SignoffCoreTests/AppIntentsTests.swift` (the `testAppShortcutsProvider_PhrasesUseApplicationNamePlaceholder` is now a count check — add a test that verifies each AppShortcut has at least one phrase)

**Apple guidance:** [App Intents](https://developer.apple.com/documentation/appintents) · [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider) · [IndexedEntity](https://developer.apple.com/documentation/appintents/indexedentity)

---

## 15. Immersive Expansion / Next-Gen Surfaces — **v2.0**

**Why:** The Signoff codebase is Swift 6 + macOS 26 + Apple Silicon. Most of the code in `SignoffCore` is platform-agnostic (Bucket, Generation, PostProcessor, AppState, License/Entitlements). The view layer is the only part that's macOS-specific. Expanding to other platforms means new view layers + a few platform-specific adapters.

**Spec — TOP 5 highest-ROI new surfaces:**

1. **iOS / iPadOS Companion App** — share `SignoffCore` via SwiftPM. iPhone app = menu bar replacement (Action Extension). iPad app = full Settings + Bucket editor with PencilKit drawing for custom signature blocks. Uses `App Intents` for the same Shortcuts surface.
2. **macOS Share Extension** — when the user selects text in any app, the Services menu shows "Signoff: Rewrite as polite" + "Signoff: Add to My List". Implements via `NSExtensionRequestHandling` in `Sources/SignoffAppExtensions/ShareExtension/`.
3. **Siri Deep Integration** — same as v1.0.1 §14 but with custom voice feedback (`AVSpeechSynthesizer`) that reads the generated signoff aloud before pasting.
4. **visionOS Spatial Popover** — port `PopoverContentView` to a `RealityView` in `Sources/SignoffVision/` so the popover hovers in the user's physical space. Use `.glassBackgroundEffect()` + `.ornament(attachmentAnchor: .scene(.bottom))` for the action bar.
5. **watchOS Complication** — `WidgetKit` complication on Apple Watch shows the last 3 generated signoffs. Tapping opens a `Text(text)` view + a "Copy to iPhone" button that syncs via `WatchConnectivity.WCSession`.

**Apple guidance:** [visionOS HIG](https://developer.apple.com/design/human-interface-guidelines/visionos) · [RealityKit](https://developer.apple.com/documentation/realitykit) · [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity) · [App Intents on iOS](https://developer.apple.com/documentation/appintents)

---

## 16. Cross-Cutting Concerns

### 16.1 Security

- **Keychain** for OpenAI / Anthropic API keys (kSecClass = kSecClassGenericPassword, kSecAttrService = "com.signoff.<provider>")
- **No analytics** (privacy-first)
- **Hardened Runtime** enabled (no JIT, no unsigned executable memory)
- **App Sandbox DISABLED** (required for Carbon event tap + Sparkle update injection)
- **Code signing** via Developer ID Application certificate
- **CSP hardening** per [OWASP MASVS](https://mas.owasp.org/)

### 16.2 Performance

- **Instruments** targets: Time Profiler (launch), Allocations (memory), Leaks (retain cycles), Animation Hitches (120ms), Network (latency)
- **Launch time budget**: < 500ms (status bar icon must appear in < 500ms)
- **Popover open**: < 100ms
- **Generation latency budget**: < 2s for Bundled, < 5s for Foundation Models, < 10s for OpenAI/Anthropic (with timeout)
- **os_signpost** traces for: generation pipeline phases, popover open/close, Settings tab switches
- **os_log** with subsystem `com.signoff.app`, categories: `generation`, `shortcuts`, `entitlement`, `popover`, `settings`

### 16.3 Testing

- **XCTest** — **14** test source files on disk under `Tests/SignoffCoreTests/` + `Tests/SignoffUITests/`. Method count ≠ coverage; **do not** claim “86+ meaningful,” “≥220,” or “all passing” without a fresh `swift test` + coverage report.
- **XCUITest** / snapshot UI tests — largely still backlog (no honest “all snapshot tests pass” claim)
- **Swift Testing** (`@Test`) — optional where already used
- **Coverage targets** (aspirational): ≥ 80% `SignoffCore`, ≥ 60% `SignoffUI`
- **CI**: prefer `swift test` on PR when runners exist; do not invent green builds in docs

### 16.4 Accessibility (full audit checklist)

- [x] Reduce Motion (BucketRowView, all 3 ButtonStyles)
- [x] Sensory feedback (.selection, .success on popover)
- [~] Accessibility labels on interactive elements (present in places; VoiceOver audit still open)
- [~] Accessibility values on bucket rows (partial)
- [x] Reduce Transparency (handled by `.regularMaterial`)
- [x] Increase Contrast (handled by `.regularMaterial`)
- [ ] Voice Control custom commands (v1.0.1)
- [ ] Switch Control scanning (v1.0.1)
- [ ] Dynamic Type (v1.0.1)

### 16.5 Rollback & feature flags (deferred to v1.0.1)

- `AppState.featureFlags` JSON-backed flag store (cached in UserDefaults)
- `featureFlags.openAIProviderEnabled`, `featureFlags.anthropicProviderEnabled`, `featureFlags.fmfProviderEnabled` — all default true at v1.0
- Flags can be flipped via a Sparkle-pushed resource (no app update required) if a provider ships broken

---

## 17. TOP 10 v1.0 Ship-Blockers (disk status — living backlog)

| # | Item | Disk status | File(s) | Remaining risk / work |
|---|---|---|---|---|
| 1 | Host `@main` + Settings + TipKit configure | ✅ Landed | `Sources/SignoffApp/SignoffApp.swift` | Optional file split only |
| 2 | `NSApplicationDelegate` + Sparkle start | ✅ Landed as `SignoffDelegate` + `SparkleIntegration` | same + `SparkleIntegration.swift` | Signed appcast publish still needs keys — see #10 |
| 3 | Status bar + NSPopover | ✅ Landed (`StatusBarController` in host file) | `SignoffApp.swift` | — |
| 4 | Onboarding floating NSPanel | ✅ Landed | `Onboarding/OnboardingWindowController.swift` + `Steps/` | Skip → A11y reminder polish |
| 5 | Settings UI | ✅ Landed as `SettingsView` TabView | `SettingsView.swift` | Optional Sidebar/Panes decomp; Settings WelcomeTip |
| 6 | Cloud providers + Keychain | ✅ Landed | `Providers.swift` + `Keychain/KeychainStore.swift` | 5s timeout landed; user toast still open (TASK-4/36) |
| 7 | License-file Pro (not StoreKit) | ✅ Landed | `License/*` + `RevenueTypes.swift` | Trial drip polish (TASK-10); never mint stubs |
| 8 | `Assets.xcassets` | ⚠️ Amber AppIcon placeholder | `Resources/Assets.xcassets` + `AppIcon.icns` | Designer Icon Composer + BrandColors |
| 9 | Notarization / Hardened Runtime ship path | ⚠️ Partial | `Signoff.entitlements` + build/DMG scripts | End-to-end notarytool on real cert |
| 10 | Sparkle appcast + EdDSA publish | ⚠️ Runtime yes / `generate-appcast.sh` yes | `docs/SPARKLE.md`, `tools/generate-appcast.sh` | Signed feed needs keys; **key loss = update breakage** |

**Open v1.0 effort (honest):** designer assets + notarization + signed appcast publish + timeout toast + test/coverage honesty — not a “rebuild deleted SignoffApp” bid. Historical ~20d estimate is stale for #1–#7. Host is present.

**StoreKit 2:** not a v1.0 ship-blocker; deferred to MAS pivot. Do not list as verified.

---

## 18. TOP 10 v1.0.1 Polish Items (with risk register)

| # | Item | File(s) | Effort | Failure mode | Mitigation | Rollback path |
|---|---|---|---|---|---|---|
| 1 | ~~CloudKit sync for `Bucket` + `SignoffGeneration`~~ **→ superseded by §24.6 v1.0.1 (6–8d, canonical)** | n/a (subsumed) | 0 | n/a | The 3-day pre-§24 estimate is stale. SwiftData + CloudKit + 1d TestFlight-only schema validation lives in §24.6 v1.0.1. | n/a (subsumed) |
| 2 | Voice Control custom commands via `.accessibilityAction(named:)` **— subset of §24.3 v1.0.1 (1d)** | `Sources/SignoffUI/Popover/PopoverContentView.swift` | 0.5 day *(additive on top of §24.3)* | Phrase conflicts with system phrases ("Generate" overlaps with TextEdit's "Generate Report") | Test phrases in a fresh user account + Voice Control grammar checker; cross-reference §24.3 for the broader accessibility push | Remove the `.accessibilityAction` modifier |
| 3 | ~~Network reachability via `NWPathMonitor`~~ **→ moved to §24.6 v1.0 (0.5 day, canonical)** | n/a (subsumed by §24.6) | 0 | n/a | The base `NWPathMonitor` wrap (0.5d) ships in v1.0; the v1.0.1 extension (1d) adds `requiresEthernet` / `requiresWiFi` filtering + 5s debounce on top of the v1.0 base. Tracked as §24.6 v1.0.1 sub-item. | n/a (subsumed) |
| 4 | Sparkle delta updates | `Resources/appcast.xml` + Sparkle config | 1 day | Delta patch fails to apply = user stuck on old version | Fall back to full download on delta failure (Sparkle default) | Revert `appcast.xml` to full-update-only |
| 5 | Dynamic Type scale audit | `Sources/SignoffUI/Popover/PopoverContentView.swift` | 0.5 day | Popover text clips at AX5 | Cap the bucket list at 4 visible rows + scroll for the rest | Lock `.dynamicTypeSize` to `.large` for the popover |
| 6 | Reduce Motion audit expansion | `Sources/SignoffUI/Popover/PopoverContentView.swift` | 0.25 day | Over-animated popover feels busy | Limit to 2 spring animations total; gate everything on `accessibilityReduceMotion` | Disable the `.symbolEffect` |
| 7 | WelcomeTip on first launch of Settings | `Sources/SignoffUI/Tips/SignoffTips.swift` | 0.25 day | Tip covers the first field the user wants to fill | Use `.position(.top)` to anchor the tip above the field | Delete the tip + revert the call site |
| 8 | Xcode Cloud workflow | `xcode-cloud/workflows/signoff-ci.yml` (NEW) | 1 day | CI burns through the 25 hr/month free tier | Set `parallel: false` + `maxBuildsPerWeek: 50`; gate main-branch runs only | Disable the workflow in App Store Connect |
| 9 | Localization infrastructure (ja, zh-Hans, de, fr, es) | `Resources/*.lproj/Localizable.strings` (NEW) | 3 days (translator time) | Translation mismatch breaks UI (truncated strings overflow) | Test with `String(localized:)` on every label; reserve 30% extra width per label | Ship en-only; remove `String(localized:)` wrappers |
| 10 | Memory Leaks pass via Instruments | n/a (testing) | 0.5 day | Real leak discovered late = backport fix to v1.0.1 | Run as part of release checklist; cap acceptable leaks at 0 | n/a (testing) |

**Total v1.0.1 effort:** **~17–19 engineer-days** (was 10.5; +6.5–8.5 from §24: §24.1 MetricKit 1.5d + §24.2 App Intents + Spotlight 2d + §24.3 Accessibility deep-dive 1d + §24.4 NLLanguageRecognizer 1d + §24.5 AppStoreServerAPI 2d + §24.6 SwiftData + CloudKit 6–8d + §24.7 AVAudioPlayer chime 1d + §24.8 NSUserActivity Handoff 1d + §24.10 Icon Composer + SwiftPM binaryTarget 1d). Apply the **live-data re-prioritization rule from §24.12**: defer items with no production telemetry signal to v1.0.2.

---

## 19. TOP 5 v2.0 New-Surface Items (Highest ROI, with risk register)

| # | Item | File(s) | Effort | Failure mode | Mitigation | Rollback path |
|---|---|---|---|---|---|---|
| 1 | **iOS / iPadOS Companion App** (share `SignoffCore` via SwiftPM) | `Sources/SignoffApp_iOS/` (NEW target) | 8 weeks | SwiftPM `SignoffCore` has macOS-only imports (Carbon, AppKit) — won't compile for iOS | Audit `SignoffCore` for platform-conditional imports; refactor to extract `SignoffCorePlatform` shared between iOS + macOS | Don't ship the iOS app; only ship iPad if iOS dependency audit fails |
| 2 | **macOS Share Extension** (Services menu "Rewrite as polite") | `Sources/SignoffAppExtensions/ShareExtension/` (NEW target) | 3 weeks | Share Extension can't import the full `SignoffCore` (memory limit) | Use a small `SignoffShareExtensionCore` framework with just the generation pipeline | Disable the extension via `Info.plist` `NSExtensionAttributes` |
| 3 | **Siri Deep Integration** (`AVSpeechSynthesizer` reads signoff aloud) | `Sources/SignoffCore/Speech/SpeechSynthesizer.swift` (NEW) | 1 week | TTS engine hangs in non-English locales | Gate the readback on the user's locale; fall back to silent | Disable the readback path; keep the paste |
| 4 | **visionOS Spatial Popover** (`RealityView` + `.glassBackgroundEffect` + `.ornament`) | `Sources/SignoffVision/` (NEW target) | 4 weeks | Apple Vision Pro is a low-volume device — ROI may not justify | Limit to v2.0 (not v2.0.1) so v2.0.1 ships without it if timeline slips | Defer the visionOS target to v3.0 |
| 5 | **watchOS Complication** (WidgetKit + WatchConnectivity) | `Sources/SignoffApp_watchOS/` (NEW target) | 3 weeks | iPhone-side `WCSession` delegate leaks when the user has no iCloud account | Use the new `WCSession.default` lifecycle (iOS 17+); test in airplane mode | Limit complication to "last signoff only" (no history sync) |

**Total v2.0 effort:** **~27 engineer-weeks (≈14 calendar weeks with 2 parallel teams — the realistic default)** (was 20 engineer-weeks; +~7 engineer-weeks from §24.2–§24.9 v2.0 items: §24.2 AppleScript/JXA 4d + §24.3 Transferable drag 1.5d + §24.4 CreateML + Speech 6d + §24.5 App Attest optional 10+d + §24.6 WebSocket 3d + §24.7 PDF export 6d + §24.8 Share + Widget + Live Activity 3d). Split into **v2.0 (≤ 6 months, ~14 calendar weeks with 2 parallel teams — realistic default)** and **v2.0+ / v3.0 (deferred, ~5+ engineer-weeks)** based on product prioritization. **Override:** if Signoff becomes the team's *primary* product (the only product, full team), the 5-team plan adds ~8 calendar weeks of parallelism (22 calendar weeks) and is acceptable; the 2-team ~14-week plan remains the conservative default to prevent underbidding.

**What is NOT in v2.0 (deferred to v3.0+):** tvOS target, Mac Catalyst target, full Passkeys + WebAuthn server validation, Apple Intelligence cross-platform @Generable patterns, full Liquid Glass app icon adoption, complete App Intents Spotlight indexing of all generations, internationalization beyond en/ja/zh-Hans/de/fr/es. The 5+ engineer-weeks deferred subset covers these.

---

## 20. Critical APIs Reference (Quick Lookup)

| API | Frameworks | Min macOS | Notes |
|---|---|---|---|
| `NSStatusItem` | AppKit | 10.0 | Menu bar anchor |
| `NSPopover` | AppKit | 10.0 | Popover container |
| `MenuBarExtra` | SwiftUI | 13.0 | Alternative to NSStatusItem |
| `.regularMaterial` | SwiftUI | 12.0 | Liquid Glass production-safe primitive |
| `.glassEffect` | SwiftUI | 26.0 | Real Liquid Glass (beta SDK only) |
| `.sensoryFeedback(_:trigger:)` | SwiftUI | 13.0 | `.selection`, `.success`, `.error` |
| `Tip` / `popoverTip` | TipKit | 14.0 | In-app hints |
| `LanguageModelSession` | FoundationModels | 26.0 | On-device generation |
| `Product.products(for:)` | StoreKit | 15.0 | **Deferred (MAS)** — not used at v1.0 |
| `Transaction.updates` | StoreKit | 15.0 | **Deferred (MAS)** — Pro is `.signofflicense` |
| `SPUStandardUpdaterController` | Sparkle | 10.13 | Auto-update controller |
| `AXIsProcessTrustedWithOptions` | ApplicationServices | 10.9 | Accessibility permission |
| `SecItemCopyMatching` | Security | 10.0 | Keychain read |
| `URLSession.data(for:)` | Foundation | 15.0 | Async network |
| `NSPersistentCloudKitContainer` | CoreData | 13.0 | CloudKit sync |
| `WKContentRuleList` | WebKit | 11.0 | Content blockers |
| `AVSpeechSynthesizer` | AVFoundation | 10.0 | Text-to-speech |
| `NWPathMonitor` | Network | 12.0 | Network reachability |

---

## 21. Decisions (with recommended defaults)

| # | Decision | Recommended default | Rationale | Override if… |
|---|---|---|---|---|
| 1 | Pro pricing tiers | **$4.99/mo, $39/yr, $99 lifetime** | Aligns with similar utility apps (Rectangle, Ice); $39/yr is the Apple-typical "save 35%" anchor; $99 lifetime is the high-end of indie utility apps | User research suggests a different tier works better in your market |
| 2 | Apple Developer Program enrollment | **$99/yr Standard Program** (already enrolled) | Required for Sparkle EdDSA keys, notarization, App Store Connect product IDs | You want to distribute only via TestFlight (still requires enrollment) |
| 3 | Marketing site | **`signoff.app` on Vercel + Cloudflare** | Static site, free tier, fast global CDN, integrates with signoff.app domain registrar | You want a self-hosted WordPress or a custom CMS |
| 4 | v1.0 launch sequence | **Sparkle GA direct** (no public TestFlight beta first) | The popover is already polished; the host files are mechanical rebuilds; v1.0.1 polish items can land in week 1 patches via Sparkle | You want a 2-week public beta to gather feedback first |
| 5 | Mac App Store pivot | **Defer to v3.0** | Sandboxing audit + IAP rework is ~2 weeks of additional work; would break the Carbon event-tap pipeline; direct distribution via Sparkle is more flexible for v1.0/v2.0 | You want to be in the Mac App Store for the "Featured" placement |

---

## 22. Code Templates (historical — superseded by live `SignoffApp.swift`)

> Skeletons below were written when host files were expected to be missing. **On disk today:** `@main SignoffApp`, `SignoffDelegate`, and `StatusBarController` already live in `Sources/SignoffApp/SignoffApp.swift`. Prefer reading/editing that file. Keep these only as reference if splitting files later.

### 22.1 `Sources/SignoffApp/App/SignoffApp.swift`

```swift
import SwiftUI
import TipKit
import SignoffCore
import SignoffUI

@main
struct SignoffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("Signoff", systemImage: "sparkles") {
            PopoverContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(appState: appState)
        }

        .commands {
            CommandGroup(after: .appInfo) {
                SettingsLink()
            }
            CommandMenu("Signoff") {
                Button("Generate Now") {
                    Task { await appState.generateNow() }
                }
                .keyboardShortcut("1", modifiers: [.control, .command])

                Button("Copy Last") {
                    Task { await appState.copyMostRecent() }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
```

### 22.2 `Sources/SignoffApp/App/AppDelegate.swift`

```swift
import AppKit
import Sparkle
import TipKit
import SignoffCore
import SignoffUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // TipKit configuration (also done in SignoffApp.init as a safety net).
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.groupContainer(identifier: "group.com.signoff"))
        ])

        // Bootstrap AppState.
        Task {
            try? await AppState.shared.initialize()
        }

        // Construct the menu-bar controller (owns the NSStatusItem + NSPopover).
        statusBarController = StatusBarController()

        // Sparkle auto-updates.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any in-flight quota reservations (no-op today; placeholder for v1.0.1).
        Task { await QuotaWindow.shared.flush() }
    }
}
```

### 22.3 `Sources/SignoffApp/App/StatusBarController.swift`

```swift
import AppKit
import SwiftUI
import SignoffCore
import SignoffUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    override init() {
        // 1. Status item with template SF Symbol.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sparkles",
                                 accessibilityDescription: "Signoff")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Signoff — generate polite sign-offs"
        }

        // 2. Popover with the existing PopoverContentView.
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 460)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(appState: AppState.shared)
        )

        super.init()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
```

### 22.4 `Sources/SignoffUI/Onboarding/OnboardingWindowController.swift`

```swift
import AppKit
import SwiftUI
import SignoffCore
import SignoffUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Signoff"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingController(
            rootView: OnboardingFlowView(
                onComplete: { [weak panel] in
                    AppState.shared.settings.hasCompletedOnboarding = true
                    panel?.close()
                }
            )
        ).view
        self.init(window: panel)
    }
}

private struct OnboardingFlowView: View {
    let onComplete: () -> Void
    @State private var step: Int = 0
    @State private var profile = UserProfile.makeEmpty()

    var body: some View {
        TabView(selection: $step) {
            welcomePage.tag(0)
            profilePage.tag(1)
            bucketsPage.tag(2)
            permissionsPage.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Text("Signoff.").font(.system(size: 48, weight: .bold))
            Text("Generate polite sign-offs in any app with ⌘⌃1")
                .font(.title3).foregroundStyle(.secondary)
            Button("Get Started") { step = 1 }.keyboardShortcut(.defaultAction)
        }.padding(40)
    }

    private var profilePage: some View {
        // SwiftData @Model classes aren't @Observable, so the `Binding($prop)`
        // sugar doesn't work. Use the explicit get/set form for optional
        // string properties (treat empty as nil).
        Form {
            TextField("Name", text: $profile.name)
            TextField("Title", text: Binding(
                get: { profile.title ?? "" },
                set: { profile.title = $0.isEmpty ? nil : $0 }
            ))
            TextField("Company", text: Binding(
                get: { profile.company ?? "" },
                set: { profile.company = $0.isEmpty ? nil : $0 }
            ))
            TextField("Email", text: Binding(
                get: { profile.email ?? "" },
                set: { profile.email = $0.isEmpty ? nil : $0 }
            ))
        }
        .padding(20)
    }

    private var bucketsPage: some View {
        Text("Choose your buckets").padding(20)
    }

    private var permissionsPage: some View {
        VStack(spacing: 16) {
            Text("Grant Accessibility").font(.title2)
            Text("Signoff needs Accessibility permission to detect ⌘⌃1 globally.")
            Button("Grant Accessibility") {
                _ = AXIsProcessTrustedWithOptions([
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ])
            }
            Button("Finish") { onComplete() }.keyboardShortcut(.defaultAction)
        }.padding(40)
    }
}
```

### 22.5 `Sources/SignoffUI/Windows/SettingsRootView.swift`

```swift
import SwiftUI
import SignoffCore
import SignoffUI

struct SettingsRootView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    // `Hashable` conformance is required by SwiftUI's `.tag()` modifier
    // when the selection type is a custom enum (not just String). Since
    // the rawValue is String, the synthesized Hashable is automatic.
    enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
        case general = "General"
        case buckets = "Buckets"
        case shortcuts = "Shortcuts"
        case account = "Account"
        case aiProviders = "AI Providers"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .buckets: return "shippingbox"
            case .shortcuts: return "keyboard"
            case .account: return "person.crop.circle"
            case .aiProviders: return "sparkles"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selectedTab {
            case .general: GeneralSettingsView()
            case .buckets: BucketsSettingsView()
            case .shortcuts: ShortcutsSettingsView()
            case .account: AccountSettingsView(appState: appState)
            case .aiProviders: AIProvidersSettingsView()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

// Per-tab detail views are placeholders; flesh out in v1.0 with @AppStorage bindings.
private struct GeneralSettingsView: View {
    var body: some View { Text("General").padding() }
}
private struct BucketsSettingsView: View {
    var body: some View { Text("Buckets").padding() }
}
private struct ShortcutsSettingsView: View {
    var body: some View { Text("Shortcuts").padding() }
}
private struct AccountSettingsView: View {
    let appState: AppState
    var body: some View { Text("Account").padding() }
}
private struct AIProvidersSettingsView: View {
    var body: some View { Text("AI Providers").padding() }
}
```

---

## 24. V2: Advanced Apple Platform Capabilities (from 30+ deep-dive research)

This section consolidates findings from 30+ parallel research agents who explored the entire developer.apple.com site. It maps advanced platform capabilities into actionable roadmap tickets for Signoff across **v1.0** (pre-ship), **v1.0.1** (fast-follow polish), **v2.0** (feature expansion), and **v3.0+** (future-proofing).

Each sub-section follows the same template: Purpose → Areas consolidated → Phased roadmap (v1.0 / v1.0.1 / v2.0 / v3.0+) with effort estimates.

---

### 24.1 Diagnostics, Profiling & Crash Reporting

**Purpose:** Hit strict performance SLAs (e.g. <100ms popover open, <500ms first token) and ship with zero observability blind spots.

**Areas consolidated:** Time Profiler / Allocations / Animation Hitches / Memory Graph, MetricKit (`MXDiagnosticPayload`, `MXCrashDiagnostic`, `MXHangDiagnostic`), `os_log` / `Logger` / `os_signpost` / Console.app, custom Instruments templates, `xctrace record` CI.

**Roadmap:**
- **v1.0** (0.5 day): `Logger(subsystem: "com.signoff.app", category: "Generation")` + `os_signpost(.begin/.end, name: "Generation")` around the provider chain + popover open. No third-party analytics. Use `\(value, privacy: .private)` interpolation for any user-content fields.
- **v1.0.1** (1.5 days): Subscribe to `MXMetricManager.shared` in `AppDelegate.applicationDidFinishLaunching`. Forward `MXHangDiagnostic` + `MXAppLaunchMetric` to a local log file. No external forwarding (privacy-first).
- **v2.0** (3 days): Custom Instruments package (.instrdst template) checked into the repo. CI runs `xcrun xctrace record --template TimeProfiler` against a synthetic generation workload. PR blocked if p95 latency regresses > 20%.

---

### 24.2 Automation, Intents, Spotlight & Background System

**Purpose:** Let users trigger Signoff from anywhere — Siri, Shortcuts, Spotlight, Quick Actions, system Notifications, AppleScript.

**Areas consolidated:** App Intents (production + `IntentTest` patterns), `AppEntity` for `Bucket`, `AppShortcut` with `\.applicationName` phrase tokens, Core Spotlight (`CSSearchableItem` + `CSSearchableItemAttributeSet`), `BGTaskScheduler` (`BGAppRefreshTask` + `BGProcessingTask`), `UNUserNotificationCenter` + `UNNotificationRequest` + categories + actions, AppleScript / JXA / ScriptingBridge / URL schemes (`signoff://`).

**Roadmap:**
- **v1.0** (1 day): `signoff://generate?bucket=work&tone=casual` URL scheme handler in `AppDelegate`. Test in Xcode: `xcrun simctl openurl booted "signoff://generate?bucket=work"`.
- **v1.0.1** (2 days): One `AppIntent` (`GenerateSignoffIntent`) with `AppEntity` for `Bucket`. `AppShortcutsProvider` registers it with the phrase *"Generate a signoff in Signoff"*. Index every `Bucket` into Spotlight via `CSSearchableIndex.default().indexSearchableItems(...)`. `IntentTest` target covers 6 cases.
- **v2.0** (4 days): `BGAppRefreshTask` to pre-warm Foundation Models off-hours. `Sdef` file to expose `generateSignoff(bucket:tone:)` to AppleScript. `NSAppleEventManager` handler. Local notification when generation takes >10s.

---

### 24.3 Pasteboard, Drag & Accessibility Advanced

**Purpose:** Bulletproof the core interaction (inject text into *any* app) and make Signoff fully accessible to VoiceOver / Full Keyboard Access / Switch Control.

**Areas consolidated:** `NSPasteboard` (general / drag / change count / `.string` / programmatic paste), `Transferable` (`.draggable` + `.dropDestination`), Accessibility (`accessibilityAction`, custom rotors, `accessibilitySortPriority`, `.accessibilityElement`, `AXAudit`).

**Roadmap:**
- **v1.0** (0.5 day): Wrap the existing programmatic paste in a `changeCount` check: read `NSPasteboard.general.changeCount` *after* `setString`, fail the paste if it didn't increment (prevents silent paste of the user's prior clipboard).
- **v1.0.1** (1 day): Add `accessibilityLabel`, `accessibilityHint`, `accessibilityAction` to every `Bucket` row + every `ButtonStyle`. `.accessibilityElement(children: .combine)` on the popover so VoiceOver treats it as one unit. Add `.accessibilityAction(.escape)` to dismiss the popover.
- **v2.0** (1.5 days): `Transferable` conformance on `Generation` so dragging from the History view lands as plain text in TextEdit / Mail / Notes / Finder. AXAudit run in CI.

---

### 24.4 AI, ML, NLP & Foundation Models Production

**Purpose:** Maximize on-device intelligence, reduce cloud API costs, and ship features that only Apple Silicon can do well.

**Areas consolidated:** Foundation Models (`@Generable` + `@Guide` + `Tool` + streaming + prewarming + session reuse + `LanguageModelSession` snapshot/restore), `CreateML` (`MLTextClassifier`, `MLDataTable`, `MLImageClassifier`), `NaturalLanguage` (`NLTagger`, `NLLanguageRecognizer`, `NLEmbedding`, `NLModel`), `Translation` (`TranslationSession`), `Vision` (`VNRecognizeTextRequest`, `VNDocumentCameraViewController`).

**Roadmap:**
- **v1.0** (1.5 day): Wrap Foundation Models calls in `LanguageModelSession` *reused* across the popover lifecycle. Call `try await session.prewarm()` in `AppDelegate.applicationDidFinishLaunching` so the first ⌘⌃1 is not 2-5s slower. `@Generable struct SignoffOutput { let text: String; let tone: String }` for type-safe response. The `AppState` is already `@Observable` (the Swift 6 Observation framework) — under Swift 6 strict concurrency it stays valid; the only change needed is marking it `@MainActor` and adding `Sendable` to any value types it returns across actor boundaries.
- **v1.0.1** (1 day): `NLLanguageRecognizer.dominantLanguage(for: text)` to detect if the user's draft is in a language the bucket supports; gracefully fallback.
- **v2.0** (6 days): Train an on-device `MLTextClassifier` on the user's prior generations to auto-suggest a bucket. Speech synthesis (`AVSpeechSynthesizer`) to read the generated signoff aloud before pasting. `TranslationSession` to auto-translate for bilingual teams.

---

### 24.5 Security, Identity, Licensing & Commerce

**Purpose:** Secure API keys, verify Pro via offline `.signofflicense` (Ed25519), and stay ahead of Gatekeeper / App Review. **StoreKit 2 is not shipped at v1.0** — `Sources/SignoffCore/Revenue/` is intentionally empty until a Mac App Store pivot.

**Areas consolidated (v1.0):** App Sandbox + Hardened Runtime (entitlements matrix: `com.apple.security.cs.*`, `com.apple.security.network.client`, `com.apple.security.app-sandbox`), `PrivacyInfo.xcprivacy`, **Keychain Services** (`SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete` with `kSecClassGenericPassword`, `kSecAttrService`, `kSecAttrAccount`, `kSecAttrAccessibleAfterFirstUnlock` — *never* `kSecAttrAccessibleAlways`), CryptoKit / Ed25519 license verify, **LocalAuthentication** for optional key reveal.

**Deferred (MAS pivot only):** StoreKit 2 (`Transaction.updates`, `SubscriptionStatus`, JWS / App Store Server API), App Attest, DeviceCheck, Apple Pay, Passkeys / WebAuthn.

**Roadmap:**
- **v1.0** (1 day, was 0.5 day): `PrivacyInfo.xcprivacy` with reason codes for `CA92.1` (UserDefaults), `C617.1` (FileTimestamp) if used. Hardened Runtime enabled with `com.apple.security.network.client` for OpenAI / Anthropic. **No App Sandbox** (we use Carbon event tap for global hot keys, which App Sandbox blocks). **+ Keychain Services** — all OpenAI / Anthropic API keys MUST live in the Keychain via `SecItemAdd` with `kSecAttrService = "com.signoff.app.provider-keys"`, `kSecAttrAccount = keyName`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (locked to device, not iCloud-backed, lost on backup restore which is correct for secrets). Never in `UserDefaults`, never in a SwiftData field, never in a file on disk. Wrap access in a `KeychainStore` actor with `@MainActor` reading. + Optional `LAContext` biometric gate for the Settings panel "Reveal" button on hidden keys with the following macOS-specific fallback chain: (1) Touch ID on supported Macs via `LAPolicy.deviceOwnerAuthenticationWithBiometrics`, (2) Apple Watch auto-unlock via `LAPolicy.deviceOwnerAuthenticationWithWatch`, (3) macOS user passcode via `LAPolicy.deviceOwnerAuthentication` (the catch-all that requires the user to type their login password). Macs with *none* of these (rare 2017- hardware) fall back to a plain "Click to reveal" button with no gate. **Pro = `.signofflicense` only** (free = **10 gen/week**).
- **v1.0.1+ / MAS** (when pivoted): StoreKit 2 + optional `AppStoreServerAPI` — not claimed as present on disk today.
- **v2.0** (10+ days): If a web companion ships, add Passkeys via `ASAuthorizationPlatformPublicKeyCredentialProvider` + WebAuthn server validation.

---

### 24.6 Data, State, Networking & Cloud Sync

**Purpose:** Instant cross-device availability + reliable remote API connectivity under flaky networks.

**Areas consolidated:** SwiftData (`@Model`, `ModelContainer`, `ModelConfiguration(isStoredInMemoryOnly:false, cloudKitDatabase:.private)`, `SchemaMigrationPlan`, `@ModelActor`), CloudKit automatic sync, `Combine` (`@Published` + operators, `assign(to: &$variable)`), `URLSession` async/await (`data(for:delegate:)`, `bytes(for:)` SSE, background sessions, `URLSessionWebSocketTask`), `Network.framework` (`NWConnection`, `NWListener`, `NWBrowser`, `NWPathMonitor`, `NWParameters.tls`), iCloud Drive (`NSFileCoordinator`, security-scoped bookmarks, `NSFileVersion` conflict resolution), HTTP/3 / QUIC auto-negotiation.

**Roadmap:**
- **v1.0** (0.5 day): `NWPathMonitor` wrapping the `URLSession` provider chain — if WiFi drops, instant fallback to Bundled (no error to user). SSE consumer pattern for Anthropic / OpenAI streaming using `URLSession.shared.bytes(for:).lines`.
- **v1.0.1** (6–8 days, was 3 days): SwiftData `@Model` for `UserProfile` + `Generation` history. `ModelContainer(cloudKitDatabase: .private)` for opt-in cross-device sync. Versioned schema + lightweight migration from in-memory to SwiftData. `@ModelActor` for background indexing. **+ 1 day of testflight-only CloudKit validation** (the schema must exist in production CloudKit console before the first user syncs; CloudKit schema drift in production is the #1 cause of SwiftData+CloudKit crashes — test with the CloudKit console in development mode first, then `xcrun cktool query-container` to verify).
- **v2.0** (3 days): Real-time collaborative editing of draft (out of scope unless we build a web companion). `URLSessionWebSocketTask` for streaming providers that prefer WebSocket over SSE.

---

### 24.7 Media, Haptics, Rendering & Document Handling

**Purpose:** Premium sensory feel + advanced rich-text / document output.

**Areas consolidated:** AVFoundation (`AVAudioEngine`, `AVAudioPlayer`, `AVAudioPlayerNode`, `AVAudioFile`, `AVAudioConverter`), `Core Haptics` (`CHHapticEngine`, `CHHapticPattern`, `CHHapticEvent`, `CHHapticParameter`, AHAP `.ahap` JSON files), `UIFeedbackGenerator` family (selection, impact, notification), SwiftUI `.sensoryFeedback(.success/.warning/.error, trigger:)`, Metal / MetalKit (`MTLDevice`, `MTLCommandQueue`, `MTLRenderPipelineState`, `MPSImageGaussianBlur`, MetalFX upscaling), WebRTC, `ReplayKit` (`RPScreenRecorder`, `RPPreviewViewController`), `CallKit` (`CXProvider`), `PDFKit` (`PDFDocument`, `PDFView`, `PDFAnnotation`, form filling), `QuickLook` (`QLPreviewController`, `QLThumbnailGenerator`), VisionKit `VNDocumentCameraViewController`.

**Roadmap:**
- **v1.0** (0.5 day): Adopt `.sensoryFeedback(.success, trigger: generationComplete)` + `.sensoryFeedback(.error, trigger: errorCount)` on the popover body. Use `NSSound(named: "Tink")` on generation complete (system sound, zero asset).
- **v1.0.1** (1 day): Subtle `AVAudioPlayer`-backed chime on first generation per session. `AVAudioSession` not needed on macOS.
- **v2.0** (6 days): `CHHapticEngine` for trackpad haptic on iOS companion (if we ship). `QuickLook` preview of generation history. Optional `PDFDocument` export of the signoff styled as a branded PDF.

---

### 24.8 Ecosystem Integration & Extensibility

**Purpose:** Put Signoff *everywhere* the user highlights text — in any app, on any Apple device.

**Areas consolidated:** App Extensions (Share extension via `SLComposeServiceViewController`, Action extension, Safari extension), WidgetKit (`Widget`, `TimelineProvider`, `WidgetBundle`, interactive widgets via App Intents in iOS 17+), ActivityKit / Live Activities (`Activity`, `ActivityAttributes`, `ContentState`, push updates, `ActivityConfiguration`), Continuity Camera, Handoff (`NSUserActivity`, `becomeCurrent`, `application(_:continue:)`), Universal Clipboard (automatic), AirDrop (`NSSharingService`), `iPhone Mirroring` (macOS 15+), Contacts (`CNContactStore` for recipient name), Calendar (`EKEventStore` for meeting context).

**Roadmap:**
- **v1.0.1** (1 day): `NSUserActivity` for the popover's current selection. Auto-routes to the iOS companion (if installed) via Handoff.
- **v2.0** (3 days): Share extension — user highlights text in any app, taps Share, picks "Signoff", gets a signoff back. WidgetKit widget showing the last 3 generations. Live Activity for long-running generations.
- **v2.0+**: Safari extension to generate a signoff for the selected text on a webpage.

---

### 24.9 Cross-Platform: visionOS, watchOS, tvOS, Catalyst

**Purpose:** Move from "a Mac utility" to "an Apple ecosystem primitive". Each of these is a separate product surface with its own UX.

**Areas consolidated:** visionOS + RealityKit (`RealityView`, `Entity`, `Component`, `System`, USDZ, Reality Composer Pro, `WindowGroup.windowStyle(.volumetric)`, `ImmersiveSpace`), watchOS + WatchKit (`WKApplication`, complications, `digitalCrownRotation`, `handGestureShortcut`, `WatchConnectivity.WCSession.default`), tvOS + Focus engine (`UIFocusEnvironment`, `UIFocusGuide`, parallax, `TVTopShelfProvider`, Siri Remote `UIPressesEvent`), Mac Catalyst (UIKit for Mac, `NSWindow.from`, Touch Bar, `UIMenuBuilder`).

**Roadmap:**
- **v2.0** (8 weeks): Extract `SignoffCore` into a standalone SwiftPM library. Build a `watchOS` target that uses `SignoffCore` for a `WKApplication` companion (complication shows last bucket used).
- **v2.0+** (12 weeks): visionOS `RealityView` spatial popover that floats the generated signoff next to the user's gaze. Initial SwiftPM + a thin visionOS shell.
- **v3.0+** (deprioritized): tvOS (low utility for text generation), Mac Catalyst (no need — we're already native Mac).

---

### 24.10 Build, Architecture, Tooling & Design

**Purpose:** Bulletproof codebase safety + modern aesthetics, both of which compound over years.

**Areas consolidated:** SwiftPM (`Package.swift`, `swift-tools-version`, `swiftLanguageVersions: [.v6]`, `.binaryTarget`, local packages, plugins, `Bundle.module`), Bundle Resources (Assets.xcassets, Info.plist keys matrix, `.xcstrings` localization), Swift 6 strict concurrency (`Sendable`, `@MainActor`, `actor`, region-based isolation SE-0414, `@preconcurrency` for non-Swift-6 deps, `@retroactive Sendable`), App icon design (superellipse shape, 1024×1024 master, layered Liquid Glass composition), SF Symbols 6 (50k+ symbols, `.symbolRenderingMode(.palette/.hierarchical/.multicolor)`, `.symbolEffect(.bounce/.pulse/.variableColor)`, `.contentTransition(.replace/.magicReplace)`), Icon Composer (`.icon` bundle format), Liquid Glass surfaces.

**Roadmap:**
- **v1.0** (0.5 day): Enable Swift 6 language mode in `Package.swift` (`swiftLanguageVersions: [.v6]`). Mark all `Observable` view models `@MainActor`. Mark exported model types `Sendable`. Add SF Symbols 6 `.symbolEffect(.pulse, value: isGenerating)` on the status icon.
- **v1.0.1** (1 day): `.binaryTarget` for any large third-party dep. `Bundle.module` migration for the `Resources/Fallbacks/*.json` files. Author a 1024×1024 app icon with Icon Composer using a layered Liquid Glass composition.
- **v2.0** (1 day): Per-feature SwiftPM library split (`SignoffCore`, `SignoffGeneration`, `SignoffRevenue`, `SignoffUI`). Each library has its own test target.

---

### 24.11 Cross-References back to existing `MASTER_SPEC.md` sections

- **§7 Settings Dashboard** ↔ **24.5 (Security & Receipts)** for per-provider key UX
- **§5 Menu-Bar Architecture** ↔ **24.7 (Haptics)** + **24.10 (SF Symbols 6)** for the popover's sensory feel
- **§8 Network Adapters + Foundation Models** ↔ **24.4 (Foundation Models prewarm + `@Generable`)** for on-device intelligence
- **§11 Notarization + Sparkle** ↔ **24.5 (Hardened Runtime entitlements matrix)** for the build's trust posture
- **§14 App Intents Automation** ↔ **24.2 (`IntentTest` coverage + Spotlight indexing)** for the test strategy
- **§17 TOP 10 v1.0 ship-blockers** ↔ **24.12 below** for retroactive additions

---

### 24.12 Top Recommendations to *add* to existing v1.0 ship-blockers

These three items are **high-ROI and low-effort** enough that they should be retroactively integrated into §17 (v1.0 ship-blockers):

1. **`NSPasteboard` changeCount validation** (from 24.3, 0.5 day): Read `NSPasteboard.general.changeCount` *after* `setString`. If it didn't increment, the paste would silently inject the user's prior clipboard — a catastrophic UX failure mode. This belongs in `ShortcutManager.swift`.

2. **`os_signpost` for LLM latency** (from 24.1, 0.5 day): Wrap each provider call in `os_signpost(.begin/.end, name: "OpenAI")` / `Anthropic` / `FoundationModels`. Without it, post-launch diagnostics of "Signoff feels slow" is impossible — we won't know if the bottleneck is network, Foundation Models load, or popover render.

3. **`FoundationModels` prewarming** (from 24.4, 0.5 day): Call `try await session.prewarm()` from `AppDelegate.applicationDidFinishLaunching`. Masks the 2-5s cold start on first ⌘⌃1 press. This is the single highest-impact perf win for users on macOS 26+.

4. **Keychain Services for API key storage** (from 24.5, 0.5 day — **raised from v1.0.1 to v1.0**): All OpenAI / Anthropic keys MUST live in the Keychain via `SecItemAdd` / `SecItemCopyMatching` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Plaintext UserDefaults is a rejection-grade security issue (App Review Guideline 5.1.1(iv) "Data Minimization" + 5.1.1(i) "Privacy"). Without this, App Review will reject the binary on first submission.

**Effort total:** 2 engineer-days for all four (1.5 day existing items + 0.5 day Keychain). All four are essentially free, ship them in v1.0.

**Live-data re-prioritization rule:** Re-prioritize §24.1 v1.0.1 (MetricKit subscription) in week 4 of v1.0 ship based on launch telemetry. If `MXHangDiagnostic` reports 0 hangs in the first 30 days of production, defer §24.1 v1.0.1 work to v1.0.2. If hangs > 0.1% of sessions, pull §24.1 v1.0.1 forward into the next sprint regardless of the rest of v1.0.1. This prevents the v1.0.1 list from growing unbounded and ties polish work to actual user pain.

**v3.0+ risk-register policy:** Items deferred to v3.0+ (Passkeys + WebAuthn server validation, CreateML text classifier, Apple Intelligence cross-platform @Generable, full Liquid Glass app icon adoption, complete App Intents Spotlight indexing of all generations) are **pre-launch research spikes** — they have no failure mode / rollback column because they are not yet on a critical path. When promoted from v3.0+ to a concrete version, they MUST inherit the risk-register format (failure mode / mitigation / rollback) used by §17–§19. See **§25 Open Spec Debt** below for the tracking list.

---

### 24.13 Test Strategy for §24 Sub-Sections

The §24 sub-sections that ship code (not just config or docs) need dedicated test targets, not just the umbrella §16.3 80% coverage rule. Add these test files before the corresponding code merges:

| §24 Sub-Section | Test File (NEW) | Coverage target | Key test cases |
|---|---|---|---|
| §24.1 Diagnostics | `Tests/SignoffCoreTests/MetricKitSubscriptionTests.swift` | 80% | `MXDiagnosticPayload` payload parsing; hang classification; privacy redaction in `os_log` |
| §24.2 App Intents | `Tests/SignoffCoreTests/AppIntentsIntentTestTests.swift` | 90% (per Apple App Intents testing guide) | 6 `IntentTest` cases: happy path, error path, no result, async, parameter validation, phrase matching |
| §24.6 SwiftData + CloudKit | `Tests/SignoffCoreTests/SwiftDataCloudKitMigrationTests.swift` | 75% | Schema versioning, lightweight migration on a clone of a real user's store, `cktool query-container` validation |
| §24.7 Haptics | `Tests/SignoffUITests/SensoryFeedbackTests.swift` | 70% | `.sensoryFeedback(.success)` fires on generation complete; `.sensoryFeedback(.error)` fires on error; Reduce Motion suppresses all |
| §24.8 Share extension | `Tests/SignoffShareExtensionTests/MemoryLimitTests.swift` (NEW target) | 60% | Memory usage < 50MB (App Extension limit); URL roundtrip; error path when no selection |
| §24.8 Widget | `Tests/SignoffWidgetTests/TimelineProviderTests.swift` (NEW target) | 80% | Timeline refresh, stale date, App Intent interactivity |
| §24.10 Icon Composer | `Tests/SignoffUIAssetsTests/AssetCatalogTests.swift` (NEW target) | 50% | All required sizes present (16/32/64/128/256/512/1024), superellipse mask, dark + tinted variants |
| §24.5 Keychain | `Tests/SignoffCoreTests/KeychainStoreTests.swift` | 95% (security-critical) | `SecItemAdd` + `SecItemCopyMatching` + `SecItemUpdate` + `SecItemDelete`; no key ever touches `UserDefaults`; rate-limited reads |

**Total new test files:** 8 (5 added to existing targets — `SignoffCoreTests` + `SignoffUITests` — and 3 new test targets: `SignoffShareExtensionTests`, `SignoffWidgetTests`, `SignoffUIAssetsTests`). Total new tests estimated: ~45 tests. All run in CI on every PR via `swift test` (existing targets) + new test target commands.

---

## 25. Open Spec Debt

Tracked list of spec items that need follow-up work. Each item links to the relevant section + has an owner / status.

| # | Item | Source | Status | Owner | Notes |
|---|---|---|---|---|---|
| 1 | `docs/spec-archive/v3-deferred.md` file (not yet created) | §24 v3.0+ risk-register policy | TODO | — | Move all v3.0+ deferred items from §24.5, §24.4, §24.9 into a single tracking file with research-spike status |
| 2 | `docs/spec-archive/` directory (not yet created) | §25 self-reference | TODO | — | `git mv` the prior versions of MASTER_SPEC.md here when v1.0 ships, to preserve the decision history |
| 3 | §24.5 v2.0 "App Attest optional 10+d" — clarify what triggers the optional | §19 v2.0 | NEEDS-DECISION | — | **Recommended default:** *only if a web companion ships* (the 10+d effort is non-trivial; without a web companion, App Attest has nothing to attest to). App Review's Guideline 2.5.4 already requires App Attest for some entitlements; if v2.0 introduces any such entitlement, App Attest becomes mandatory and overrides this default. Update §24.5 with the decision rule |
| 4 | §24.6 v1.0.1 "1d TestFlight-only CloudKit schema validation" — concrete test plan | §24.13 | TODO | — | Document the exact `xcrun cktool` commands + the CloudKit console schema check before the first user syncs |
| 5 | §24.4 v2.0 "CreateML text classifier" — what is the training data? | §19 v2.0 | NEEDS-DECISION | — | **Recommended default:** *on-device training on the user's prior generations, opt-in (Settings → Privacy → \"Learn my style\"), no server upload*. Privacy-first is the brand promise (§1, §16.1); a public corpus is a privacy regression. Quality will be lower for the first 50 generations; acceptable given the privacy win. |
| 6 | §24.9 v2.0 "watchOS + visionOS" — exact device coverage | §19 v2.0 | NEEDS-DECISION | — | **Recommended default:** *visionOS 1+ (Vision Pro only) + watchOS 10+*. Covers >95% of the current install base for each platform. visionOS 2 (lower-cost device) deferred to v3.0+; watchOS 11 is the same code as watchOS 10 in practice. The complication will degrade gracefully on older watchOS versions via `WKApplication` version checks at runtime. |

When any of these are resolved, update the spec inline + remove the row.

---

## End of `MASTER_SPEC.md`

This spec is the source of truth for Signoff v1.0 → v2.0. Update as decisions are made; archive superseded versions in `docs/spec-archive/`.