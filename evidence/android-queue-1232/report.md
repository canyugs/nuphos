# Android server queue operation evidence

## Source and artifact

- PR #1232, initial head `d44c4913f0628c5147584c4cae5782ef8175bdc6`, revised head `1934b20818f8c85722e9efad563c53e351114506`.
- Base `7eb2923e3c83d6932a9af1478faf73ca94ccb424`.
- Revised minified APK SHA256 `8ca78be2c4f6327311dd974a2aa63abf80a5f317676260441904e3308681ac34`.
- Normal MainActivity, NuphosRoot, password login and ConversationScreen. No instrumentation, reflection or extracted consumer harness was used for the UI run.
- R8 and resource shrinking enabled; manifest debuggable false; separate package `ai.nuphos.android.queue1231`, Android test signing.
- Controlled differences: local synthetic HTTP API on loopback, cleartext test manifest, `BuildConfig.DEBUG=true` solely to opt into the existing local credential-destination guard. Fake account/workspace/runtime/queue data. This is not a Play artifact, real backend/runtime, Firebase delivery or physical-device acceptance.

## Initial-head normal UI operation

1. Logged in through the normal password UI. Opened the synthetic conversation from the normal list.
2. Own queued rows appeared in server order; the teammate's row was absent. Steering controls were disabled until the runtime allowed it. See `queue-initial.png`.
3. Entered `Existing draft`, took the second message back using Edit. Composer contained the original draft plus recalled text. DELETE returned 200. See `recalled-draft.png`.
4. Removed the remaining queued note using Remove. DELETE returned 200.
5. Explicitly sent the combined draft while busy. The main chat request received HTTP 202; one request was recorded and the message appeared in the server queue after reconciliation. See `queued-after-poll.png`.
6. Changed only the synthetic runtime capability to permit steering. Clicked Send into turn; POST /steer returned 200 and the row disappeared. See `steering-enabled.png`, `steered-result.png`.
7. Synthetic DELETE 503 retained the row, left the composer empty and displayed a recovery error. See `deletion-failure-result.png`.
8. A stale row whose server message had started received DELETE 404. It disappeared with an explanatory message and was not copied into the composer. See `already-started-result.png`.
9. Synthetic read-only metadata disabled Edit, Remove, Send into turn, composer, voice and queue-send parent controls. Verified enabled=false on the actionable parents in `readonly-queue.xml`.
10. A successful original-message receipt with an inline JPEG restored the text and named photo tile. See `photo-recalled.png`.

## Revised-head normal UI regression

- Reinstalled the revised minified APK in place on the same disposable emulator, preserving the synthetic login; opened the normal conversation again.
- A confirmed take-back with an unsupported inline attachment retained its original text and filename in the recovery panel; the next Edit action was disabled. See `latest-recovery-held.png` and XML.
- Explicitly removing the second queued message did not replace the first retained recovery receipt or its file information. See `latest-recovery-preserved.png`.
- Unsupported inline formats remain an explicit in-screen recovery limitation; direct restoration currently supports Android's inline JPEG format. The recovery panel warns to restore/copy before leaving. This run does not establish process-death durability for un-restored receipts or queued file-transfer end-to-end content reading.

## Automated verification on revised head

484 JVM tests, zero failures/errors, including:

- queue ownership/order, duplicate actions, stale reads, 404/transient failures, scope invalidation and recovery receipts with original file parts;
- original queue response text/file decoding;
- actual loopback HTTP 202 with no SSE frames through the real SseClient parser and ChatSession: original/prepared owned copies released, pending state cleared, optimistic user row removed, exactly one request;
- unconfirmed HTTP 500 retains both owned copies for recovery.

Android device-test source compilation and lint pass (zero errors). Checks: `checks4.log`; R8 build: `release-build2.log`. Screenshots are synthetic only. Pixel, Play, production API and iOS simulators were not operated for this task.
