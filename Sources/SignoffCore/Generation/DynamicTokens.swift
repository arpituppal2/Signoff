import Foundation

/// Dynamic placeholder tokens usable inside prompt-template example strings
/// (e.g. unhinged.json's "Not built for {weekday},").
///
/// These are resolved at TEMPLATE LOAD time (so every downstream consumer —
/// prompt prefix, register few-shots, curated examples — sees concrete text)
/// and again on OUTPUT (so the model literally echoing the token still
/// surfaces a valid signoff). Professional's closed-vocabulary gate is
/// unaffected: its menu contains no tokens.
///
/// Deliberately tiny: tokens are *style hooks*, not a serving corpus — the
/// model still generates the line fresh each time.
public enum DynamicTokens: String, CaseIterable, Sendable {
    /// Today's weekday name, e.g. "Thursday". Lets the template carry a
    /// "Not built for {weekday}," anchor without any per-day hardcoding.
    case weekday = "{weekday}"

    public static func resolve(_ text: String, date: Date = Date(), calendar: Calendar = .current) -> String {
        guard text.contains("{") else { return text }
        var resolved = text
        for token in DynamicTokens.allCases {
            guard resolved.contains(token.rawValue) else { continue }
            let replacement: String
            switch token {
            case .weekday:
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = calendar
                formatter.dateFormat = "EEEE"
                replacement = formatter.string(from: date)
            }
            resolved = resolved.replacingOccurrences(of: token.rawValue, with: replacement)
        }
        return resolved
    }
}

extension PromptTemplate {
    /// Resolve dynamic tokens across every example-bearing field. The template
    /// cache stores the RAW decoded template so a long-running app picks up a
    /// new weekday without a relaunch; resolution happens per `load` call.
    public func resolvingDynamicTokens() -> PromptTemplate {
        PromptTemplate(
            system: system,
            userVariants: userVariants.map { variant in
                .init(when: variant.when, user: DynamicTokens.resolve(variant.user))
            },
            positiveExamples: positiveExamples.map { DynamicTokens.resolve($0) },
            registers: registers.map { list in
                list.map { register in
                    PromptTemplate.Register(
                        name: register.name,
                        cue: register.cue,
                        examples: register.examples.map { DynamicTokens.resolve($0) })
                }
            })
    }
}
