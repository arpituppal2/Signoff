# Signoff — Brand Identity & Design Specification

> **The mark you leave. Written by your Mac's neural engine.**

---

## 1. Core Positioning

### The One-Liner
**Signoff** is the only email signoff generator that runs entirely on your Mac's Neural Engine — learning your voice silently, generating locally, leaving nothing but your signature.

### The Unique Value Proposition
| Everyone Else | Signoff |
|---------------|---------|
| Cloud API calls | **On-device Foundation Models (Apple Neural Engine)** |
| Hardcoded phrase libraries | **Live generation — every signoff is new** |
| Manual tone selection | **Silent voice learning from your writing** |
| Generic "Best regards" | **Your voice, your tone, your signoff** |
| Data leaves your device | **Zero egress. Ever.** |

### Brand Promise
> *You write the message. Your Mac's Neural Engine writes the signature. Nobody else sees either.*

---

## 2. Brand Pillars (The DNA)

### 1. Neural Local-First
The Apple Neural Engine isn't an implementation detail — it's the **product**. Every signoff is generated on-device using `LanguageModelSession` with `@Generable` structured output. No cloud. No fallback phrases. If the model isn't ready, we tell you why and help you enable it.

### 2. Silent Intelligence
We don't ask "what's your tone?" — we **learn it**. Through permitted Accessibility observation of your outbound mail/chat, we build a `VoiceProfile` (locally, encrypted, never synced) that shapes every generation. The more you use it, the more it sounds like *you*.

### 3. The Mark
A signoff isn't text. It's a **signature** — the final flourish that says "this came from me." Our brand mark is the `signature` SF Symbol. The amber underline is the ink stroke. Every generated phrase carries that mark.

### 4. Tone as a Spectrum, Not a Switch
Five buckets aren't modes — they're **registers** on a single instrument:
- **Professional** → Executive register
- **Standard** → Conversational register  
- **Unhinged** → Creative register
- **Footer** → Formal register
- **Custom** → Your register

### 5. Apple-Quality, Not "AI App" Aesthetic
Liquid Glass materials. System fonts. Native animations. Respects Reduce Motion/Transparency. Feels like it shipped from Cupertino, not a hackathon.

---

## 3. Visual Identity

### 3.1 Logo / App Icon
```
Primary:  SF Symbol "signature" — template, system-tinted
Accent:   Amber (#D4A017) — the ink underscore
```
```
┌─────────────────────────────────────┐
│  ╭─────────────╮                    │
│  │  signature  │  ← SF Symbol       │
│  │   (ink)     │                    │
│  ╰────┬────────╯                    │
│       │ amber underline             │
└───────┴─────────────────────────────┘
```

**App Icon**: Rounded square, system material background, centered `signature` symbol in label color, amber underline stroke animates on launch (subtle, 600ms).

### 3.2 Color System
| Role | Light | Dark | Usage |
|------|-------|------|-------|
| **Amber Accent** | `#D4A017` | `#E8C56D` | Generate button, active bucket indicator, signature underline, "Signoff." wordmark period |
| **Surface Base** | System `windowBackgroundColor` | System `windowBackgroundColor` | Popover background, card surfaces |
| **Surface Elevated** | `controlBackgroundColor` + 0.08 opacity white | `controlBackgroundColor` + 0.12 opacity white | Signoff preview card |
| **Surface Selected** | Amber 12% | Amber 18% | Active bucket row |
| **Text Primary** | `labelColor` | `labelColor` | Bucket names, signoff text |
| **Text Secondary** | `secondaryLabelColor` | `secondaryLabelColor` | Tone labels, hints |
| **Text Tertiary** | `tertiaryLabelColor` | `tertiaryLabelColor` | Status line, metadata |

**No custom brand colors on functional chrome.** Amber appears *only* as the signature mark.

### 3.3 Typography
| Element | Font | Weight | Style |
|---------|------|--------|-------|
| App name / Wordmark | System Rounded | Semibold | "Signoff" |
| Bucket names | System | Semibold | 13pt |
| Tone labels | System | Regular | 11pt, lowercase |
| **Signoff preview** | **System Monospace** | **Regular** | **15pt, tracking +0.5** |
| Status/metadata | System | Regular | 11pt monospaced digits |

### 3.4 Motion Language
| Interaction | Animation | Duration | Easing |
|-------------|-----------|----------|--------|
| Bucket select | Scale 0.98 → 1.0 + background fill | 150ms | `spring(response: 0.3, damping: 0.7)` |
| Signoff reveal | Slide up 8px + fade | 200ms | `easeOut` |
| Generate button pulse | Symbol effect `.pulse` | Continuous while generating | — |
| Popover appear | System popover animation | System | — |
| **All motion respects** `accessibilityReduceMotion` → instant |

