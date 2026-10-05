# Nuphos Android

Native Android client built with Kotlin and Jetpack Compose. This contribution
contains the app, Gradle wrapper, JVM tests, and isolated device fixture tests.
It does not contain credentials, APK files, IDE settings, or personal test data.

## Requirements

- Android Studio or Android SDK command-line tools.
- JDK 21 to start Gradle. Gradle uses a JDK 17 Kotlin toolchain.
- Android SDK platform 37 and platform-tools. Accept the SDK licenses first.
- Android 14 (API 34) or later on a device or emulator.

Set `JAVA_HOME` to JDK 21 and `ANDROID_HOME` to the Android SDK directory.
Alternatively, set `sdk.dir` in an untracked `local.properties` file.
Open this directory in Android Studio, or run:

```sh
cd apps/android
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleDebugAndroidTest
adb -s DEVICE_SERIAL install -r app/build/outputs/apk/debug/app-debug.apk
```

The Gradle toolchain resolver can download JDK 17. Gradle downloads build tools
once the SDK licenses are accepted. The debug APK is for development and uses a
local debug signing key. It is not a signed store release. An installed APK must
use the same signing key to update without removing app data.

## Service support

The current app connects to `api.nuphos.ai`. Sign-in opens `nuphos.ai` in a
browser and returns to the app. A Nuphos Cloud account is required. This version
does not expose a custom API endpoint or native email sign-in. Desktop and iOS
support self-hosted endpoints; Android support remains separate future work.

The app supports conversations, shared history, attachment transfers, runtime
controls, permissions, Plans, Connectors, account settings, read-only Monitoring,
and read-only stored Trigger runs. Availability depends on team permissions,
connected providers, and backend capabilities. Android notifications are local;
remote push requires a separate backend and transport integration.

No backend or iOS changes are needed for this contribution. The public backend
contains the API contracts used by the app. Managed cloud operations remain
service-dependent and are not added to the self-hosted backend by this client.

## Tests

JVM tests use synthetic inputs and intercepted HTTP responses. They do not need
an account or a live server. CI builds the app and device-test APK, runs JVM
tests, and checks Android lint. CI does not run live-account acceptance tests.

Device fixture tests use synthetic data and request interceptors. Run them on a
clean emulator or a dedicated test device; instrumentation can replace app
state. Do not run the full fixture suite on a signed-in personal phone.

```sh
./gradlew :app:connectedDebugAndroidTest
```

Live tests tied to private accounts, device serials, team IDs, screenshots, and
provisioning scripts are excluded from this contribution. Installed-state
account and Trigger lifecycle acceptance tests are also excluded because they
require an existing login token. Earlier private-device
results do not prove that this public checkout passed every live operation.
Do not place tokens, signing keys, test-account data, or screenshots in Git.
