import Testing
import Foundation
@testable import SignoffCore

/// Tests the simplified PostProcessor (spec §3: FM handles quality).
/// Only ensurePunctuation and appendFooter remain.
struct PostProcessorTests {

    // MARK: - ensurePunctuation

    @Test("Ensure punctuation appends period")
    func ensurePunctuationAppendsPeriod() {
        #expect(PostProcessor.ensurePunctuation("Thanks") == "Thanks.")
    }

    @Test("Ensure punctuation preserves exclamation")
    func ensurePunctuationPreservesExclamation() {
        #expect(PostProcessor.ensurePunctuation("Great!") == "Great!")
    }

    @Test("Ensure punctuation preserves question")
    func ensurePunctuationPreservesQuestion() {
        #expect(PostProcessor.ensurePunctuation("Soon?") == "Soon?")
    }

    @Test("Ensure punctuation empty string")
    func ensurePunctuationEmptyString() {
        #expect(PostProcessor.ensurePunctuation("") == "")
    }

    @Test("Ensure punctuation trims whitespace")
    func ensurePunctuationTrimsWhitespace() {
        #expect(PostProcessor.ensurePunctuation("  Talk soon  ") == "Talk soon.")
    }

    @Test("Ensure punctuation no double punctuation")
    func ensurePunctuationNoDoublePunctuation() {
        #expect(PostProcessor.ensurePunctuation("See you.") == "See you.")
        #expect(PostProcessor.ensurePunctuation("See you!") == "See you!")
    }

    // MARK: - appendFooter

    @Test("Append footer nothing mode")
    func appendFooterNothingMode() {
        let snapshot = UserProfileSnapshot(profile: nil)
        #expect(PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .nothing) == "Thanks.")
    }

    @Test("Append footer name mode")
    func appendFooterNameMode() {
        let profile = UserProfile(name: "Alex")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .name)
        #expect(result.contains("Thanks."))
        #expect(result.contains("—Alex"))
    }

    @Test("Append footer full footer mode")
    func appendFooterFullFooterMode() {
        let profile = UserProfile(name: "Alex", title: "Engineer", company: "Acme",
                                  email: "alex@acme.com", phone: "+1555", website: "acme.com")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .fullFooter)
        #expect(result.contains("Thanks."))
        #expect(result.contains("Alex"))
        #expect(result.contains("Engineer"))
        #expect(result.contains("Acme"))
        #expect(result.contains("alex@acme.com"))
    }

    @Test("Append footer full footer excludes empty fields")
    func appendFooterFullFooterExcludesEmptyFields() {
        let profile = UserProfile(name: "Alex")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .fullFooter)
        #expect(result.contains("Thanks."))
        #expect(result.contains("Alex"))
        #expect(!result.contains("(null)"))
        #expect(!result.contains("nil"))
    }

    @Test("Append footer full footer honors field selection")
    func appendFooterFullFooterHonorsFieldSelection() {
        let profile = UserProfile(name: "Alex", title: "Engineer", company: "Acme",
                                  email: "alex@acme.com", footerFieldsRaw: "name,title")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .fullFooter)
        #expect(result.contains("Alex"))
        #expect(result.contains("Engineer"))
        #expect(!result.contains("Acme"))
        #expect(!result.contains("alex@acme.com"))
    }

    @Test("Append footer full footer default includes everything")
    func appendFooterFullFooterDefaultIncludesEverything() {
        let profile = UserProfile(name: "Alex", title: "Engineer", company: "Acme",
                                  email: "alex@acme.com")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .fullFooter)
        #expect(result.contains("Alex"))
        #expect(result.contains("Engineer"))
        #expect(result.contains("Acme"))
        #expect(result.contains("alex@acme.com"))
    }

    @Test("Footer field encode nil when all selected")
    func footerFieldEncodeNilWhenAllSelected() {
        let all = Set(FooterField.allCases.map(\.rawValue))
        #expect(FooterField.encode(all) == nil)
        #expect(FooterField.decode(nil) == all)
        #expect(FooterField.decode("") == all)
        #expect(FooterField.decode("name,title") == ["name", "title"])
        #expect(FooterField.encode(["name", "title"]) == "name,title")
    }

    @Test("Append footer name mode ignores selection")
    func appendFooterNameModeIgnoresSelection() {
        let profile = UserProfile(name: "Alex", title: "Engineer", footerFieldsRaw: "title")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .name)
        #expect(result.contains("—Alex"))
    }

    @Test("Append footer applies punctuation before footer")
    func appendFooterAppliesPunctuationBeforeFooter() {
        let snapshot = UserProfileSnapshot(profile: nil)
        let result = PostProcessor.appendFooter("Great chat", profile: snapshot, mode: .nothing)
        #expect(result == "Great chat.")
    }

    // MARK: - UserProfileSnapshot

    @Test("User profile snapshot empty")
    func userProfileSnapshotEmpty() {
        let s = UserProfileSnapshot(profile: nil)
        #expect(s.name == "")
        #expect(s.title == nil)
        #expect(s.company == nil)
        #expect(s.selfDescription == "")
        #expect(s.emojiEnabled == false)
        #expect(s.includedFooterFields == Set(FooterField.allCases.map(\.rawValue)))
    }

    @Test("User profile snapshot full profile")
    func userProfileSnapshotFullProfile() {
        let p = UserProfile(name: "Bob", title: "Dev", company: "Co",
                            email: "b@c.com", phone: "555", website: "b.co",
                            selfDescription: "coder", emojiEnabled: true,
                            footerFieldsRaw: "name,email")
        let s = UserProfileSnapshot(profile: p)
        #expect(s.name == "Bob")
        #expect(s.title == "Dev")
        #expect(s.company == "Co")
        #expect(s.email == "b@c.com")
        #expect(s.phone == "555")
        #expect(s.website == "b.co")
        #expect(s.selfDescription == "coder")
        #expect(s.emojiEnabled == true)
        #expect(s.includedFooterFields == ["name", "email"])
    }
}