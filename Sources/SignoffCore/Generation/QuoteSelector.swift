import Foundation

/// Selects an approved phrase for the Quotes / Unhinged buckets.
///
/// Foundation Models is not used to fact-check or invent these lines. The
/// template's references are the verified offline set. Selection prefers
/// never-used lines first (randomized among them), then falls back to the
/// least-recently-seen line once the whole bank has been used, so the rotation
/// keeps advancing instead of locking onto one phrase.
public enum QuoteSelector {
    public static func select(from template: PromptTemplate, avoiding recent: [String]) -> String? {
        let candidates = template.positiveExamples
            .map { ProviderResponseGuard.sanitizeSignoff($0) }
            .filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return nil }

        let recentNormalized = recent.map { normalize($0) }
        let recentSet = Set(recentNormalized)

        // Never-used lines are always preferred. Randomize among them so a
        // session doesn't replay the same day-rotation order every day.
        let unseen = candidates.filter { !recentSet.contains(normalize($0)) }
        if !unseen.isEmpty {
            return unseen[Int.random(in: 0..<unseen.count)]
        }

        // Whole bank has been used recently: pick the least-recently-seen line.
        // Re-using and re-appending it makes the next-least-recent line win next
        // time, so selection rotates through the bank rather than locking.
        return candidates.min { a, b in
            mostRecentPosition(a, in: recentNormalized) < mostRecentPosition(b, in: recentNormalized)
        }
    }

    /// Index of the most-recent occurrence of `candidate` in `recent`
    /// (oldest-first order), or -1 if never present.
    private static func mostRecentPosition(_ candidate: String, in recent: [String]) -> Int {
        let n = normalize(candidate)
        for (i, r) in recent.enumerated().reversed() {
            if r == n { return i }
        }
        return -1
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}