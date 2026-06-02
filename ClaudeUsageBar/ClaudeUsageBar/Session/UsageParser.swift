import Foundation

enum UsageParser {
    private static func re(_ p: String) -> NSRegularExpression {
        // [.dotMatchesLineSeparators] makes "." span newlines like JS [\s\S]
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let planBlock = re(#"Plan usage limits.{0,40}?\b(Pro Max|Max|Pro|Free|Team|Enterprise)\b"#)
    private static let planFallback = try! NSRegularExpression(pattern: #"\b(Pro Max|Max|Pro|Free|Team|Enterprise)\b"#)
    private static let sessionFull = re(#"Current session.*?Resets in\s+(.+?)\s*(?:\n|$).*?(\d+)\s*%\s*used"#)
    private static let sessionAlt = re(#"Current session.*?(\d+)\s*%\s*used"#)
    private static let sessionReset = re(#"Resets in\s+([0-9]+\s*hr(?:\s*[0-9]+\s*min)?|[0-9]+\s*min)"#)
    private static let weekly = re(#"All models.*?Resets\s+(.+?)\s*(?:\n|$).*?(\d+)\s*%\s*used"#)
    private static let design = re(#"Claude Design.*?(\d+)\s*%\s*used"#)

    private static func group(_ re: NSRegularExpression, _ text: String, _ idx: Int) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > idx,
              let r = Range(m.range(at: idx), in: text) else { return nil }
        return String(text[r])
    }

    static func parse(_ text: String) -> UsageState {
        var out = UsageState()
        if text.isEmpty { return out }

        out.plan = group(planBlock, text, 1) ?? group(planFallback, text, 1)

        if let resets = group(sessionFull, text, 1), let pct = group(sessionFull, text, 2) {
            out.sessionResetsIn = resets.trimmingCharacters(in: .whitespaces)
            out.sessionPercent = Int(pct)
        } else {
            if let pct = group(sessionAlt, text, 1) { out.sessionPercent = Int(pct) }
            if let r = group(sessionReset, text, 1) { out.sessionResetsIn = r.trimmingCharacters(in: .whitespaces) }
        }

        if let resets = group(weekly, text, 1), let pct = group(weekly, text, 2) {
            out.weeklyResetsAt = resets.trimmingCharacters(in: .whitespaces)
            out.weeklyPercent = Int(pct)
        }

        if let d = group(design, text, 1) { out.designPercent = Int(d) }
        return out
    }
}
