import Foundation

enum StreamingMarkdownTests {
    static func run() {
        closesAnOpenStrongMarker()
        closesAnOpenCodeSpanAndFence()
        leavesSettledTextAlone()
        leavesBulletsAndArithmeticAlone()
        readsEmphasisOnlyOutsideCodeSpans()
        onlyEverAppends()
        print("Streaming markdown passed")
    }

    private static func closed(_ text: String) -> String {
        StreamingMarkdown.closingOpenMarkers(in: text)
    }

    private static func closesAnOpenStrongMarker() {
        precondition(closed("這裡的 **重點") == "這裡的 **重點**", "got \(closed("這裡的 **重點"))")
        precondition(closed("a *word") == "a *word*")
        // The closer has landed; nothing to add.
        precondition(closed("這裡的 **重點** 已經寫完") == "這裡的 **重點** 已經寫完")
    }

    private static func closesAnOpenCodeSpanAndFence() {
        precondition(closed("run `bun test") == "run `bun test`")
        precondition(closed("```swift\nlet x = 1") == "```swift\nlet x = 1\n```")
        precondition(closed("```swift\nlet x = 1\n```\ndone") == "```swift\nlet x = 1\n```\ndone")
    }

    private static func leavesSettledTextAlone() {
        for text in ["", "plain text", "第一段\n\n第二段", "`code`", "**bold** and *italic*"] {
            precondition(closed(text) == text, "settled text must not change: \(text)")
        }
    }

    /// A marker followed by a space is a bullet or a stray asterisk, not an
    /// opener — closing those would style half the answer.
    private static func leavesBulletsAndArithmeticAlone() {
        precondition(closed("* first item") == "* first item")
        precondition(closed("2 * 3 = 6") == "2 * 3 = 6")
    }

    /// Asterisks inside a code span are literal, so a half-written span must
    /// not collect an emphasis closer on its way out.
    private static func readsEmphasisOnlyOutsideCodeSpans() {
        precondition(closed("`2**n") == "`2**n`", "got \(closed("`2**n"))")
        precondition(closed("call `f(**a") == "call `f(**a`")
        // Emphasis outside a finished span still closes.
        precondition(closed("**注意 `bun test` 這裡") == "**注意 `bun test` 這裡**")
        // Both open: the span closes first, then the emphasis around it.
        precondition(closed("**注意 `bun") == "**注意 `bun`**", "got \(closed("**注意 `bun"))")
    }

    /// The text itself is never rewritten, so nothing the model wrote is lost
    /// or reordered on the way to the screen.
    private static func onlyEverAppends() {
        let samples = [
            "這裡的 **重點", "run `bun test", "```swift\nlet x = 1", "a *word",
            "plain", "* first item", "**done** already",
        ]
        for text in samples {
            precondition(closed(text).hasPrefix(text), "must only append, got \(closed(text)) for \(text)")
        }
    }
}
