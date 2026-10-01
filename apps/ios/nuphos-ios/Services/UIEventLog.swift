import CoreGraphics
import OSLog

/// Structured UI diagnostics that can be filtered in Console.app with the
/// `ui-events` category.
enum UIEventLog {
    private static let logger = Logger(subsystem: "ai.nuphos.ios", category: "ui-events")

    #if DEBUG
    static func regression(name: String, passed: Bool, detail: String) {
        logger.notice("scroll_regression name=\(name, privacy: .public) passed=\(passed) \(detail, privacy: .public)")
    }
    #endif

    static func pageTransition(from: String, to: String) {
        logger.info("page_transition from=\(from, privacy: .public) to=\(to, privacy: .public)")
    }

    static func chatScroll(sessionId: String, contentOffset: CGPoint) {
        logger.info(
            "chat_scroll session_id=\(sessionId, privacy: .private(mask: .hash)) x=\(Double(contentOffset.x), privacy: .public) y=\(Double(contentOffset.y), privacy: .public)"
        )
    }
}
