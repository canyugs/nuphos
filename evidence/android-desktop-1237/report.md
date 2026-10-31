# Current recovery revision

Source 04f8fa47ba51ace19eae8f5b45594a0340773397; minified APK SHA-256 `b78a44d6dad4ed034991785a406c32d0da73d731181636a7fffb1c40383d704e`. All 481 JVM tests pass. The reader now bounds total handshake, first-picture and partial-read progress separately from scoped cancellation. Periodic full updates and WebSocket pings check idle liveness. A decoder drain failure cleans up once, exposes Failed/Retry, and explicit retry resets the decoder and starts watching.

Normal full-Root UI on this exact artifact accepted a silent synthetic WebSocket, reached the default handshake deadline, closed it and reconnected to the H.264 picture as watcher (`recovery-after-timeout.png`). Accepted partial-banner and scoped-cancel cases plus deterministic codec-failure cleanup/no-repeat/visible-error/watcher-retry are JVM tests; an actual hardware codec failure was not injected. The normal behavior and limits from the original operation revision remain documented below.

# Android conversation desktop operation

Source: PR #1237, signed 247539a9f3e1525ef27827ef0dab1dd5bdfab5d4, based on 7eb2923e.

## Artifact and setup

APK SHA-256: `9e04f0fee2d7c4fc6e834edf7f497e536633c5a83f3245194431860f13af5370`.

The exact production source was built as an isolated `ai.nuphos.android.desktop1236` variant, with R8 and resource shrinking enabled, debuggable=false, a test signing key and local HTTP/WebSocket endpoint. BuildConfig.DEBUG=true permits the existing local-API consent guard. The only manifest override allows cleartext to the synthetic local endpoint. MainActivity, NuphosRoot, ChatSession, DesktopScreen and the native transport/decoder have no source injection or fixture replacement.

The self-owned headless emulator had audio disabled. A synthetic local API provided a test account/conversation and an RFB server; no production account or real remote computer was used. The H.264 sample is a generated blue 320x200 frame. The Raw sample is green. These are normal product UI operations through the real HTTP open, authenticated WebSocket, RFB decoder and MediaCodec path, against synthetic endpoints.

## Results

- All 478 JVM tests passed with zero failures/errors; lint had zero errors, instrumentation sources compiled and the minified APK built.
- Normal conversation actions showed Desktop only with owner/capability metadata.
- Raw green and H.264 blue screens rendered. The final artifact's screenshots are `final-raw-watching.png` and `final-h264.png`.
- Watching plus a tap generated no pointer/key input. Explicit Take over preceded input; Hand back sent the agent control frame and disabled input.
- IME composition itself generated no key packets. Explicit Type sent exactly `Synthetic123`, in order, once, with each key's release. See `exact-result.json`. The earlier per-edit implementation duplicated IME updates; the normal UI operation caught it and the explicit batch fixed it.
- Fast Home/return after taking control closed the stream and returned to the conversation, without reopening control (`final-fast-return.png`). The viewer now releases on Pause as well as Stop.
- The synthetic endpoint deliberately closed one stream after takeover. The UI showed Connecting, reconnected, and displayed Watching, with no automatic human-control frame (`final-reconnected-watching.png`).
- Normal conversation metadata polling changed the synthetic owner permission to false. The viewer closed and the transport ended (`final-owner-invalidated.png`).
- Separate actual HTTP tests verify that identity invalidation during an outstanding open request cannot attach the returned desktop, and that a 403 is visible without retrying or taking control.

## Limits

This is isolated synthetic operation, not a real Mac/Box, physical device or Play acceptance. Live account, team and consent switches were not each manually exercised; their captured guards and cancellation wiring are covered by source review and the invalidated-owner/open-request cases. Remote CJK delivery and hardware keyboards need authorized target validation. The Android UI provides direct touch, scrolling and explicit text/key controls; iOS's dedicated trackpad, pinch and window-fitting interface is not implemented. Framebuffer allocation is capped at 6,291,456 pixels and protocol/frame payloads are bounded. No real desktop was opened or controlled, and the physical phone's data was untouched.
