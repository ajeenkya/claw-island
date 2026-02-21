import Foundation

enum VoiceCommandIntents {
    enum SendKey: Equatable {
        case enter
        case commandEnter

        var bridgeArgument: String {
            switch self {
            case .enter: return "enter"
            case .commandEnter: return "command_enter"
            }
        }

        var spokenLabel: String {
            switch self {
            case .enter: return "Enter"
            case .commandEnter: return "Command Enter"
            }
        }
    }

    struct TypeAndSendIntent: Equatable {
        let text: String
        let sendKey: SendKey
    }

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

    static func parseTypeAndSendIntent(_ value: String) -> TypeAndSendIntent? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard let sendKey = detectSendKey(in: lower) else { return nil }

        let commandVerbs = ["type", "write", "reply", "respond", "send"]
        guard let verbRange = firstWordRange(in: lower, matchingAny: commandVerbs) else { return nil }

        let remainderOriginal = String(trimmed[verbRange.upperBound...])
        let remainderLower = remainderOriginal.lowercased()

        let pressBoundaryPattern = #"(?i)\s*(?:and\s+then|then|and)?\s*(?:press|hit|tap)\s+(?:the\s+)?(?:(?:command|cmd)\s+)?(?:send|enter|return)\b"#
        let sendKeyBoundaryPattern = #"(?i)\s+(?:send|enter|return)\s+key\b"#

        let boundaryRange = firstRegexMatch(in: remainderLower, pattern: pressBoundaryPattern)
            ?? firstRegexMatch(in: remainderLower, pattern: sendKeyBoundaryPattern)

        guard let boundaryRange else { return nil }

        var payload = String(remainderOriginal[..<boundaryRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        payload = normalizeTypePayload(payload)
        guard !payload.isEmpty else { return nil }

        return TypeAndSendIntent(text: payload, sendKey: sendKey)
    }

    private static func detectSendKey(in lower: String) -> SendKey? {
        let commandEnterHints = [
            "command enter",
            "cmd enter",
            "command return",
            "cmd return"
        ]
        if commandEnterHints.contains(where: { lower.contains($0) }) {
            return .commandEnter
        }

        let enterHints = [
            "press send",
            "hit send",
            "tap send",
            "send key",
            "press enter",
            "hit enter",
            "tap enter",
            "press return",
            "hit return",
            "tap return"
        ]
        if enterHints.contains(where: { lower.contains($0) }) {
            return .enter
        }

        return nil
    }

    private static func normalizeTypePayload(_ raw: String) -> String {
        var payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = payload.lowercased()
        let prefixes = ["with ", "to ", "saying ", "say "]
        if let prefix = prefixes.first(where: { lower.hasPrefix($0) }) {
            payload = String(payload.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let trailingNoisePatterns = [
            #"(?i)\s+here$"#,
            #"(?i)\s+in\s+this\s+(?:chat|message|thread|box)$"#,
            #"(?i)\s+in\s+(?:codex|telegram|slack|whatsapp)$"#,
            #"(?i)\s+to\s+(?:codex|telegram|slack|whatsapp)$"#
        ]
        for pattern in trailingNoisePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let fullRange = NSRange(payload.startIndex..<payload.endIndex, in: payload)
            payload = regex.stringByReplacingMatches(in: payload, options: [], range: fullRange, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        payload = payload.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’.,;:"))
        return payload
    }

    private static func firstWordRange(in value: String, matchingAny words: [String]) -> Range<String.Index>? {
        var earliest: Range<String.Index>?
        for word in words {
            guard let range = value.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) else {
                continue
            }

            if let current = earliest {
                if range.lowerBound < current.lowerBound {
                    earliest = range
                }
            } else {
                earliest = range
            }
        }
        return earliest
    }

    private static func firstRegexMatch(in value: String, pattern: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: fullRange),
              let range = Range(match.range, in: value) else {
            return nil
        }
        return range
    }
}
