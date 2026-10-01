import Foundation

enum ComposerActionTests {
    static func run() {
        sendsWhenNoTurnIsRunning()
        stopsMidTurnWithNothingTyped()
        steersMidTurnWithSomethingTyped()
        queuesWhenTheRuntimeCannotSteer()
        print("Composer button state passed")
    }

    private static func action(
        streaming: Bool,
        payload: Bool,
        canSteer: Bool = false,
        sendsDuringTurn: Bool = false,
        canStop: Bool = true
    ) -> ComposerAction {
        .current(
            isStreaming: streaming,
            hasPayload: payload,
            canSteer: canSteer,
            sendsDuringTurn: sendsDuringTurn,
            canStop: canStop
        )
    }

    private static func expect(_ got: ComposerAction, _ want: ComposerAction, _ what: String) {
        precondition(got == want, "\(what): expected \(want), got \(got)")
    }

    private static func sendsWhenNoTurnIsRunning() {
        expect(action(streaming: false, payload: true), .send, "idle with text")
        expect(action(streaming: false, payload: false), .send, "idle and empty")
    }

    private static func stopsMidTurnWithNothingTyped() {
        expect(action(streaming: true, payload: false, canSteer: true), .stop, "mid-turn and empty")
        // Whitespace is not a payload, so the button is still Stop.
        let whitespaceIsEmpty = "   \n\t".trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        expect(action(streaming: true, payload: !whitespaceIsEmpty), .stop, "mid-turn with only whitespace")
        // A turn that cannot be cancelled leaves the button on Send rather
        // than showing a Stop that would do nothing.
        expect(action(streaming: true, payload: false, canStop: false), .send, "mid-turn, empty, uncancellable")
    }

    private static func steersMidTurnWithSomethingTyped() {
        expect(action(streaming: true, payload: true, canSteer: true), .steer, "mid-turn with text")
    }

    private static func queuesWhenTheRuntimeCannotSteer() {
        expect(action(streaming: true, payload: true), .queue, "mid-turn, steering unavailable")
        expect(
            action(streaming: true, payload: true, sendsDuringTurn: true),
            .send,
            "mid-turn on a runtime that takes messages directly"
        )
    }
}
