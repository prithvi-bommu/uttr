import Foundation
import Testing
@testable import Uttr

@Suite("HallucinationFilter")
struct HallucinationFilterTests {

    @Test("passes real speech through, trimmed")
    func passesRealSpeech() {
        #expect(HallucinationFilter.clean("  hello there \n") == "hello there")
        #expect(HallucinationFilter.clean("Let's ship it today.") == "Let's ship it today.")
    }

    @Test("strips bracketed non-speech annotations")
    func stripsBrackets() {
        #expect(HallucinationFilter.clean("[ Silence ]") == "")
        #expect(HallucinationFilter.clean("[BLANK_AUDIO]") == "")
        #expect(HallucinationFilter.clean("hello [MUSIC] world") == "hello world")
    }

    @Test("strips parenthetical non-speech annotations")
    func stripsParentheticals() {
        #expect(HallucinationFilter.clean("(soft music)") == "")
        #expect(HallucinationFilter.clean("okay (wind blowing) then") == "okay then")
    }

    @Test("strips musical-note glyphs")
    func stripsMusicNotes() {
        #expect(HallucinationFilter.clean("\u{266A}") == "")
        #expect(HallucinationFilter.clean("\u{266A} lyrics \u{266B}") == "lyrics")
    }

    @Test("strips leftover Whisper special tokens")
    func stripsSpecialTokens() {
        #expect(HallucinationFilter.clean("<|startoftranscript|>hello") == "hello")
    }

    @Test("drops whole-transcript silence hallucinations")
    func dropsKnownArtifacts() {
        #expect(HallucinationFilter.clean("you") == "")
        #expect(HallucinationFilter.clean("Thank you.") == "")
        #expect(HallucinationFilter.clean("thanks for watching") == "")
    }

    @Test("keeps real sentences that merely contain a trigger word")
    func keepsSentencesContainingTriggers() {
        #expect(HallucinationFilter.clean("you should refactor this") == "you should refactor this")
        #expect(HallucinationFilter.clean("thank you for the review Sam") == "thank you for the review Sam")
    }

    @Test("empty and whitespace input yields empty")
    func emptyInput() {
        #expect(HallucinationFilter.clean("") == "")
        #expect(HallucinationFilter.clean("   \n ") == "")
    }
}