---

## 4. Voice & Tone (The App's Personality)

### Writing Principles
1. **Never say "AI" or "model"** — say "your Mac's neural engine" or "on-device intelligence"
2. **Never say "generate"** in user-facing copy — say "draft," "write," "craft," "sign"
3. **Privacy is assumed, not advertised** — no "we don't track you" badges
4. **Tone matches the bucket** — Professional bucket copy is crisp; Unhinged copy is playful

### Microcopy Examples

| Context | Professional | Standard | Unhinged |
|---------|--------------|----------|----------|
| Empty state | "Press Generate for a signoff ready to paste." | "Hit Generate. Get a signoff." | "Your inbox is waiting." |
| Generating | "Drafting on-device…" | "Thinking…" | "Consulting the void…" |
| FM unavailable | "Enable Apple Intelligence in System Settings to use Signoff." | "Turn on Apple Intelligence →" | "The neural engine's asleep. Wake it up." |
| Copied | "Copied." | "Got it." | "Yanked." |
| Permission needed | "Grant Accessibility to auto-paste at your cursor." | "Need Accessibility for ⌘V magic." | "Let me type for you. Please?" |

---

## 5. The Silent Intelligence System (Core Differentiator)

### 5.1 VoiceProfile — Built Locally, Never Leaves Device

```
VoiceProfile (SwiftData, encrypted at rest)
├── lexicalFingerprint: [String: Float]    // n-gram frequencies from observed outbound text
├── avgSentenceLength: Float               // your typical sentence rhythm
├── punctuationStyle: PunctuationProfile   // ! vs . vs ? distribution
├── formalityScore: Float                  // 0.0 (casual) → 1.0 (formal)
├── emojiFrequency: Float                  // 0.0 → 1.0
├── signoffPatterns: [String]              // your last 50 manual signoffs
├── vocabularyRichness: Float              // type-token ratio
├── lastUpdated: Date
└── version: Int                           // schema version for migration
```

### 5.2 Silent Observation Flow

