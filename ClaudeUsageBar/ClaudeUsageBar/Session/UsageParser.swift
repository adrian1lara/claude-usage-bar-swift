import Foundation

enum UsageParser {
    private static func re(_ p: String) -> NSRegularExpression {
        // [.dotMatchesLineSeparators] makes "." span newlines like JS [\s\S]
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let planBlock = re(#"Plan usage limits.{0,40}?\b(Pro Max|Max|Pro|Free|Team|Enterprise)\b"#)
    private static let planFallback = try! NSRegularExpression(pattern: #"\b(Pro Max|Max|Pro|Free|Team|Enterprise)\b"#)
    // Matched only WITHIN a single section's text, so percents can't bleed across sections.
    private static let percentUsed = re(#"(\d+)\s*%\s*used"#)
    private static let resetsIn = re(#"Resets in\s+(.+?)\s*(?:\n|$)"#)
    private static let resetsAt = re(#"Resets\s+(.+?)\s*(?:\n|$)"#)
    private static let design = re(#"Claude Design.*?(\d+)\s*%\s*used"#)

    private static func group(_ re: NSRegularExpression, _ text: String, _ idx: Int) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > idx,
              let r = Range(m.range(at: idx), in: text) else { return nil }
        return String(text[r])
    }

    /// Earliest case-insensitive occurrence of any marker at or after `start`.
    private static func firstIndex(of markers: [String], in text: String, from start: String.Index) -> String.Index? {
        var best: String.Index?
        for m in markers {
            if let r = text.range(of: m, options: .caseInsensitive, range: start..<text.endIndex),
               best == nil || r.lowerBound < best! {
                best = r.lowerBound
            }
        }
        return best
    }

    /// Substring from the first `from` marker up to the next `to` marker (or end).
    /// Bounds each section so its percent/reset can't be read from a neighbour.
    private static func slice(_ text: String, from: [String], to: [String]) -> String? {
        guard let start = firstIndex(of: from, in: text, from: text.startIndex) else { return nil }
        let after = text.index(start, offsetBy: 1, limitedBy: text.endIndex) ?? text.endIndex
        let end = firstIndex(of: to, in: text, from: after) ?? text.endIndex
        return String(text[start..<end])
    }

    static func parse(_ text: String) -> UsageState {
        var out = UsageState()
        if text.isEmpty { return out }

        out.plan = group(planBlock, text, 1) ?? group(planFallback, text, 1)

        // Session ("current session" / daily) section, bounded so a reset to 0%
        // with no "% used" text can't pick up the weekly percent below it.
        if let seg = slice(text, from: ["Current session"],
                           to: ["All models", "Weekly", "Plan usage", "Claude Design"]) {
            if let pct = group(percentUsed, seg, 1) { out.sessionPercent = Int(pct) }
            if let r = group(resetsIn, seg, 1) { out.sessionResetsIn = r.trimmingCharacters(in: .whitespaces) }
        }

        // Weekly ("all models") section.
        if let seg = slice(text, from: ["All models", "Weekly limit", "Weekly"],
                           to: ["Claude Design", "Plan usage"]) {
            if let pct = group(percentUsed, seg, 1) { out.weeklyPercent = Int(pct) }
            if let r = group(resetsAt, seg, 1) { out.weeklyResetsAt = r.trimmingCharacters(in: .whitespaces) }
        }

        if let d = group(design, text, 1) { out.designPercent = Int(d) }
        return out
    }
}
