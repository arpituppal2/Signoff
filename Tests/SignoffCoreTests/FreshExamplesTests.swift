import Testing
import Foundation
@testable import SignoffCore

/// Tests for web-harvested fresh examples and dynamic tokens.
/// Pure functions only — no network in unit tests.
struct FreshExamplesTests {

    // MARK: - Candidate extraction

    @Test("Extraction pulls signoff-shaped lines from messy page text")
    func extractionFromMessyText() {
        let page = """
        Here are some funny email signoffs people love:
        1. All fax, no printer,
        2. Sent from my pizza box
        - Please hesitate to reach out.
        "With queso on top,"
        Someone's actual signature below this line.
        """
        let lines = FreshExamplesFilter.candidateLines(from: page)
        #expect(lines.contains("All fax, no printer,"))
        #expect(lines.contains("Sent from my pizza box"))
        #expect(lines.contains("Please hesitate to reach out"))
        #expect(lines.contains("With queso on top,"))
    }

    // MARK: - Filtering

    @Test("Filter drops meta-discussion, links, wrong shape, and dedupes")
    func filterDropsJunk() {
        let input = [
            "A list of the best email signoffs",        // meta
            "Check out https://example.com/funny",      // link
            "I laughed so hard at this thread",         // meta + wrong shape
            "All fax, no printer",                      // good
            "all fax, no printer",                      // dupe (case)
            "Sent from my last three brain cells",      // good
            "Q",                                        // too short
            "This is a very long line that keeps going and going and going far past any reasonable signoff length limit", // too long
            "the mountain was quietly judging everyone",// lowercase start
        ]
        let out = FreshExamplesFilter.filter(input, existing: [])
        #expect(out.contains("All fax, no printer,"))
        #expect(out.contains("Sent from my last three brain cells,"))
        #expect(out.count == 2)
    }

    @Test("Filter respects existing pool (no duplicates across refreshes)")
    func filterDedupesAgainstExisting() {
        let existing: Set<String> = ["all fax, no printer,"]
        let out = FreshExamplesFilter.filter(["All fax, no printer", "With queso on top"], existing: existing)
        #expect(out == ["With queso on top,"])
    }

    @Test("Filter formats with trailing comma and capitalizes nothing it should not")
    func filterFormats() {
        let out = FreshExamplesFilter.filter(["Sent from my pizza box"], existing: [])
        #expect(out == ["Sent from my pizza box,"])
    }

    // MARK: - Dynamic tokens

    @Test("Weekday token resolves to an English weekday name")
    func weekdayTokenResolves() {
        let resolved = DynamicTokens.resolve("Not built for {weekday},")
        #expect(!resolved.contains("{weekday}"))
        #expect(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            .contains(resolved.replacingOccurrences(of: "Not built for ", with: "").replacingOccurrences(of: ",", with: "")))
    }

    @Test("Templates resolve tokens at load time")
    func templateLoadResolvesTokens() async {
        let template = await PromptTemplate.load(bucket: BucketID.unhinged.rawValue)
        #expect(template != nil)
        // No token survives loading, anywhere.
        let all = (template?.positiveExamples ?? []) + (template?.registers ?? []).flatMap(\.examples)
        #expect(all.contains(where: { $0.contains("Not built for ") }))
        #expect(!all.contains(where: { $0.contains("{weekday}") }))
    }

    @Test("PostProcessor resolves a literal token echo in output")
    func postProcessorResolvesEcho() {
        let snapshot = UserProfileSnapshot()
        let out = PostProcessor.appendFooter("Not built for {weekday},", profile: snapshot, mode: .nothing)
        #expect(!out.contains("{weekday}"))
        #expect(out.hasSuffix(","))
    }
}
