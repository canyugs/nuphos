import Foundation

/// One server-sent event: the `event:` name (if any) and the joined `data:`
/// payload. Comment lines (`: …`) are dropped; they are the heartbeat.
struct SSEEvent: Sendable, Equatable {
    var event: String?
    var data: String
    var id: String?
}

/// Minimal SSE reader over `URLSession.bytes`. Yields events as they arrive
/// and enforces two deadlines the desktop client also uses: a first-byte
/// deadline and an idle timeout between bytes.
enum SSEClient {
    enum Failure: LocalizedError {
        case badStatus(Int, body: String?)
        case notEventStream(String?)
        case firstByteTimeout
        case idleTimeout
        /// Heartbeats kept coming but no event did — a dead run.
        case frameTimeout

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body): body.flatMap(SSEClient.errorMessage) ?? "Nuphos returned status \(code)."
            case .notEventStream(let type): "Expected an event stream, got \(type ?? "nothing")."
            case .firstByteTimeout: "Nuphos did not start responding in time."
            case .idleTimeout: "The connection went quiet for too long."
            case .frameTimeout: "The runtime went quiet; the reply was closed."
            }
        }
    }

    /// Opens `request` and streams its events. The stream ends when the
    /// server closes the connection; cancel the consuming task to abort.
    static func events(
        for request: URLRequest,
        firstByteTimeout: Duration = .seconds(5),
        idleTimeout: Duration = .seconds(45),
        frameTimeout: Duration = .seconds(40 * 60)
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let activity = ActivityClock()
            // Reset by events only, never by heartbeats: the backend's stall
            // sweeper ends a silent run after 35 minutes, so a client that
            // keeps reconnecting past that is waiting on nothing.
            let frames = ActivityClock()

            let reader = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw Failure.notEventStream(nil)
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 4000 { break } }
                        throw Failure.badStatus(http.statusCode, body: body.isEmpty ? nil : body)
                    }
                    let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
                    guard contentType.contains("text/event-stream") else {
                        throw Failure.notEventStream(contentType)
                    }

                    var pending = SSEEvent(data: "")
                    var hasData = false
                    var buffer: [UInt8] = []
                    buffer.reserveCapacity(4096)

                    // Split on newlines by hand: `AsyncLineSequence` drops the
                    // blank lines that delimit SSE events.
                    func consume(_ rawLine: [UInt8]) {
                        var line = String(decoding: rawLine, as: UTF8.self)
                        if line.hasSuffix("\r") { line.removeLast() }
                        if line.isEmpty {
                            if hasData { frames.touch(); continuation.yield(pending) }
                            pending = SSEEvent(data: "")
                            hasData = false
                            return
                        }
                        if line.hasPrefix(":") { return } // heartbeat / comment

                        let (field, value) = split(line)
                        switch field {
                        case "data":
                            pending.data += (hasData ? "\n" : "") + value
                            hasData = true
                        case "event": pending.event = value
                        case "id": pending.id = value
                        default: break
                        }
                    }

                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            activity.touch()
                            consume(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty { consume(buffer) }
                    if hasData { continuation.yield(pending) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Watchdog: first byte within `firstByteTimeout`, then no gap
            // longer than `idleTimeout` (the backend heartbeats every ~5 s).
            let watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    let (seen, idle) = activity.status()
                    if !seen, idle > firstByteTimeout {
                        continuation.finish(throwing: Failure.firstByteTimeout)
                        reader.cancel()
                        return
                    }
                    if seen, idle > idleTimeout {
                        continuation.finish(throwing: Failure.idleTimeout)
                        reader.cancel()
                        return
                    }
                    let (sawFrame, sinceFrame) = frames.status()
                    if sawFrame, sinceFrame > frameTimeout {
                        continuation.finish(throwing: Failure.frameTimeout)
                        reader.cancel()
                        return
                    }
                }
            }

            continuation.onTermination = { _ in
                reader.cancel()
                watchdog.cancel()
            }
        }
    }

    /// Last-byte timestamp shared between the reader and the watchdog.
    private final class ActivityClock: @unchecked Sendable {
        private let lock = NSLock()
        private var last = ContinuousClock.now
        private var seen = false

        func touch() {
            lock.withLock { last = .now; seen = true }
        }

        func status() -> (seen: Bool, idle: Duration) {
            lock.withLock { (seen, ContinuousClock.now - last) }
        }
    }

    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        let field = String(line[..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        return (field, value)
    }

    static func errorMessage(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return body.isEmpty ? nil : body }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = json["message"] as? String { return message }
        return body
    }
}
