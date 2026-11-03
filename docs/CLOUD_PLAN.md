# Cloud Generation Plan — Dev Key + Pro Subscription

**Status:** approved direction (decided 2026-08-27). Hardware lists stay out of the product — no corpora, no canned pools. Quality + infinite diversity come from a real model; repetition is handled with rolling history in the prompt.

## The problem

The shipping path generates with Apple's on-device ~3B Foundation Models model. Its documented failure modes (see comments in `GenerationTuning`, `Providers`, `PromptComposer`): noun salad, comma-glued run-ons, opener-fixation ruts, a ~15–20 line pop-culture recall span, and the "pink-elephant" effect (it copies lines it is told to avoid). The pipeline compensates with a 24-attempt retry budget, a 13-rule validator, a growing banned-word graveyard, and prompt gymnastics — up to 36 model calls per accepted signoff, and format-perfect nonsense still passes. This is the root cause of "the signoffs are REALLY bad."

A corpus cannot fix this: at 50 emails/day, even 1,000 curated lines repeat inside a month. Generation with sufficient model capacity is the only scalable answer.

## What exists now (landed on disk)

- `Sources/SignoffCore/Generation/CloudProviders.swift` — `OpenAIProvider` (gpt-4o-mini) + `AnthropicProvider` (claude-haiku-4-5) implementing `GenerationProvider`. 5s timeout, temperature from `GenerationTuning`, 96-token cap, keys from env (`SIGNOFF_OPENAI_KEY` / `SIGNOFF_ANTHROPIC_KEY`) or Keychain (`com.signoff` service, accounts `api.openai` / `api.anthropic`). Minimal validation: format sanitize + pasteable + length + unhinged safety gate. No banned-word scaffolding.
- `Sources/SignoffCore/Generation/FreshExamples.swift` — web-harvested few-shot anchors (see below).
- `Sources/SignoffCore/Generation/DynamicTokens.swift` — `{weekday}` token ("Not built for {weekday},") resolved at template load and output.
- `Bench/main.swift` (`swift run ProviderBench`) — single-roll A/B per bucket×provider with rolling history, writes `bench_results.md`. Cloud arms use web-harvested fresh anchors, mirroring the future shipping path. No retries, no gauntlet — judges the model, not the scaffolding.
- `GenerationProviderKind` extended with `.openAI` / `.anthropic`.

## Fresh examples subsystem (user decision 2026-08-27)

The user supplied a list of great unhinged signoffs and asked for an online search tool that caches ~5 examples. Shipped as `FreshExamplesService`:

