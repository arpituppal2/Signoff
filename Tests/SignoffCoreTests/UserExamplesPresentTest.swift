import Testing
import Foundation
@testable import SignoffCore

@Suite struct UserExamplesPresentTest {
    @Test func allUserExamplesInUnhingedBank() async throws {
        let template = await PromptTemplate.load(bucket: BucketID.unhinged.rawValue) ?? .fallback
        let bank = template.positiveExamples
            .map { ProviderResponseGuard.sanitizeSignoff($0) }
            .map(normalize)
        let set = Set(bank)

        let user = [
            "All fax, no printer", "Please hesitate to reach out",
            "Sent from my last 3.5 brain cells", "With all due respect and a little bit of jest",
            "No cheers, only tears", "With queso on top", "Remember the name", "Smell ya later",
            "Sprinkled with vibes", "Alright, alright, alright", "Thanking you, dearest one",
            "On my tippy toes", "Not built for", "I have spoken", "Hasta la pasta",
            "We ride at dawn", "Sent from my pillow fort", "Sent while contemplating waffles",
            "Somehow still here like the Fast and Furious Franchise", "Insincerely",
            "You just lost The Game", "Keep climbing your mountains", "Not sent from my fridge",
            "Sent with the poison, the poison for Kuzco", "Living the dream", "From the trenches",
            "No espresso, all depresso", "Foaming at the mouth", "From the pits of hell",
            "Putting the fun in dysfunctional", "On all fours", "I take tips",
        ]
        var missing: [String] = []
        for line in user {
            // The user wrote some examples with placeholder tails ("Not built for
            // [weekday]", "I take tips, my Venmo is ____"). Match by containment:
            // the bank has the full line ("Not built for {weekday},") whose
            // normalized form contains the normalized user phrase.
            let n = normalize(line)
            if !bank.contains(where: { $0.contains(n) }) { missing.append(line) }
        }
        #expect(missing.isEmpty, "Missing from unhinged bank: \(missing)")
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
