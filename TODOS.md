# TODOS — Signoff (backlog from /autoplan review)

## SignoffCore

- [ ] **Priority:** P0 — `swift test` does not compile: `Tests/SignoffCoreTests/GenerationTests.swift` references `GenerationProviderKind.offlineFallback` (badge title, rawValue, isLiveOnDevice, and `allCases == [.foundationModels, .offlineFallback]`), which was removed in the v1.1.0 free-and-open-source commit. Stale on `main`; blocks every local `swift test` run. Strip the dead `.offlineFallback` assertions so the suite compiles. (CI skips on runners lacking the macOS 26 SDK, so this is invisible there but red locally.)

## SignoffUI / SignoffApp (string truth-up)

- [ ] **Priority:** P1 — Truth-up all in-app strings that still promise a private offline phrasebook: `ErrorFixCard.swift` `.fmUnavailable` (line 37) and `.fallbackExhausted` / `.rateLimited` dead cases (lines 23/24/39/60), `SettingsView.swift:355` footer, `AboutWindow.swift:137/145`, `HelpOverlayWindow.swift:72`. README pool copy is fixed in v1.1.1; these remain. Independent of the backup-model work.

## v1.2.0 (backup model — deferred; see plan `main-autoplan-plan-20260730-181917.md`)

- [ ] **Priority:** P1 — Build the provider routing seam (eng review C1): `GenerationProvider` is decorative; both generation call sites hardcode `FoundationModelsProvider()`. Add a `provider(for:)` resolver before a backup provider can ever be called.
- [ ] **Priority:** P1 — Make `guardWords` real for both providers (eng review C2): loaded from JSON but never consumed by `PromptComposer` / `ProviderResponseGuard`. Latent bug on the FMF path too, not just the future backup model.
- [ ] NSPopover → NSMenu HIG redesign (separate, larger scope).
- [ ] On-device fine-tuning on user signoffs (v2+, needs infra).
- [ ] Benchmark 135M vs 250M vs 360M against a *brand quality floor* before locking the band (see gate).
- [ ] Decide runtime: MLX vs single-GGUF llama.cpp DX (see gate — taste).
