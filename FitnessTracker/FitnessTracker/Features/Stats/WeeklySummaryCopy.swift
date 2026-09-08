import Foundation

/// Keeps already-persisted weekly prose trustworthy when an older prompt used
/// an ambiguous "completed out of planned" phrase for an over-target week.
enum WeeklySummaryCopy {
    private static let adherencePattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:you\s+)?(?:logged|completed)\s+\d+\s+out\s+of\s+\d+\s+(?:scheduled\s+)?sessions?"#
    )

    static func correctedBody(_ body: String, completed: Int, planned: Int) -> String {
        guard completed > planned, planned > 0 else { return body }
        let range = NSRange(location: 0, length: (body as NSString).length)
        let replacement = "You completed \(completed) sessions against a plan of \(planned)"
        return adherencePattern.stringByReplacingMatches(
            in: body,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