```
┌─────────────────────────────────────────────────────────────┐
│  User grants Accessibility permission (onboarding step 3)  │
└─────────────────────┬───────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  AXObserver watches Mail.app / Messages / Slack / Discord   │
│  ONLY on SEND action (⌘Enter, Send button click)           │
│  Captures: final composed text (not keystrokes)             │
└─────────────────────┬───────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  On-device processing (background, utility QoS):            │
│  1. Strip quoted text, signatures, headers                  │
│  2. Extract final 1-2 sentences (likely the signoff)        │
│  3. Update VoiceProfile incrementally (online learning)     │
│  4. Encrypt & persist to SwiftData                          │
└─────────────────────┬───────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  Next generation: VoiceProfile injected into FMF prompt    │
│  "Voice: [profile summary]" → model matches your rhythm    │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 Privacy Guarantees (Non-Negotiable)
- ❌ **No keystroke logging** — only final sent messages
- ❌ **No cloud sync** — VoiceProfile lives in app sandbox
- ❌ **No analytics** — not even local MetricKit
- ✅ **User can reset** VoiceProfile anytime (Settings → Privacy → "Reset My Voice")
- ✅ **User can pause** observation (menu bar → "Pause Learning")
- ✅ **Transparent** — "What I've Learned" panel shows extracted patterns (no raw text)

---

## 6. Product Surfaces & Brand Expression

### 6.1 Menu Bar Item (The Entry Point)
```
┌────────────────────────────────────┐
│  [signature icon]  ← template,    │
│   amber underline animates       │
│   on first launch (600ms)        │
└────────────────────────────────────┘
Tooltip: "Signoff — Press ⌃⌘` to open, ⌃⌘1–6 for buckets"
Right-click: Generate / Copy Last / Settings / Help / Re-run Onboarding / Quit
```

### 6.2 Popover — The Core Surface (372pt ideal width)

```
┌────────────────────────────────────────────────────────────┐
│  ╭─────╮  Signoff                    [🔒] Privacy Badge   │
│  │ sig │  On-device email signoffs                          │
│  ╰──┬──╯                                                    │
├────────────────────────────────────────────────────────────┤
│  [Professional ▼]  [Standard]  [Unhinged]  [Custom]  [⋯]   │  Bucket strip
│  ◼  Professional      balanced                              │  (selected = amber
│  ⬜  Standard         conversational                        │   underline + check)
│  ⬜  Unhinged         deranged                               │
│  ⬜  Custom           your rules                             │
├────────────────────────────────────────────────────────────┤
│  [Generate ◐]              [Copy]          [⌃⌘1]           │
├────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Appreciate the clarity on this.                     │  │  Signoff card
│  │  —                                                   │  │  (monospace, 15pt,
│  │  A. Patel                                            │  │   amber period)
│  └──────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────┤
│  🟢 Neural engine ready  •  0.8s  •  847 signoffs         │  Status line
└────────────────────────────────────────────────────────────┘
```

**Key Brand Moments in Popover:**
1. **Bucket strip** — amber underline on selected bucket = "this is your register"
2. **Generate button** — amber prominent, signature symbol, pulses while neural engine works
3. **Signoff card** — elevated surface, monospace text, amber period = "the mark"
4. **Status line** — "Neural engine ready" not "AI ready" — owns the hardware

### 6.3 Settings Window — The Control Center

**Toolbar Panes (native macOS Settings style):**

| Pane | Brand Expression |
|------|-----------------|
| **General** | Clean, functional. "Show in Menu Bar" toggle with "Quit" link when off. |
| **Profile** | 7 fields. Self-description (500 chars) = "Voice context for neural engine." |
| **Buckets** | Per-bucket cards. Emoji toggle. CYNICAL gate (Unhinged only). Duplicate → Custom. |
| **Shortcuts** | Recorder UI. Conflict banner. ⌃⌘ / ⌥⌘ modifier toggle. |
| **Privacy** | **Hero panel.** FM status badge. VoiceProfile viewer ("What I've Learned"). Reset button. Apple Intelligence deep link. |
| **Advanced** | Verbose logging. Re-run onboarding. Help links. |

**Privacy Pane — The Brand Centerpiece:**
```
┌────────────────────────────────────────────────────────────┐
│  🔒 Privacy & Intelligence                                 │
├────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Apple Intelligence Status:  ● Ready                 │  │
│  │  Your Mac's Neural Engine is generating signoffs     │  │
│  │  locally. No data leaves this device.                │  │
│  │  [Open Apple Intelligence Settings…]                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  What I've Learned (VoiceProfile)                    │  │
│  │  ─────────────────────────────────────────────────   │  │
│  │  Formality: ████████░░ 72%  (Professional register)  │  │
│  │  Avg. sentence: 14.2 words                          │  │
│  │  Punctuation: . 78%  ! 15%  ? 7%                    │  │
│  │  Emoji use: 12%                                     │  │
│  │  Common closers: "Thanks," "Appreciate it," "On it."│  │
│  │                                                       │  │
│  │  [View Raw Profile…]  [Reset My Voice]               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Learning Status:  ● Active  [Pause Learning]        │  │
│  │  Observes sent messages in Mail, Messages, Slack     │  │
│  │  to refine your voice profile. Never reads drafts.   │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

### 6.4 Onboarding — The Silent Intelligence Setup

**5 Steps, each with purpose:**

| Step | Title | Content | Brand Moment |
|------|-------|---------|--------------|
| 1 | Welcome | "Your Mac's neural engine can write your signoffs. Let's teach it your voice." | Animated signature writing itself |
| 2 | Profile | Name + Self-description (500 chars). "How do you sound?" | Live preview: "With your voice: 'Appreciate the clarity.' Without: 'Best regards.'" |
| 3 | Accessibility | "To paste signoffs at your cursor, Signoff needs Accessibility permission." | Demo: generates → pastes in fake text field |
| 4 | Input Monitoring | "For global shortcuts (⌃⌘1–6) to work anywhere." | Shows shortcut diagram |
| 5 | Bucket Tour | Horizontal scroll through 5 buckets with live FMF examples | Each bucket generates a real signoff on-device during onboarding |

**Completion:** "Your neural engine knows your voice. Press ⌃⌘` anywhere."

---

## 7. Keyboard Shortcuts — Muscle Memory

