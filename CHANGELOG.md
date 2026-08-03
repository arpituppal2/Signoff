# Changelog

## 1.1.0 — 2026-08-07

### Hybrid generation + quality gate

- **Curated corpus.** Bundled 138 Normal, 128 Cynical, and 119 Professional
  high-quality signoffs as processable package resources. `Package.swift` now
  processes `Resources/Corpus` so the corpus is actually bundled — previously it
  was silently unbundled, which left the curated-fallback path empty.
- **Deterministic local validator.** New `SignoffQualityValidator`: banned
  tokens and n-grams, per-bucket word-count ranges, single-line enforcement, no
  markdown or quotes, no model narration, Jaccard similarity against recent
  history (rejects > 0.7), and a vowel-density readability check. Failed live
  attempts get a summarized "PREVIOUS ATTEMPT REJECTED" corrective instruction.
- **Bounded hybrid pipeline.** Generate → validate → retry with corrective
  prompt → if every attempt fails the validator, select a mechanism-diverse,
  history-aware curated fallback. Raw model text never reaches paste or
  clipboard — only a validated or curated signoff is pasted or copied. The
  curated-fallback path returns success and the signoff is presented normally.
- **Prompt rewrites.** Professional now permits conventional closers (Best
  regards, Warmly, Sincerely, etc.) instead of banning them; general and
  cynical drop the ghost-inbox and surreal-noun-poetry angles. All four
  templates guard only genuinely-bad patterns.

### Shortcuts

- **After-Signoff special action.** `ShortcutManager.register` gains a
  `runSpecialAction` closure; ⌃⌥F fires the new `pasteAfterSignoff` action.

### UI / overlay

- **At-caret signature animation.** The write/unwrite pen-stroke overlay is
  resolved from the frontmost app's AX caret rect (`CaretLocator`) and shown in
  a non-activating floating `NSPanel`, fading before paste lands.
- **Splash fix.** The startup splash now uses a solid window-background color so
  the empty-state signature glyph no longer bleeds through (fixes the startup
  double-signature).
- **Rich-text editor.** Rebuilt with `ResizingTextView`, `RichTextEditor`,
  `RichTextToolbar`, and `ScalableImageAttachment`, replacing the deleted
  `RichFooterEditor`.

### Hygiene

- `.gitignore` local `/build/` and `/default.profraw`.
- Removed four unused legacy modules: `ContextHarvester`,
  `SilentLearningEngine`, `SignoffTips`, `RichFooterEditor`.
- Test suite aligned with the new generation and shortcuts APIs; added
  `GenerationQualityTests` with a banana-fixation regression sentinel.

## 1.0.0

Initial release.
