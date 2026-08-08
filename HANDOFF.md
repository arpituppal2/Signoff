# Signoff — Handoff to continue

## TL;DR (what's actually wrong)
The build is broken **only** in `Sources/SignoffUI/Popover/SignoffMenuContent.swift`.
`swift build --target SignoffCore` passes clean. The whole-app `swift build` fails
solely because of one file. Fix that one file and the project should compile.

## The trap the previous session fell into
`SignoffMenuContent.swift.bak` is a **broken intermediate snapshot and must NOT be
used as the structural reference.** It references `splashStarted` which is never
declared (`@State private var splashStarted` does not exist in it) — so it never
compiled. The previous session kept trying to restore/rebuild from `.bak` and
getting cascading brace errors. **Delete `.bak` and forget it exists.**

### Use HEAD as the reference instead
The last *compiling* version of the file is the committed HEAD:

```
git show HEAD:Sources/SignoffUI/Popover/SignoffMenuContent.swift   # 1250 lines, compiles
```

HEAD's splash uses a **different, working** implementation (`splashDrawn`,
`splashFadeOut`, `splashScale`) — the `.bak`'s `splashStarted`/`SplashPhase`
version is a dead, broken branch. The user's splash tuning commits
("Splash: 3s per phase") are already at HEAD and already work. **Keep the HEAD
splash as-is.**

## What HEAD's file contains that must be removed
Two features were already removed from the rest of the codebase (`SignoffCore`
builds, `AppState.swift` and `SignoffApp.swift` are already clean) but
`SignoffMenuContent.swift` at HEAD still has them:

### 1. TipKit (remove entirely)
- `import TipKit` (line 3)
- `@State private var activeTip: (any Tip)?`
- `if activeTip != nil { tipStrip }` block in `body`
- `private var tipStrip: some View { ... TipView(tip) ... }`
- `private func evaluateActiveTip() async { ... }` (references `SelectBucketTip`,
  `GenerateNeedsBucketTip`, `FirstGenerationTip`,
  `AccessibilityPermissionTip`, `InputMonitoringPermissionTip`,
  `TeachVoiceTip`, `CustomBucketTip`)
- `await evaluateActiveTip()` call in `.task`
- `syncTipParameters(appState: appState)` call in `.task` (if present)
- The `SignoffTips.swift` file is already deleted from disk and `Sources/SignoffCore`
  builds without it — so any `SignoffUI` reference to those tip types is dangling.

### 2. Custom bucket (remove entirely)
The Custom bucket was removed from the model layer (see summary: removed from
`PersistenceController`, `SettingsView`, `AppState`, `Bucket` defaults, etc.).
HEAD's `SignoffMenuContent.swift` still references it:
- `case BucketID.custom.rawValue: "Custom voice"` in the bucket-tagline switch
- `else if let bucket = ..., bucket.id == BucketID.custom.rawValue { customFooterPreview(bucket) }` branch in `previewSection`
- the whole `private func customFooterPreview(_ bucket: Bucket) -> some View { ... }`
  (references `RichTextFooter.attributed`, `AttributedStringPreview`)
