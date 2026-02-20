import Foundation

enum VoiceCommandIntents {
    static func isSelectionRewriteRequest(_ value: String) -> Bool {
        let lower = value.lowercased()
        let keywords = [
            "rewrite", "rephrase", "polish", "improve this",
            "make this shorter", "shorter", "friendlier",
            "professional tone", "change the tone", "make this better"
        ]
        return keywords.contains { lower.contains($0) }
    }

    static func isDirectApplyRewriteRequest(_ value: String) -> Bool {
        let lower = value.lowercased()
        let directApplyPhrases = [
            "and apply",
            "apply it",
            "replace it",
            "rewrite and apply",
            "rewrite and replace",
            "skip preview",
            "no preview",
            "directly apply",
            "just apply"
        ]
        return directApplyPhrases.contains { lower.contains($0) }
    }

    static func isApplyConfirmation(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let explicit = [
            "apply", "yes", "yes apply", "confirm", "go ahead",
            "do it", "replace it", "approved"
        ]
        return explicit.contains(normalized)
    }

    static func isCancelPendingRewrite(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cancelWords = ["cancel", "never mind", "dismiss", "skip that"]
        return cancelWords.contains(normalized)
    }

    static func extractRewriteText(from response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.lowercased().hasPrefix("rewritten:") {
            cleaned = String(cleaned.dropFirst("rewritten:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.lowercased().hasPrefix("revised:") {
            cleaned = String(cleaned.dropFirst("revised:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }
}