| Shortcut | Action | Bucket |
|----------|--------|--------|
| ⌃⌘` | Open popover | — |
| ⌃⌘1 | Generate + paste | Professional |
| ⌃⌘2 | Generate + paste | Standard |
| ⌃⌘3 | Generate + paste | Unhinged |
| ⌃⌘4 | Generate + paste | Custom |
| ⌃⌘5 | Generate + paste | Footer |
| ⌃⇧C | Copy last signoff | — |

**Conflict Resolution:** Settings → Shortcuts shows ⚠️ banner with "Switch all to ⌥⌘" one-click fix.

---

## 8. Error States — Honest, Actionable

| Scenario | Title | Message | Action |
|----------|-------|---------|--------|
| FM not enabled | "Apple Intelligence Off" | "Signoff runs on your Mac's neural engine. Enable Apple Intelligence in System Settings." | [Open Settings] |
| Model downloading | "Neural Engine Preparing" | "Apple Intelligence is downloading the on-device model. Try again in a few minutes." | [Check Again] |
| Ineligible Mac | "Unsupported Hardware" | "Foundation Models requires Apple Silicon (M-series). This Mac isn't eligible." | — |
| Generation failed | "Generation Failed" | "The neural engine returned an error. Try again?" | [Retry] |
| Permissions missing | "Can't Auto-Paste" | "Grant Accessibility permission to paste signoffs automatically." | [Open Settings] |

**Never** show a generic "Error" — always tell them *what* failed and *how to fix it*.

---

## 9. Non-Negotiable Brand Rules

1. **Never say "AI"** — Say "neural engine," "on-device intelligence," "Foundation Models"
2. **Never show fallback phrases** — If FMF fails, show error card. No "Best regards" backup.
3. **Amber only on the mark** — No amber buttons elsewhere. No amber text. Only the signature underline and Generate button.
4. **Monospace for signoffs** — The preview card is *always* monospace. It's a signature, not body text.
5. **Popover stays open after generate** — User can generate again, switch buckets, copy. Close on click-out or Esc.
6. **VoiceProfile is user-visible** — "What I've Learned" panel in Privacy. Transparency builds trust.
7. **Onboarding is replayable** — Settings → Advanced → "Re-run Onboarding"
8. **No empty states without actions** — Every empty state has a primary button.
9. **Reduce Motion / Transparency respected** — Always. No exceptions.
10. **Sparkle updates** — Silent background check. "What's New" in Help menu.

---

## 10. Implementation Priorities (Brand-Aligned)

### P0 — Brand Foundation (Week 1)
- [ ] VoiceProfile SwiftData model + encryption
- [ ] AXObserver silent learning engine (background, utility QoS)
- [ ] Privacy pane with "What I've Learned" panel
- [ ] Amber accent system + signature mark component
- [ ] Monospace signoff preview card

### P1 — Core Experience (Week 2)
- [ ] Popover with bucket strip, generate, preview, status line
- [ ] Global shortcuts (⌃⌘` + ⌃⌘1-6) with conflict resolution
- [ ] Onboarding flow (5 steps, replayable)
- [ ] Settings window (all 6 panes)
- [ ] FMF availability + error cards with deep links

### P2 — Polish (Week 3)
- [ ] Bucket selection animation (amber underline slide)
- [ ] Signoff reveal animation (slide up + fade)
- [ ] Generate button pulse during FMF call
- [ ] "What I've Learned" raw JSON viewer
- [ ] Reset VoiceProfile with confirmation
- [ ] Pause Learning toggle in menu bar

### P3 — Voice Maturity (Week 4+)
- [ ] VoiceProfile v2: n-gram + embedding similarity
- [ ] Per-bucket voice adaptation (formal vs casual registers)
- [ ] Export/import VoiceProfile (encrypted, user-initiated)
- [ ] "Sounds like me" thumbs up/down on generations → RLHF-style local preference

---

## 11. The Brand in One Screen

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│     ╭─────────────────────────────────────────────────────╮    │
│     │  Your Mac's neural engine                            │    │
│     │  just wrote your signoff.                            │    │
│     │                                                      │    │
│     │  "Appreciate the clarity on this."                  │    │
│     │  — A. Patel                                          │    │
│     │                                                      │    │
│     │  ● Neural engine ready  •  0.8s  •  847 signoffs    │    │
│     ╰─────────────────────────────────────────────────────╯    │
│                                                                 │
│     The mark you leave. Written by your device.                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Appendix: Brand Asset Checklist

- [ ] App icon (all sizes, template + colored variants)
- [ ] SignatureMark SwiftUI component (reusable)
- [ ] Amber color extension (`Brand.amber(for: ColorScheme)`)
- [ ] Monospace signoff preview style
- [ ] Bucket strip selection animation
- [ ] ErrorFixCard with FMF deep links
- [ ] VoiceProfile SwiftData model + encryption
- [ ] AXObserver learning engine
- [ ] Privacy pane "What I've Learned" view
- [ ] Onboarding 5-step flow with live FMF generation
- [ ] Settings 6-pane layout
- [ ] Shortcut recorder with conflict UI
- [ ] Sparkle integration + What's New
- [ ] Accessibility audit (VoiceOver, Switch Control, Reduce Motion)

---

*Signoff — The mark you leave. Written by your Mac's neural engine.*