- `CustomBucketTip.customBucketTip` in the tip candidates list
- `RichTextFooter` / `AttributedStringPreview` imports are still fine to leave
  unused (they're real types in `SignoffCore`/`SignoffUI`), but the Custom branch
  must go since `BucketID.custom` no longer exists as a populated default.

### Also fix while in there (post-migration drift in the popover)
- Shortcut hint should already honor the new `ctrlOpt` (`⌃⌥`) modifier, not the
  old `optCmd` (`⌥⌘`) / hard-coded `⌃⌘`. The previous session fixed `shortcutText`
  to switch on `binding.modifier` ("ctrlOpt"/"optCmd"/default) — make sure HEAD's
  version also does this. The `shortcutHintForBucket` helper similarly.
- `ForEach(appState.recentGenerations) { gen in` in the history page should use
  `ForEach(appState.recentGenerations, id: \.id) { gen in` (previous session made
  this change — `SignoffGeneration` may not conform to Identifiable by hash).

## Safest approach
Reset the file to HEAD, then do minimal surgical deletes + the two fixes above:

```
git checkout HEAD -- Sources/SignoffUI/Popover/SignoffMenuContent.swift
# then Edit out TipKit + Custom bucket + fix shortcut/hints, INCREMENTALLY
swift build   # after each batch of edits
```

Do NOT hand-rewrite the 1250-line file from scratch — too easy to drop the
working splash. Edit HEAD's file in place.

## Verification (do ALL of these before declaring done)
1. `swift build` — exit 0, no warnings about the menu file.
2. `swift test` — prior count was 120 passing. Note: `Tests/SignoffCoreTests/
   GenerationQualityTests.swift` is a NEW untracked file (?? in git status) — run
   it; if it was written to assert generations avoid the banned guard words, make
   sure it still passes with the current prompts. There is also a
   `default.profraw` untracked file (LLVM coverage artifact) — leave it, it's junk.
3. Launch the app, hit `⌃⌥1` (Normal), `⌃⌥2` (Professional), `⌃⌥3` (Cynical).
   CarbonEventTap debug logs should confirm shortcut fires; a signoff should land
   on the clipboard / paste at cursor. Watch for the Apple SensitiveContentML
   error-15 (prior fix: keep banned words OUT of the prompt/instructions, validate
   post-generation only via `ProviderResponseGuard`).
4. Open the popover from the menu bar item — confirm the splash plays once (the
   user has been tuning it: drawOn → zoom → drawOff+fade) and the Voices/Compose
   two-column layout renders without the tip strip and without the Custom voice.

## Prompt / generation quality state (already done, do not regress)
- `general.json` (Normal): no examples in `userVariants`, huge `guardWords` incl.
  slang (bro, dude, vibe, sus, npc…) and filler (oops, ugh, sigh, honestly,
  literally, basically, just, really, penguin, distracted, figuring, still).
- `professional.json`: temp lowered to 0.4–0.6, corporate buzzwords in guardWords,
  "Do NOT use: regards, best regards, sincerely, respectfully" in userVariant.
- `unhinged.json` (Cynical): profanity moved out of the prompt into guardWords.
- `SignoffOutput.swift` `@Guide`: forbid internal punctuation + filler words;
  output must be one phrase ending in exactly one comma.
- `Providers.swift temperature(for:)`: professional 0.4–0.6, standard 0.7.
- `sanitizeSignoff`: strips ",." ", !" trailing combos, handles "phrase comma." →
  ",", collapses double commas, guarantees exactly one trailing comma.
- Cache hits now validated against guardWords (falls back to live gen on violation).
- Sessions always created fresh in `FoundationModelsSessionPool` (prewarm corrupts
  content-filter state — disabled).

## The user's open ask for THIS phase (not yet started): "make it not feel generic"
> "the app feels quite generic. It doesn't have it's own vibe to it. need to fix that."
This is a **design/polis- IDENTITY pass**, to be done **after it compiles & tests pass.**
Scope it before touching pixels — read `Sources/SignoffUI/Components/Brand.swift`
(the design tokens: ember accent, ink/surface/divider palettes, typography,
motion) and `CardStyles.swift` first to understand the existing system so you
extend it rather than reinvent it. Then decide the identity direction and propose
it before implementing (the user values "simple is good, don't overcomplicate").
Do not start this until the build is green.

## Constraints that must hold (from the user, hard)
- "simple is good, don't overcomplicate." Resist adding features as a fix for
  "feels generic" — the fix is aesthetic identity, not more buttons.
- "study ai slop and get rid of it." Generations must read like a real person,
  not LLM word salad.
- "no agents." Do not add agent/autonomous/loop features.
- TipKit tips are GONE — "friction, not a feature." Do not re-add.
- Signoffs: no internal punctuation, hardcode the single trailing comma.
- Three voices only: Normal, Professional, Cynical. Custom is gone.

## Git state at handoff
- Branch `main`. Working tree dirty (see `git status`). `SignoffTips.swift` and
  `ContextHarvester.swift` / `SilentLearningEngine.swift` are deleted (`D`).
  `.bak` file is untracked — delete it. `GenerationQualityTests.swift` is untracked.
- Do NOT commit unless asked. Do NOT push unless asked.