- **Exa** search (`x-api-key`, env `EXA_API_KEY` or Keychain `api.exa`) — chosen over Brave/SerpAPI because it returns extracted page text, not just links.
- Queries rotate over a small bank ("funny email sign-offs people actually use", …), 2 per refresh, ~6 results each → `FreshExamplesFilter` extracts signoff-shaped lines (2–9 words, capitalized, no links/meta-talk/emoji) and reuses the unhinged safety gate.
- Pool of 8 cached on disk (`~/Library/Application Support/Signoff/FreshExamples.json`), 7-day TTL, 5 surfaced per generation as `curatedExamples` — **style anchors only, never served to users** (no exhaustion failure mode; the user's no-corpus rule holds).
- Static banks in `Prompts/*.json` remain the offline fallback; the user's example list was merged in (Kuzco poison, Fast & Furious, pits of hell, dynamic `{weekday}`).
- Not wired into the CURRENT FM shipping path (the 3B model copies examples verbatim — "phrase bank" effect documented in PromptComposer). Activates with the cloud-primary cutover; the bench's cloud arms already use it.
- Unit tests: `FreshExamplesTests` (7 tests, pure — no network).

**WIRED 2026-08-27 ("just fix it"):** `GenerationService.runGeneration` now walks **cloud primary → FM fallback**. `CloudProviderWalk.availableProviders()` (OpenAI first, then Anthropic — only those with keys) feeds `executeCloudGeneration`: 2 rolls per provider (`maxAttemptsPerCloudProvider`), web-harvested anchors for creative buckets, `CloudPromptAugment` rolling-history avoid list (last 30 lines). Success records `.openAI`/`.anthropic` as the provider kind. Any failure (no key, 401, timeout, reject) falls through to the existing FM hybrid loop — keyless Macs behave exactly as before. Verified: bogus-key run falls back cleanly (`ErrorRateHarness` exit 0); keyless path unchanged. **Remaining for Pro launch:** proxy holding the real key + license auth (Phase 2 below) — until then, cloud activates only on machines with a key in env/Keychain (dev + BYOK users).

## Business model (decided)

**Developer holds the API key. Users pay Pro.** Free tier is quota-limited (current `LicenseFeatures.freeDefault.generationsPerWeek = 10`); Pro removes caps / unlocks everything.

## Why the dev key needs a proxy (do not skip this)

An API key embedded in a distributed, unnotarized-yet Developer-ID DMG **will be extracted** (strings/grep on the binary, mitm on the download). So:

1. **Phase 1 (today, no backend):** keys live in Keychain on the DEV's machine; the `ProviderBench` harness and local runs work. BYOK fields can ship in Settings for early testers using their own keys. No key ships in the binary.
2. **Phase 2 (Pro launch):** a minimal proxy holds the real keys:
   - Thin HTTPS endpoint (Cloudflare Worker / Vercel edge / 32MB VPS) that forwards `POST /generate` to OpenAI/Anthropic.
   - Auth: the app presents a Pro license token — reuse the existing Ed25519 `.signofflicense` (client already has `LicenseVerifier`; proxy verifies the same signature with the public key, no database needed for v1).
   - Rate limit per license (e.g. 2,000 generations/month) to bound worst-case cost; per-IP rate limit for anonymous/free quota.
   - Server logs counts only — never store signoff text (privacy-first promise).
3. **Phase 3 (scale):** add per-license counters (D1/Redis), abuse cutoffs, provider failover (OpenAI → Anthropic) server-side.

## Cost math (order-of-magnitude, gpt-4o-mini pricing ~$0.15/1M in · $0.60/1M out)

Per generation ≈ 500 prompt tokens + 20 output tokens ≈ **$0.00009** (with rolling history, say 800 in → ~$0.00013).

| Segment | Usage | Monthly cost/user | Note |
|---|---|---|---|
| Free (10/week) | ~43/mo | ~$0.005 | negligible — give free users cloud quality too |
| Typical Pro | 300/mo | ~$0.04 | at $4.99/mo → ~99% margin |
| Heavy (50/day) | 1,500/mo | ~$0.20 | still ~96% margin |
| Lifetime $99 user | 200/mo avg | ~$0.026/mo | breakeven in ~1.5yr of heavy use, far sooner typically |

Key implication: **the free tier can afford real model quality.** The viral moment (Often hit #1) is decided by the first-run experience — do not put 3B quality behind the free door.

## Shipping-path changes when "go" (not done yet — explicit gate)

1. `GenerationService.runGeneration`: provider walk = **cloud primary** (OpenAI → Anthropic on failure) → FM fallback when offline/unavailable → honest failure.
2. Prompt changes: send rolling history (last ~30 lines) in the prompt for ALL buckets (cloud handles avoid lists; delete the pink-elephant workaround comment rationale), keep the professional closed-menu until cloud quality is proven.
3. Retry budget collapses 24 → 2–3 (model competence replaces lottery).
4. Delete the 3B-era scaffolding: banned-word graveyard, mechanism lanes, register-cycling hacks, `sanitizeSignoff` comma surgery (keep basic comma guarantee), most of `SignoffQualityValidator`. Keep `validatedCynical` safety gate.
5. Pro gating: cloud calls gated by license token against the proxy; free = quota; FM fallback free for everyone offline.

## Verification loop (already runnable)

```bash
swift run ProviderBench --count 12 --bucket unhinged        # FM baseline (works today)
SIGNOFF_OPENAI_KEY=sk-... swift run ProviderBench --count 12 # adds OpenAI arm
SIGNOFF_ANTHROPIC_KEY=sk-ant-... swift run ProviderBench     # adds Anthropic arm
```

Judge `bench_results.md` by hand per bucket before/after any wiring change. Acceptance bar: a stranger would sign an email with ≥90% of cloud lines; zero near-duplicates across the rolling-history window.

## Risks

- **Key extraction** — mitigated by proxy; never ship the raw key.
- **Latency** — cloud ~0.7–2s vs FM ~1–4s; 5s timeout + FM fallback keeps the shortcut responsive.
- **Cost blowout** — per-license rate limits + monthly cap alarm at the proxy.
- **Apple policy** — none: plain HTTPS calls, no sandbox issue (Developer ID path).
- **Provider model deprecation** — model IDs are single constants in `CloudProviderConfig`.
