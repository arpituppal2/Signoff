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
    @Guide(description: "A single short email signoff of 3–14 words ending with . ! or ?. No quotes, no recipient name, no markdown, no leading 'I'.")
    public var text: String
}
#endif
