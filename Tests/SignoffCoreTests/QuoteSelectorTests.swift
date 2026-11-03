import Testing
@testable import SignoffCore

struct QuoteSelectorTests {
    @Test("quote selector returns a verified template reference")
    func returnsTemplateReference() {
        let template = PromptTemplate(
            system: "quotes",
            userVariants: [],
            positiveExamples: ["May the Force be with you,", "I'll be back,"])
        let result = QuoteSelector.select(from: template, avoiding: [])
        #expect(result == "May the Force be with you," || result == "I'll be back,")
    }

    @Test("quote selector avoids recent references before cycling")
    func avoidsRecentReferences() {
        let template = PromptTemplate(
            system: "quotes",
            userVariants: [],
            positiveExamples: ["May the Force be with you,", "I'll be back,"])
        let result = QuoteSelector.select(from: template, avoiding: ["May the Force be with you,"])
        #expect(result == "I'll be back,")
    }

    @Test("quote selector cycles after every reference was used")
    func cyclesWhenExhausted() {
        let template = PromptTemplate(
            system: "quotes",
            userVariants: [],
            positiveExamples: ["May the Force be with you,"])
        let result = QuoteSelector.select(from: template, avoiding: ["May the Force be with you,"])
        #expect(result == "May the Force be with you,")
    }
}
