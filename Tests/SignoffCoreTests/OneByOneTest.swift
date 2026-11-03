import Testing
import Foundation
@testable import SignoffCore

/// One-by-one quality harness — **the human is the validator, one at a time.**

/// Produces EXACTLY ONE raw generation per invocation and exits. No loop, no
/// batching, no buffer: the human reads the single printed line, fully analyzes
/// it against the CEO / Universal / Redundancy rules, THEN triggers the next
/// invocation.

/// State across invocations is a temp-file dir (`/tmp/signoff-1x1`):
///  - `<bucket>.json`  : recent good closers fed back as context (prevents ruts)
///  - `<bucket>.streak`: current accepted-in-a-row count (drives tone cycling)
///
@MainActor
@Suite(.serialized)
struct OneByOneTest {
    private let service = GenerationService.shared
    // private let validator = SignoffQualityValidator.shared   // hint-only

    private let targetCount = 50
    private let onlyBucket: String? = "standard"  // only test standard bucket
    private let historyDir = "/tmp/signoff-1x1"
    private let tones = [0.5, 0.8, 1.0]
    // Deterministic register rotation forces the on-device 3B model out of
    // single-voice fixation ruts. The 3B model structurally collapses the
    // other archetypes to ONE formula each, ignoring all anti-twin instructions:
    //   - mock-epic-melodrama       → "[Dramatic noun] has [verb] your [food]"
    //   - dad-joke-pun              → rhymes on "All [X] no [Y]" or literal food names
    //   - fake-mythologizing        → "[Verb] by [noun-salad]"
    //   - theatrical-overstatement  → straight-faced doom
    // Per the user's framework, negative suppression does NOT break a 3B
    // fixation (pink-elephant effect); the right move is to restrict rotation
    // to voices that demonstrably produce clean, varied, real-phrase output.
    //
    // 2 voices remain, but they are NOT equal. Observed per-turn reliability
    // (bounded mechanical-gate retry active):
    //   - deadpan-closer          ~70% — reliably emits a real twist across its
    //                                  3 veins (authorship / officeism / odd
    //                                  signoff). THE workhorse. Produces
    //                                  "Not crafted by my calculator,"
    //                                  "Signed in silence,".
    //   - pop-culture-catchphrase ~10% — the 3B cannot reliably produce
    //                                  *widely recognizable* multi-word
    //                                  references; emits faux-references
    //                                  ("The cheese is alive,") and
    //                                  context-flavored imperatives ("Eat
    //                                  your vegetables,"). Most turns waste.
    // The cycle is weighted deadpan 2:1 so the workhorse gets 2 of every 3
    // turns and the weaker voice still gets periodic turns (so it can't go
    // stale and still occasionally lands a real catchphrase like "Bazinga,"
    // / "Cowabunga,"). Re-weight or re-add a dropped voice only if observed
    // reliability shifts.
    private let standardRegisterCycle = [
        "deadpan-closer",
        "deadpan-closer",
        "pop-culture-catchphrase",
    ]

    // ---- temp-file helpers -------------------------------------------------

