import Foundation

/// Markdown arrives one piece at a time, so a marker is unmatched for as long
/// as it takes the model to write its other half. Rendered literally, `**重點`
/// shows its asterisks and then reflows into bold when the closer lands —
/// the jerk that makes streamed text read as crude.
///
/// Closing the open marker instead renders the tail the way it is going to
/// end up, so the only thing that changes as the rest arrives is the text.
enum StreamingMarkdown {
    /// Only ever appends; the text itself is never altered.
    static func closingOpenMarkers(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var closers = ""

        let lines = text.components(separatedBy: "\n")
        let fences = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.count
        if fences % 2 == 1 {
            // Inside a fence everything is literal, so nothing else applies.
            return text + (text.hasSuffix("\n") ? "" : "\n") + "```"
        }

        guard let last = lines.last, !last.isEmpty else { return text }
        // Inside a code span even `**` is literal, so emphasis is read only
        // from what lies outside one: a half-written span must not collect an
        // emphasis closer on its way out.
        let (prose, openCodeSpan) = outsideCodeSpans(last)
        if openCodeSpan { closers += "`" }
        if emphasis(prose, marker: "**") { closers += "**" }
        if emphasis(prose, marker: "*") { closers += "*" }

        return closers.isEmpty ? text : text + closers
    }

    /// The line with its code spans taken out, and whether one is still open.
    private static func outsideCodeSpans(_ line: String) -> (prose: String, open: Bool) {
        let pieces = line.components(separatedBy: "`")
        // Pieces alternate outside, inside, outside…, so an odd number of
        // them means every span is closed.
        let prose = pieces.enumerated().filter { $0.offset % 2 == 0 }.map(\.element).joined(separator: " ")
        return (prose, pieces.count % 2 == 0)
    }

    /// Whether the line has an opener of this marker with no closer. A `*`
    /// followed by a space is a bullet or punctuation rather than emphasis,
    /// so only a run with text right after it counts as an opener.
    private static func emphasis(_ line: String, marker: String) -> Bool {
        let runs = markerRuns(in: line).filter { $0.width == marker.count }
        guard runs.count % 2 == 1 else { return false }
        return runs.last?.opensText == true
    }

    private struct Run {
        let width: Int
        /// Text follows the run, so it reads as an opening marker.
        let opensText: Bool
    }

    private static func markerRuns(in line: String) -> [Run] {
        var runs: [Run] = []
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            guard characters[index] == "*" else { index += 1; continue }
            let start = index
            while index < characters.count, characters[index] == "*" { index += 1 }
            let after = index < characters.count ? characters[index] : " "
            runs.append(Run(width: index - start, opensText: !after.isWhitespace))
        }
        return runs
    }
}
