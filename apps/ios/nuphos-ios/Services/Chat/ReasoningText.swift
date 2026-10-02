import Foundation

/// Reasoning summaries arrive as Markdown; Codex opens each one with a bold
/// title line.
enum ReasoningText {
    static func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    /// The first line as plain text, for the collapsed row.
    static func headline(_ markdown: String) -> String? {
        guard let line = markdown.split(whereSeparator: \.isNewline).first(where: { !$0.allSatisfy(\.isWhitespace) }) else {
            return nil
        }
        let plain = String(attributed(String(line)).characters)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
        return plain.isEmpty ? nil : plain
    }
}
