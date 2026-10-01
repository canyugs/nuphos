# Simulator notification regression

Build Debug and install `ai.nuphos.ios` into an iOS simulator. Launch it with
`SIMCTL_CHILD_NUPHOS_PREVIEW_RESPONSES` set to the absolute path of
`push-responses.json`, and pass `-preview-home` to `simctl launch`.
The fake responses apply only to api.nuphos.ai; no real account or provider is used.
The simulator remembers the fixture path for OS-initiated cold launches.
Remove the simulator app to clear that opt-in. Release builds omit the transport.

1. Allow notifications, open chat A, and send `push-b.apns` with `simctl push`.
   Tap its banner. Verify “Hello from push-b”.
2. Put the app in the background, send a notification, and tap it.
   Verify the process survives and shows the requested conversation.
3. Terminate the app, send a notification, and tap it. Verify cold-launch routing
   waits for workspace loading and opens the requested conversation.
4. From the push-opened chat B, send and tap `push-a.apns`.
   Verify the transcript changes to “Hello from push-a”.

Before the callback fix, step 2 reproducibly aborted in the async delegate's
Objective-C completion with `NSInternalInconsistencyException: Call must be made
on main thread`, via UIApplication's state-restoration snapshot methods.
Explicit delegate completion handlers now execute on MainActor. The destination
is keyed by the target's team/session identity so step 4 replaces its ChatSession.

Validated on iPhone 17 Pro Max / iOS 26.3 simulator. Device testing remains useful
for APNs delivery itself; the fixture exercises the system notification delegate
and navigation, not production provider execution.
