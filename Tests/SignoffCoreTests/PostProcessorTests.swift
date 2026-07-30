import XCTest
import Foundation
@testable import SignoffCore

/// Tests the simplified PostProcessor (spec §3: FM handles quality).
/// Only ensurePunctuation and appendFooter remain.
final class PostProcessorTests: XCTestCase {

    // MARK: - ensurePunctuation

    func testEnsurePunctuation_AppendsPeriod() {
        XCTAssertEqual(PostProcessor.ensurePunctuation("Thanks"), "Thanks.")
    }

    func testEnsurePunctuation_PreservesExclamation() {
        XCTAssertEqual(PostProcessor.ensurePunctuation("Great!"), "Great!")
    }

    func testEnsurePunctuation_PreservesQuestion() {
        XCTAssertEqual(PostProcessor.ensurePunctuation("Soon?"), "Soon?")
    }

    func testEnsurePunctuation_EmptyString() {
        XCTAssertEqual(PostProcessor.ensurePunctuation(""), "")
    }

    func testEnsurePunctuation_TrimsWhitespace() {
        XCTAssertEqual(PostProcessor.ensurePunctuation("  Talk soon  "), "Talk soon.")
    }

    func testEnsurePunctuation_NoDoublePunctuation() {
        XCTAssertEqual(PostProcessor.ensurePunctuation("See you."), "See you.")
        XCTAssertEqual(PostProcessor.ensurePunctuation("See you!"), "See you!")
    }

    // MARK: - appendFooter

    func testAppendFooter_NothingMode() {
        let snapshot = UserProfileSnapshot(profile: nil)
        XCTAssertEqual(PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .nothing), "Thanks.")
    }

    func testAppendFooter_NameMode() {
        let profile = UserProfile(name: "Alex")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .name)
        XCTAssertTrue(result.contains("Thanks."))
        XCTAssertTrue(result.contains("—Alex"))
    }

    func testAppendFooter_FullFooterMode() {
        let profile = UserProfile(name: "Alex", title: "Engineer", company: "Acme",
                                  email: "alex@acme.com", phone: "+1555", website: "acme.com")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .fullFooter)
        XCTAssertTrue(result.contains("Thanks."))
        XCTAssertTrue(result.contains("Alex"))
        XCTAssertTrue(result.contains("Engineer"))
        XCTAssertTrue(result.contains("Acme"))
        XCTAssertTrue(result.contains("alex@acme.com"))
    }

    func testAppendFooter_FullFooterExcludesEmptyFields() {
        let profile = UserProfile(name: "Alex")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .fullFooter)
        XCTAssertTrue(result.contains("Thanks."))
        XCTAssertTrue(result.contains("Alex"))
        XCTAssertFalse(result.contains("(null)"))
        XCTAssertFalse(result.contains("nil"))
    }

    func testAppendFooter_AppliesPunctuationBeforeFooter() {
        let snapshot = UserProfileSnapshot(profile: nil)
        let result = PostProcessor.appendFooter("Great chat", profile: snapshot, mode: .nothing)
        XCTAssertEqual(result, "Great chat.")
    }

    // MARK: - UserProfileSnapshot

    func testUserProfileSnapshot_Empty() {
        let s = UserProfileSnapshot(profile: nil)
        XCTAssertEqual(s.name, "")
        XCTAssertNil(s.title)
        XCTAssertNil(s.company)
        XCTAssertEqual(s.selfDescription, "")
        XCTAssertFalse(s.emojiEnabled)
    }

    func testUserProfileSnapshot_FullProfile() {
        let p = UserProfile(name: "Bob", title: "Dev", company: "Co",
                            email: "b@c.com", phone: "555", website: "b.co",
                            selfDescription: "coder", emojiEnabled: true)
        let s = UserProfileSnapshot(profile: p)
        XCTAssertEqual(s.name, "Bob")
        XCTAssertEqual(s.title, "Dev")
        XCTAssertEqual(s.company, "Co")
        XCTAssertEqual(s.email, "b@c.com")
        XCTAssertEqual(s.phone, "555")
        XCTAssertEqual(s.website, "b.co")
        XCTAssertEqual(s.selfDescription, "coder")
        XCTAssertTrue(s.emojiEnabled)
    }
}
