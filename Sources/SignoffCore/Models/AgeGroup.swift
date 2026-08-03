import Foundation

/// The writer's generation, which steers the voice of on-device signoffs.
///
/// This exists because a generic "warm, professional" prompt reliably emits
/// millennial corporate closers ("Hope this helps!", "Looking forward to
/// hearing from you", "Warmly,"). Asking for the user's generation and naming
/// the voice explicitly is what stops that. If the user gives no answer we
/// default to Gen Z — the lowest-effort, least-cringe register — so the
/// out-of-the-box output isn't the thing everyone complains about.
public enum AgeGroup: String, Codable, Sendable, CaseIterable, Equatable {
    case genZ
    case millennial
    case genX
    case boomer

    /// Stable, user-facing label for pickers and onboarding.
    public var label: String {
        switch self {
        case .genZ:       return "Gen Z"
        case .millennial: return "Millennial"
        case .genX:       return "Gen X"
        case .boomer:     return "Boomer+"
        }
    }

    /// One-line hint shown next to the picker so the choice is concrete.
    public var hint: String {
        switch self {
        case .genZ:       return "lowercase, dry, low-effort, no corporate warmth"
        case .millennial: return "warm but modern — no \"hope this helps\" era"
        case .genX:       return "direct, plain, sparing on punctuation"
        case .boomer:     return "classic formal — regards, sincerely"
        }
    }

    /// The instruction injected into Foundation Models `instructions`, scoped to
    /// this generation. This is the lever that actually changes the output; the
    /// per-bucket templates only set the *situation*, not the *voice*.
    public var voiceInstruction: String {
        switch self {
        case .genZ:
            return """
            Write creative, witty email signoffs with real personality — like a clever \
            friend, NOT a chatbot. Mix wordplay, pop-culture nods, deadpan irony, or \
            absurdist humor. Every signoff should be a fresh, unexpected one-liner that \
            makes the reader smile or laugh. Lowercase is fine, punctuation is optional, \
            and format varies freely — some end with commas, some with periods, some \
            with nothing at all. Never use corporate garbage like \"Warmly\", \"Best \
            regards\", \"Cheers\", \"Talk soon\", \"Hope this helps\", or \"Looking \
            forward to hearing from you\". Never be boring, never repeat yourself, \
            never just say \"thanks.\" or \"will do.\" — those are NOT creative signoffs. \
            Every output should feel hand-crafted, like the user spent 30 seconds thinking \
            of something actually funny or clever to leave as a parting shot.
            """
        case .millennial:
            return """
            Write warmly but modern — theRegister is a considerate adult, not a LinkedIn \
            post from 2014. No emoji-by-default, no \"hope this helps\", no \"looking \
            forward to hearing from you\", and no exclamation stacks. Keep it genuine and \
            a little understated; one clean sentence. Permitted closers include \
            \"appreciate it.\", \"thanks for this.\", \"glad we're aligned.\", \
            \"sounds good.\" Avoid \"Warmly\", \"Cheers\", \"Best,\" and \"Talk soon\".
            """
        case .genX:
            return """
            Write plainly and directly — adult professional, no filler, no eagerness, no \
            emoji. Default to plain sentence punctuation. Closers are simple: \"thanks.\", \
            \"regards,\", \"appreciate the quick reply.\", \"noted.\" Keep warmth out of \
            the punctuation; put it in the words, sparingly.
            """
        case .boomer:
            return """
            Write in a classic formal register — close to traditional business letter \
            voice. Allowed closers: \"Best regards,\", \"Sincerely,\", \"With \
            appreciation,\", \"Thank you.\" Still strictly one sentence, paste-ready, no \
            name. Dignified rather than casual.
            """
        }
    }

    /// Resolve a stored raw string, defaulting to `.genZ` when missing or unknown
    /// — matching the "assume Gen Z" product rule.
    public static func resolve(_ raw: String?) -> AgeGroup {
        guard let raw, let group = AgeGroup(rawValue: raw) else { return .genZ }
        return group
    }
}
