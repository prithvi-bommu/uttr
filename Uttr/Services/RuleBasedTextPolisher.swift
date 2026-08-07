import Foundation

/// Pure, synchronous text-cleanup rules applied to a finished transcript.
///
/// Every transform is a deterministic string operation with no I/O, so the
/// whole pipeline runs locally in well under a millisecond and can never
/// throw — it is *fail-open* by construction (worst case it returns the input
/// unchanged). This is the offline alternative to the cloud "Text Polish"
/// providers: no API key, no network, nothing leaves the machine.
enum RuleEngine {
    /// Disfluencies removed when `removeFillers` is on. Deliberately
    /// conservative: only tokens that are almost never intentional dictation.
    /// "like" and "so" are intentionally excluded — they are real words.
    static let fillerWords: Set<String> = [
        "um", "umm", "uhm", "uh", "uhh", "erm", "hmm", "mmm", "mhm",
    ]

    static func apply(_ input: String, options: RuleBasedTextPolisher.Options) -> String {
        var text = input
        if options.removeFillers { text = removeFillers(text) }
        if options.collapseDuplicates { text = collapseDuplicateWords(text) }
        text = normalizeWhitespace(text)
        if options.capitalizeSentences { text = capitalizeSentences(text) }
        return text
    }

    // MARK: - Rules

    /// Drops standalone filler tokens ("um", "uh", …), preserving surrounding
    /// punctuation-free words. Matching ignores case and attached punctuation.
    static func removeFillers(_ text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        let kept = tokens.filter { token in
            !fillerWords.contains(core(of: String(token)))
        }
        return kept.joined(separator: " ")
    }

    /// Collapses immediately-repeated identical words ("the the cat" ->
    /// "the cat"), a common Whisper stutter. Case- and punctuation-insensitive
    /// on the comparison; keeps the first occurrence verbatim.
    static func collapseDuplicateWords(_ text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        var result: [Substring] = []
        var previousCore: String?
        for token in tokens {
            let currentCore = core(of: String(token))
            if !currentCore.isEmpty, currentCore == previousCore {
                continue // duplicate — skip
            }
            result.append(token)
            if !currentCore.isEmpty { previousCore = currentCore }
        }
        return result.joined(separator: " ")
    }

    /// Capitalizes the first letter of the transcript and the first letter of
    /// every sentence following `.`, `!`, or `?`.
    static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var capitalizeNext = true
        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(contentsOf: String(character).uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" {
                    capitalizeNext = true
                }
            }
        }
        return result
    }

    /// Collapses runs of whitespace to single spaces and trims the ends.
    static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    /// Lowercased token with leading/trailing punctuation stripped, used for
    /// filler/duplicate comparison so "Um," and "um" match.
    private static func core(of token: String) -> String {
        token
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters)
    }
}

/// Offline `TextPolisher` that runs the local `RuleEngine`. Never contacts a
/// network, never throws, and requires no API key. Suitable as the default
/// "Text Polish" implementation for a privacy-first, local-only build.
struct RuleBasedTextPolisher: TextPolisher {
    struct Options: Equatable, Sendable {
        var removeFillers: Bool
        var collapseDuplicates: Bool
        var capitalizeSentences: Bool

        init(
            removeFillers: Bool = true,
            collapseDuplicates: Bool = true,
            capitalizeSentences: Bool = true
        ) {
            self.removeFillers = removeFillers
            self.collapseDuplicates = collapseDuplicates
            self.capitalizeSentences = capitalizeSentences
        }

        /// Maps persisted settings onto engine options.
        init(config: LocalPolishConfig) {
            self.init(
                removeFillers: config.removeFillers,
                collapseDuplicates: config.collapseDuplicates,
                capitalizeSentences: config.capitalizeSentences
            )
        }
    }

    let options: Options

    init(options: Options = Options()) {
        self.options = options
    }

    func polish(_ transcript: String) async throws -> String {
        RuleEngine.apply(transcript, options: options)
    }

    func testConnection() async throws -> PolishTestResult {
        .success // Local engine is always available.
    }
}
