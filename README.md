# Signoff

A macOS menu-bar app that generates sign-off text for your emails and messages, pasted straight into any focused field with a global keyboard shortcut (⌃⌘1–6).

## ⚠️ Important: on-device generation does not work properly

**Due to the limits of on-device computing, this project does not function properly on its own.**

The default generation path uses Apple's on-device ~3B Foundation Models model. At that size, the model cannot produce reliable output for this task. Documented failure modes include:

- **Noun salad** — format-perfect but semantically meaningless output
- **Comma-glued run-ons** and **opener-fixation ruts** (every signoff starts the same way)
- **~15–20 line pop-culture recall span** — it forgets context almost immediately
- **The "pink-elephant" effect** — it copies the very lines it is told to avoid

The pipeline compensates with a 24-attempt retry budget, a 13-rule validator, and prompt gymnastics — up to 36 model calls per accepted signoff — but this only filters the nonsense; it cannot fix it. Even with all of that scaffolding, the results are frequently unusable. **This is a hardware/model-capacity limit, not a bug that can be patched around.**

## ✅ Cloud models work well

**If you hook up a cloud model, this project should work well.**

Generation with sufficient model capacity is the only scalable answer. The codebase ships with cloud providers ready to go:

- **Providers:** `Sources/SignoffCore/Generation/CloudProviders.swift` — OpenAI (`gpt-4o-mini`) and Anthropic (`claude-haiku-4-5`), implementing the same `GenerationProvider` protocol as the on-device path
- **Walk order:** `GenerationService` runs **cloud primary → on-device fallback** — if a cloud key is present, cloud is used; otherwise it falls back to the on-device model (with the quality caveats above)
- **Fresh-example anchors:** `FreshExamples.swift` harvests signoff-shaped few-shot examples via web search (Exa), surfaced as style anchors only — never served verbatim to users
- **Rolling avoid-list:** `DynamicTokens` + prompt augmentation keep the last 30 generated lines out of new prompts, so output doesn't repeat itself

### Bringing your own key

Keys are read from environment variables or the macOS Keychain (never embedded in the binary) — see **Setup → Configure a cloud model** below for the exact variables and Keychain accounts.

## Setup

### Requirements

- **macOS 26.0 or later** (declared in `Package.swift`)
- **Xcode / Swift toolchain** (Swift Package Manager project — no `.xcodeproj` needed)

### Build & run

```sh
git clone https://github.com/arpituppal2/Signoff.git
cd Signoff
swift build
swift test        # full suite; some FM-generation tests are long-running
```

Run the app from Xcode (open `Package.swift`) or launch the built binary from `.build/`. Signoff lives in the menu bar — look for its icon after launch.

### Grant Accessibility permission

Signoff pastes generated text into whatever field is focused, which requires synthesizing ⌘V. On first use macOS will deny this until you grant access:

1. **System Settings → Privacy & Security → Accessibility**
2. Enable **Signoff** (the in-app button flips from "Grant Permission" to "Granted ✓" once the probe passes)

Without this, generation still works but pasting fails with `PasteError.accessibilityDenied`.

### Configure a cloud model (recommended)

Without a key, Signoff falls back to the on-device model — see the ⚠️ section above for why that doesn't work well. With a key, set it via environment variable or the macOS Keychain (never embedded in the binary):

| Provider | Env var | Keychain service / account |
|---|---|---|
| OpenAI | `SIGNOFF_OPENAI_KEY` | `com.signoff` / `api.openai` |
| Anthropic | `SIGNOFF_ANTHROPIC_KEY` | `com.signoff` / `api.anthropic` |
| Exa (fresh examples, optional) | `EXA_API_KEY` | `com.signoff` / `api.exa` |

```sh
export SIGNOFF_OPENAI_KEY="sk-..."   # picked up on next launch
```

With a key configured, generation quality is dramatically better: coherent, on-bucket, and varied. See [`docs/CLOUD_PLAN.md`](docs/CLOUD_PLAN.md) for the full architecture, including the dev-key + Pro subscription model.

### Usage

Press **⌃⌘1–6** in any focused text field to generate and paste a signoff; the bucket is selected by which number you press. Recent generations are managed per-bucket so output doesn't repeat itself.

### Benchmarking (optional)

`Bench/main.swift` runs a single-roll A/B bench per bucket × provider:

```sh
swift run ProviderBench   # writes bench_results.md
```

## Repository layout

- `Sources/SignoffCore/` — generation pipeline, prompts, persistence, shortcuts
- `Sources/SignoffUI/` — menu-bar popover UI
- `Tests/SignoffCoreTests/` — unit + quality/validation tests
- `Bench/`, `Harness/` — provider benchmarking and validation harnesses
- `docs/CLOUD_PLAN.md` — cloud generation architecture and roadmap
- `MASTER_SPEC.md`, `IMPLEMENTATION_SUMMARY.md` — design and implementation notes

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** — see [`LICENSE`](LICENSE).

In short: you're free to use, modify, and distribute this software, but derivative works must also be licensed under the AGPL, and if you run a modified version over a network, you must make its source available to its users.
