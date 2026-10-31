# Android voice input validation

Production patch: PR #1234, based on 7eb2923e. The current production commit is recorded in manifest2.json.

## Focused checks

473 JVM tests pass; lint has zero errors. The Composer device suite exercises explicit send with latest text, admission loss, local editable dictation, cancellation, owner changes, blank/error responses and rejection at the durable draft limit with the original text and retained file preserved. See device5.log for the final device result.

## Full Root controlled operation

The installed variant runs the normal MainActivity, NuphosRoot, conversation, ChatComposer and ChatSession with R8 and resource shrinking enabled, debuggable=false, an isolated application ID and test signature. BuildConfig.DEBUG=true permits the synthetic loopback API. MainActivity alone supplies a synthetic recorder (45-byte temporary file, no microphone input) and a NuphosWhisperTransport using the normal Http.client consent interceptor with an event-listener client factory. This is a controlled test variant, not the unchanged production artifact. Its exact overlay and APK hashes are in root-variant-manifest.json.

Normal UI operations on the synthetic conversation:

- Transcribe and edit: transcript appears in the composer; no chat POST.
- Transcribe and send: one actual ChatSession POST /agent/chat, exactly `Synthetic voice transcript Synthetic voice transcript` (existing draft + latest transcript), accepted with HTTP 202.
- Lose send admission during a delayed transcript: `Retained after admission loss` remains in the composer; no additional chat POST.
- Cancel recording: draft remains, no transcription or chat send.
- Empty transcript after an explicit send action: visible no-speech error; existing draft remains, no additional chat POST.

Only one synthetic chat submission occurred across these operations. Screenshots: root-chat-edit-result.png, root-chat-send-result.png, root-loss-result.png, root-cancel-result.png and root-empty-result.png.

## Limits

The original minified source variant showed the recording controls, but an emulator launched with -no-audio did not produce a usable transcription. A subsequent synthetic-recorder variant using the default transport factory also failed before the API was reached; the event-listener Http.client factory variant completed the controlled operations. This does not establish the cause of that default-factory failure. Real microphone capture, the default production transport against the real subscription service, a real provider response, Pixel and Play acceptance remain unverified. No host microphone, real account, physical phone or remote runtime was used.
