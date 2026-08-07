import Foundation
import Testing
@testable import Uttr

@Suite("RuleEngine")
struct RuleEngineTests {

    private let all = RuleBasedTextPolisher.Options()

    @Test("removes standalone filler words")
    func removesFillers() {
        #expect(RuleEngine.removeFillers("um so uh this works") == "so this works")
        #expect(RuleEngine.removeFillers("Um, this is fine.") == "this is fine.")
    }

    @Test("keeps real words that are not fillers")
    func keepsRealWords() {
        #expect(RuleEngine.removeFillers("I like this so much") == "I like this so much")
    }

    @Test("collapses immediately repeated words")
    func collapsesDuplicates() {
        #expect(RuleEngine.collapseDuplicateWords("the the cat") == "the cat")
        #expect(RuleEngine.collapseDuplicateWords("that that that works") == "that works")
    }

    @Test("duplicate collapse ignores case and punctuation")
    func collapsesDuplicatesLoosely() {
        #expect(RuleEngine.collapseDuplicateWords("No, no we cannot") == "No, we cannot")
    }

    @Test("does not collapse distinct adjacent words")
    func keepsDistinctWords() {
        #expect(RuleEngine.collapseDuplicateWords("very very good") == "very good")
        #expect(RuleEngine.collapseDuplicateWords("the cat sat") == "the cat sat")
    }

    @Test("capitalizes first letter and sentence starts")
    func capitalizes() {
        #expect(RuleEngine.capitalizeSentences("hello world. how are you?") == "Hello world. How are you?")
        #expect(RuleEngine.capitalizeSentences("done! next one.") == "Done! Next one.")
    }

    @Test("normalizes whitespace")
    func normalizesWhitespace() {
        #expect(RuleEngine.normalizeWhitespace("  a   b\tc \n") == "a b c")
    }

    @Test("full pipeline combines the rules")
    func fullPipeline() {
        let input = "um so  the the plan is uh ready. it it works"
        let output = RuleEngine.apply(input, options: all)
        #expect(output == "So the plan is ready. It works")
    }

    @Test("individual rules can be disabled")
    func selectiveRules() {
        let onlyCapitalize = RuleBasedTextPolisher.Options(
            removeFillers: false, collapseDuplicates: false, capitalizeSentences: true)
        #expect(RuleEngine.apply("um the the cat", options: onlyCapitalize) == "Um the the cat")
    }

    @Test("empty input stays empty")
    func emptyInput() {
        #expect(RuleEngine.apply("", options: all) == "")
    }
}

@Suite("RuleBasedTextPolisher")
struct RuleBasedTextPolisherTests {

    @Test("polish applies the configured rules")
    func polishApplies() async throws {
        let polisher = RuleBasedTextPolisher()
        let result = try await polisher.polish("um hello hello world")
        #expect(result == "Hello world")
    }

    @Test("test connection always succeeds (local, offline)")
    func connectionSucceeds() async throws {
        let result = try await RuleBasedTextPolisher().testConnection()
        #expect(result == .success)
    }

    @Test("options map from LocalPolishConfig")
    func optionsFromConfig() {
        let config = LocalPolishConfig(
            enabled: true, removeFillers: false,
            collapseDuplicates: true, capitalizeSentences: false)
        let options = RuleBasedTextPolisher.Options(config: config)
        #expect(options.removeFillers == false)
        #expect(options.collapseDuplicates == true)
        #expect(options.capitalizeSentences == false)
    }
}