    private func streakURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket).streak")
    }

    private func historyURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket).json")
    }

    // Per-roll invocation counter — advances on EVERY invocation (accept OR
    // reject), unlike history length (which only grows on an accept). Without
    // this, a reject streak freezes the cycle index (pegged to history length)
    // onto one register and hammers it forever — observed: catchphrase fed 5
    // times in a row while the stronger deadpan-closer never got a turn. The
    // counter gives every voice a fair rotation even across long reject runs.
    private func rollURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket).roll")
    }

    // NOTE (revision): an earlier cross-invocation recent-REJECTS memory was
    // considered here but the harness only sees the single SURFACED candidate
    // — not the bounded retry's internal rejects — so it can't record them.
    // The cross-invocation reject memory now lives INSIDE generateRaw (where
    // the internal rejects are visible), persisted to
    // `/tmp/signoff-1x1/<bucket>.recentrejects` and primed into each
    // invocation's effectiveRecent. See the comment block there.
    private func recentRejectsURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket).recentrejects")
    }

    private func currentRoll(_ bucket: String) -> Int {
        guard let s = try? String(contentsOf: rollURL(bucket)).trimmingCharacters(in: .whitespacesAndNewlines),
              let n = Int(s) else { return 0 }
        return n
    }

    private func bumpRoll(_ bucket: String) {
        let n = currentRoll(bucket) + 1
        try? "\(n)".write(to: rollURL(bucket), atomically: true, encoding: .utf8)
    }

    private func currentStreak(_ bucket: String) -> Int {
        guard let s = try? String(contentsOf: streakURL(bucket)).trimmingCharacters(in: .whitespacesAndNewlines),
              let n = Int(s) else { return 0 }
        return n
    }

    private func loadHistory(_ bucket: String) -> [String] {
        let url = historyURL(bucket)
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return Array(arr.suffix(60))
    }

    private func appendHistory(_ text: String, _ bucket: String) {
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: historyDir),
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        var arr = loadHistory(bucket)
        arr.append(text)
        if arr.count > 60 { arr.removeFirst(arr.count - 60) }
        try? JSONSerialization.data(withJSONObject: arr).write(to: historyURL(bucket))
    }

    // ---- single generation --------------------------------------------------

    @Test("One-by-one: single raw generation for human judgment")
    func oneByOneSingleRaw() async throws {
        await warmup()

        let bucketIds: [String] = onlyBucket.map { [$0] } ?? ["professional", "unhinged", "standard"]

        // Emit exactly ONE raw generation for the next pending streak slot.
        for bucket in bucketIds {
            let streak = currentStreak(bucket)
            guard streak < targetCount else {
                print("[\(bucket.uppercased())] DONE — \(targetCount) in a row accepted.")
                continue
            }
            let recent = loadHistory(bucket)
            let toneValue = tones[streak % tones.count]
            // Rotate preferred register to break single-voice fixation ruts.
            // Peg the index to a per-roll counter bumped on EVERY invocation
            // (accept OR reject) — NOT history length, which only grows on an
            // accept and would freeze the cycle onto one register during a
            // reject streak (observed: catchphrase hammered 5× in a row while
            // deadpan-closer never got a turn). The counter survives resets
            // and guarantees each voice an equal rotation.
            let cycleIndex = currentRoll(bucket)
            bumpRoll(bucket)
            let preferredRegister: String? = (bucket == "standard")
                ? standardRegisterCycle[cycleIndex % standardRegisterCycle.count]
                : nil

            // NOTE: an earlier "STYLE DIVERGE: these objects are overused —
            // banana, umbrella, …" directive here was REMOVED. Naming the
            // overused nouns produced the textbook pink-elephant effect: roll 5
            // of the test batch emitted "Banana peel under the umbrella," —
            // BOTH named nouns in one output. The 3B model foregrounds whatever
            // is named, even as "diverge-from." Suppression of latent noun
            // fixations must stay NOUN-AGNOSTIC; we rely on the gate's skeleton
            // collision + validator fingerprints + the recent-signoffs style
            // list. Bare-noun salad will occasionally surface and reset the
            // streak; that's honest.

            if #available(macOS 26, *) {
                let result = await service.generateRaw(
                    bucketId: bucket, profile: nil,
                    recentTexts: recent, toneValue: toneValue,
                    customInstructions: nil,
                    preferredRegister: preferredRegister)
                switch result {
                case .success(let outcome):
                    let text = outcome.text
                    let slot = streak + 1
                    let regTag = preferredRegister.map { " {" + $0 + "}" } ?? ""
                    print("[\(bucket.capitalized)] CANDIDATE #\(slot)/\(targetCount)\(regTag) | \"\(text)\"")
                    // PAUSE: human evaluation required. Test exits with status 0
                    // to allow external interaction. Manually update state files
                    // based on evaluation:_accept (save+streak++) or _reject (streak=0, log reject).
                    // Reset state manually after rejection and re-run test.
                case .providerFailed(let reason):
                    print("[\(bucket.capitalized)] PROVIDER-HICCUP (NOT a reset — retry next invocation) | \(reason)")
                case .usageLimitReached:
                    print("[\(bucket.capitalized)] USAGE-LIMIT (retry next invocation)")
                }
            } else {
                print("[\(bucket.uppercased())] FMF requires macOS 26+")
            }
        }
    }

    private func warmup() async {
        print("[1x1] FMF probe: \(FoundationModelsAvailability.probe())")
        if #available(macOS 26, *) {
            await FoundationModelsSessionPool.shared.invalidateAll()
        }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 100_000_000)
        print("[1x1] After warmup FMF probe: \(FoundationModelsAvailability.probe())")
    }
}

private extension OneByOneTest {
    /// Convenience to advance the streak file by one after a human ACCEPT verdict.
    static func accept(_ bucket: String) {
        // invoked externally via a helper target; kept as documentation of intent
    }
}