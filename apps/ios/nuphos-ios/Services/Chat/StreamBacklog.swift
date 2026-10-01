import Foundation

/// Re-attaching to a run replays it from its first frame. Applied one at a
/// time, those frames are re-enacted — the transcript fast-forwards through
/// work that is already over — so a burst is held and handed back in one
/// piece, to be applied as state rather than as animation.
///
/// Nothing is reordered or dropped: `receive` returns exactly the frames it
/// was given, in order, just later.
struct StreamBacklog {
    struct Frame: Equatable {
        let value: JSONValue
        let type: String
    }

    /// Frames closer together than this belong to a replay rather than to a
    /// reply being written.
    static let frameGap: TimeInterval = 0.1
    /// How many of them in a row before holding starts.
    static let burstLength = 8
    /// The most frames held at once, so a long replay still shows progress.
    static let batchSize = 64
    /// The longest frames are ever held. A burst that stops — the replay has
    /// caught up, the agent is thinking — must not leave them waiting on a
    /// frame that may never come, and a stream that stays fast renders
    /// steadily at this rate rather than in jumps. Held at the short end of
    /// the 30–100ms band that reads as continuous: each commit lands about a
    /// word, rather than a clump long enough to see arrive.
    static let holdWindow: TimeInterval = 0.07
    /// Frames the user is waiting on go in the moment they arrive, however
    /// fast the stream is running.
    static let rendersImmediately: Set<String> = [
        "tool-approval-request", "atlas-turn-complete", "atlas-turn-paused",
        "atlas-stream-done", "atlas-transcript-snapshot", "error",
    ]

    private var held: [Frame] = []
    private var burst = 0
    private var lastFrameAt: Date = .distantPast
    /// When the held frames go in regardless of what else arrives.
    private(set) var deadline: Date?

    /// Whether frames are currently being held back.
    var isHolding: Bool { !held.isEmpty }

    /// The frames to apply now: empty while a replay is still arriving.
    mutating func receive(_ value: JSONValue, type: String, at now: Date) -> [Frame] {
        let gap = now.timeIntervalSince(lastFrameAt)
        lastFrameAt = now
        burst = gap < Self.frameGap ? burst + 1 : 0

        let frame = Frame(value: value, type: type)
        if burst >= Self.burstLength, !Self.rendersImmediately.contains(type) {
            if held.isEmpty { deadline = now.addingTimeInterval(Self.holdWindow) }
            held.append(frame)
            guard held.count >= Self.batchSize || now >= (deadline ?? now) else { return [] }
            return flush()
        }
        return flush() + [frame]
    }

    /// The held frames once their window is up — what the scheduled flush
    /// applies when no further frame arrives to carry them in.
    mutating func framesDue(at now: Date) -> [Frame] {
        guard let deadline, now >= deadline else { return [] }
        return flush()
    }

    /// Everything held, for a stream that ended or went quiet.
    mutating func flush() -> [Frame] {
        defer { held = []; deadline = nil }
        return held
    }
}
