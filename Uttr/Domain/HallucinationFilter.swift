import Foundation

/// Strips the artifacts Whisper models emit on silence or near-silence.
///
/// Whisper (and WhisperKit) will happily "transcribe" a silent or very quiet
/// buffer into non-speech annotations like `[ Silence ]`, `(soft music)`,
/// `[BLANK_AUDIO]`, musical-note glyphs, or a bare filler phrase such as
/// "you" / "thank you". None of those are dictation and pasting them is worse
/// than pasting nothing. This filter runs locally in well under a millisecond
/// and is fail-open: any input it does not recognise is returned trimmed but
/// otherwise untouched.
enum HallucinationFilter {
    /// Whole-transcript phrases that are known Whisper silence hallucinations.
    /// Matched only when they constitute the *entire* cleaned transcript, so a
    /// legitimate sentence that merely contains "you" is never affected.
    private static let knownArtifacts: Set<String> = [
        "you",
        "thank you",
        "thank you.",
        "thanks for watching",
        "thank you for watching",
        "please subscribe",
        "bye",
        "silence",
        "music",
        "blank_audio",
        "inaudible",
    ]

    /// Regex fragments removed anywhere they appear.
    private static let strippedPatterns: [String] = [
        "\\[[^\\]]*\\]",       // [ Silence ], [BLANK_AUDIO], [MUSIC]
        "\\([^\\)]*\\)",       // (soft music), (wind blowing)
        "<\\|[^|]*\\|>",       // leftover Whisper special tokens <|...|>
        "\u{266A}",             // ♪
        "\u{266B}",             // ♫
    ]

    /// Returns the transcript with non-speech annotations removed. When the
    /// entire transcript is a known hallucination phrase, returns "".
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        for pattern in strippedPatterns {
            text = text.replacingOccurrences(
                of: pattern, with: " ", options: .regularExpression)
        }

        // Collapse the whitespace the removals may have left behind.
        text = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Whole-string known artifact -> nothing worth pasting.
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?…-"))
        if normalized.isEmpty || knownArtifacts.contains(normalized) {
            return ""
        }

        return text
    }
}
