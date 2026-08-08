import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Guided generation schema for on-device signoffs.
/// Kept deliberately narrow — one field — so the model stays focused on the
/// phrase itself; tone / bucket constraints live in Instructions + Prompt.
@available(macOS 26, *)
@Generable(description: "A short email signoff phrase.")
public struct SignoffOutput: Sendable {
    @Guide(description: "A short, witty email signoff ending with exactly one comma. 3 to 8 words. Capitalize only the first word. No internal punctuation. No quotes, no emoji. Just the signoff phrase.")
    public var text: String
}
#endif