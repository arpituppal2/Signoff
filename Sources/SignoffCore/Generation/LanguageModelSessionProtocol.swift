import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Protocol abstraction over `LanguageModelSession` to enable mocking in tests.
/// This mirrors the subset of FoundationModels' LanguageModelSession API
/// used by Signoff's generation pipeline.
@available(macOS 26, *)
public protocol LanguageModelSessionProtocol: Sendable {
    /// Whether the session is currently generating a response.
    var isResponding: Bool { get }

    /// Pre-warm the session with a prompt prefix to cache common context.
    /// - Parameter promptPrefix: Optional prompt prefix to pre-warm.
    func prewarm(promptPrefix: Prompt?) async

    /// Generate a structured response conforming to `Output`.
    /// - Parameters:
    ///   - prompt: The user prompt to respond to.
    ///   - output: The generable output type.
    ///   - options: Generation options (temperature, token limit, etc.).
    /// - Returns: The generated output.
    func respond<Output: Generable & Sendable>(
        to prompt: String,
        generating output: Output.Type,
        options: GenerationOptions
    ) async throws -> Output
}

/// A wrapper around the real `LanguageModelSession` that conforms to our protocol.
/// This enables dependency injection while preserving the real Foundation Models behavior.
@available(macOS 26, *)
public struct RealLanguageModelSession: LanguageModelSessionProtocol {
    private let session: LanguageModelSession

    public init(instructions: String) {
        self.session = LanguageModelSession(instructions: instructions)
    }

    public var isResponding: Bool {
        session.isResponding
    }

    public func prewarm(promptPrefix: Prompt?) async {
        await session.prewarm(promptPrefix: promptPrefix)
    }

    public func respond<Output: Generable & Sendable>(
        to prompt: String,
        generating output: Output.Type,
        options: GenerationOptions
    ) async throws -> Output {
        let response = try await session.respond(
            to: prompt,
            generating: output,
            options: options
        )
        return response.content
    }
}

/// A mock session for testing that returns pre-programmed responses.
@available(macOS 26, *)
public actor MockLanguageModelSession: LanguageModelSessionProtocol {
    public nonisolated var isResponding: Bool { false }
    private let response: SignoffOutput?
    private let error: (any Error)?

    public init(response: SignoffOutput? = nil, error: (any Error)? = nil) {
        self.response = response
        self.error = error
    }

    public func prewarm(promptPrefix: Prompt?) async {}

    public func respond<Output: Generable & Sendable>(
        to prompt: String,
        generating output: Output.Type,
        options: GenerationOptions
    ) async throws -> Output {
        if let error {
            throw error
        }

        guard let response = response as? Output else {
            throw GenerationError.unsafeCandidate(reason: "Mock response type mismatch")
        }

        return response
    }
}

/// A mock session that simulates context window overflow on first call,
/// then succeeds on retry (testing the retry logic in FoundationModelsSessionPool).
@available(macOS 26, *)
public actor ContextOverflowMockSession: LanguageModelSessionProtocol {
    public nonisolated var isResponding: Bool { false }
    private let finalResponse: SignoffOutput
    private var attempt = 0

    public init(finalResponse: SignoffOutput) {
        self.finalResponse = finalResponse
    }

    public func prewarm(promptPrefix: Prompt?) async {}

    public func respond<Output: Generable & Sendable>(
        to prompt: String,
        generating output: Output.Type,
        options: GenerationOptions
    ) async throws -> Output {
        attempt += 1
        if attempt == 1 {
            // First attempt: simulate context window overflow
            throw GenerationError.contextWindowExceeded
        }

        // Second attempt: succeed
        guard let response = finalResponse as? Output else {
            throw GenerationError.unsafeCandidate(reason: "Mock response type mismatch")
        }
        return response
    }
}
#endif