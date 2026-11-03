import Testing
import Foundation
@testable import SignoffCore

/// Unit tests for the validation pipeline (sanitize, length, guard words)
@MainActor
struct ValidationPipelineTests {

    // MARK: - sanitizeSignoff Tests

    @Test("sanitizeSignoff removes trailing period after comma")
    func sanitizeRemovesTrailingPeriod() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards,.")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff removes trailing exclamation after comma")
    func sanitizeRemovesTrailingExclamation() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards,!")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff removes trailing question mark after comma")
    func sanitizeRemovesTrailingQuestionMark() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards,?")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff handles trailing period with space")
    func sanitizeHandlesPeriodWithSpace() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards, .")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff strips standalone trailing period")
    func sanitizeStripsStandalonePeriod() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards.")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff strips standalone trailing exclamation")
    func sanitizeStripsStandaloneExclamation() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards!")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff strips standalone trailing question mark")
    func sanitizeStripsStandaloneQuestionMark() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards?")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff collapses double trailing commas")
    func sanitizeCollapsesDoubleCommas() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards,,")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff ensures trailing comma when missing")
    func sanitizeEnsuresTrailingComma() {
        let result = ProviderResponseGuard.sanitizeSignoff("Best regards")
        #expect(result == "Best regards,")
    }

    @Test("sanitizeSignoff handles multi-line input by taking first line")
    func sanitizeHandlesMultiLine() {
        let result = ProviderResponseGuard.sanitizeSignoff("Line one\nLine two,")
        #expect(result.hasSuffix(","))
    }

    @Test("validatedPasteable rejects leaked formatting instructions")
    func pasteableRejectsFormattingLeak() async throws {
        do {
            try ProviderResponseGuard.validatedPasteable("Hope this resonates, Comma,", provider: "FMF")
            Issue.record("Expected formatting artifact to be rejected")
        } catch let error as GenerationError {
            #expect(error == .unsafeCandidate(reason: "formatting instruction leaked into output"))
        }
    }

    // MARK: - validatedPasteable Tests

    @Test("validatedPasteable rejects empty string")
    func pasteableRejectsEmpty() {
        #expect(throws: GenerationError.unsafeCandidate(reason: "empty FMF response")) {
            try ProviderResponseGuard.validatedPasteable("", provider: "FMF")
        }
    }

    @Test("validatedPasteable rejects whitespace-only string")
    func pasteableRejectsWhitespace() {
        #expect(throws: GenerationError.unsafeCandidate(reason: "empty FMF response")) {
            try ProviderResponseGuard.validatedPasteable("   \n\t  ", provider: "FMF")
        }
    }

    @Test("validatedPasteable accepts valid signoff")
    func pasteableAcceptsValid() {
        let result = try! ProviderResponseGuard.validatedPasteable("Best regards,", provider: "FMF")
        #expect(result == "Best regards,")
    }

    @Test("validatedPasteable rejects AI refusal")
    func pasteableRejectsRefusal() async throws {
        do {
            try ProviderResponseGuard.validatedPasteable("I can't help with that", provider: "FMF")
            Issue.record("Expected refusal error")
        } catch let error as GenerationError {
            #expect(error == .refused(reason: "I can't help with that"))
        }
    }

    @Test("validatedPasteable rejects 'I cannot help'")
    func pasteableRejectsCannotHelp() async throws {
        do {
            try ProviderResponseGuard.validatedPasteable("I cannot help", provider: "FMF")
            Issue.record("Expected refusal error")
        } catch let error as GenerationError {
            #expect(error == .refused(reason: "I cannot help"))
        }
    }

    @Test("validatedPasteable rejects 'As an AI'")
    func pasteableRejectsAsAnAI() async throws {
        do {
            try ProviderResponseGuard.validatedPasteable("As an AI, I don't do that", provider: "FMF")
            Issue.record("Expected refusal error")
        } catch let error as GenerationError {
            #expect(error == .refused(reason: "As an AI, I don't do that"))
        }
    }

    // MARK: - validatedLength Tests

    @Test("validatedLength rejects empty string")
    func lengthRejectsEmpty() async throws {
        do {
            try ProviderResponseGuard.validatedLength("")
            Issue.record("Expected guardrail error")
        } catch let error as GenerationError {
            #expect(error == .guardrailViolation(reason: "Output too short"))
        }
    }

    @Test("validatedLength accepts 1 word")
    func lengthAcceptsOneWord() {
        let result = try! ProviderResponseGuard.validatedLength("Thanks,")
        #expect(result == "Thanks,")
    }

    @Test("validatedLength accepts 7 words")
    func lengthAcceptsSevenWords() {
        let result = try! ProviderResponseGuard.validatedLength("Best regards and good luck to you,")
        #expect(result == "Best regards and good luck to you,")
    }

    @Test("validatedLength rejects 9 words")
    func lengthRejectsNineWords() async throws {
        // The guardrail caps at <= 8 words (unhinged ceiling). 8 passes; 9
        // is the first rejection. Test that boundary.
        do {
            try ProviderResponseGuard.validatedLength("Best regards and good luck to you always now,")
            Issue.record("Expected guardrail error")
        } catch let error as GenerationError {
            #expect(error == .guardrailViolation(reason: "Output too long (run-on)"))
        }
    }

    // MARK: - Full Pipeline Integration Tests

    @Test("Full pipeline: valid input passes all stages")
    func fullPipelineValidInput() {
        let input = "Best regards,"
        let sanitized = ProviderResponseGuard.sanitizeSignoff(input)
        let pasteable = try! ProviderResponseGuard.validatedPasteable(sanitized, provider: "FMF")
        let lengthValidated = try! ProviderResponseGuard.validatedLength(pasteable)
        #expect(lengthValidated == "Best regards,")
    }

    @Test("Full pipeline: input with period gets corrected")
    func fullPipelineCorrectsPeriod() {
        let input = "Best regards,."
        let sanitized = ProviderResponseGuard.sanitizeSignoff(input)
        let pasteable = try! ProviderResponseGuard.validatedPasteable(sanitized, provider: "FMF")
        let lengthValidated = try! ProviderResponseGuard.validatedLength(pasteable)
        #expect(lengthValidated == "Best regards,")
    }

    @Test("Full pipeline: run-on output gets rejected")
    func fullPipelineRejectsRunOn() async throws {
        let input = "This is a very long signoff with way too many words in it,"
        let sanitized = ProviderResponseGuard.sanitizeSignoff(input)
        let pasteable = try! ProviderResponseGuard.validatedPasteable(sanitized, provider: "FMF")
        do {
            try ProviderResponseGuard.validatedLength(pasteable)
            Issue.record("Expected guardrail error")
        } catch let error as GenerationError {
            #expect(error == .guardrailViolation(reason: "Output too long (run-on)"))
        }
    }
}