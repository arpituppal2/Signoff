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
    @Guide(description: "One short signoff phrase. No explanation, label, or quotation marks.")
    public var text: String
}
#endif