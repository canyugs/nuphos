# Android chat list pull-to-refresh evidence

Product head: 360502cc75a5652befa2b8963f7782fcc955c4cb

Synthetic intercepted HTTP fixtures on a physical Pixel 8 using a separate .refreshfixture application ID. This is not live backend acceptance. The real Play app and its data were unchanged; FLAG_SECURE was not bypassed. Light Surface and system-bar padding are fixture-host configuration.

289 JVM tests, 16 Python CI runner tests, lint and app/test APK builds passed. Seven real swipe fixture tests passed in 17.926 seconds, including empty/error viewport centering, search/archive retention, pins, failure/retry, folds/drafts, duplicate/pagination guards, stale workspace/account/cursor rejection and cancellation recovery. The separately recorded gesture case passed in 12.777 seconds.

All nine light screenshots were individually inspected. The reviewed video removes idle lead-in and the closing Activity transition; its contact sheet samples at four frames per second. Black contact-sheet padding is not video content. Default epoch timestamps are synthetic fixture data.

Before: refresh-before-light.png. Success updates both history and pins: refresh-success-light.png. Failure retains successful data: refresh-failed-retains-light.png. Retry: refresh-retry-light.png. Empty/error remain centered: refresh-empty-light.png, refresh-initial-error-light.png. Search/archive retained: refresh-filters-light.png. Fold and unsent draft retained: refresh-fold-draft-light.png. Refresh indicator: refresh-refreshing-light.png.
