# Nuphos iOS

SwiftUI client for api.nuphos.ai. Open `nuphos-ios.xcodeproj` in Xcode 26.2 or later.

## Run on a simulator

```sh
xcodebuild -project nuphos-ios.xcodeproj -scheme nuphos-ios -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Transcript regression checks

After installing a Debug simulator build, run:

```sh
bash tests/scroll-simulator.sh booted
```

This opens an offline fixture with long Markdown answers and tests initial
positioning, a new send, streaming growth, unchanged snapshots, and returning
to the latest message. Initial positioning and sending are sampled each display
frame; the test fails on drift rather than checking only the final offset.
It also checks a locally updated asynchronous card: its measured height must
match the allocated cell height, and the following message must sit below it.
Step expansion is sampled for title drift, and new sends must install their
short presentation-only arrival animation without changing the scroll geometry.
Relaunch without `-scroll-regression` to return to the signed-in app.

The iOS transcript uses ChatLayout 2.5.2 and self-sizing UIKit cells hosting
SwiftUI rows. The controller owns reading position, applies changed rows only,
and treats `lastSubmittedRowID` as explicit local-send intent. Server updates
preserve the visible row; sends extend the layout to place the new question near
the top. Dragging takes over from automatic following. Markdown must be populated
before a fresh cell is measured. The existing SwiftUI transcript remains the
fallback on other platforms.

## Run on a device

```sh
xcodebuild -project nuphos-ios.xcodeproj -scheme nuphos-ios -configuration Debug \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> <DerivedData>/Build/Products/Debug-iphoneos/nuphos-ios.app
xcrun devicectl device process launch --device <udid> ai.nuphos.ios
```

## TestFlight

`.github/workflows/release-ios.yml` archives, signs with the team's App Store
Connect API key (cloud-managed distribution certificate) and uploads to
TestFlight. It runs when the version in `apps/ios/package.json` changes on
`main`, or from the Actions tab. The build number is the workflow run number;
`MARKETING_VERSION` in the
project only matters for local builds.

Locally, with an API key at `~/.private_keys/AuthKey_<id>.p8`:

```sh
xcodebuild -project nuphos-ios.xcodeproj -scheme nuphos-ios -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/nuphos.xcarchive \
  -allowProvisioningUpdates -authenticationKeyPath ~/.private_keys/AuthKey_<id>.p8 \
  -authenticationKeyID <id> -authenticationKeyIssuerID <issuer> \
  CURRENT_PROJECT_VERSION=<build> archive
xcodebuild -exportArchive -archivePath build/nuphos.xcarchive -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates -authenticationKeyPath ~/.private_keys/AuthKey_<id>.p8 \
  -authenticationKeyID <id> -authenticationKeyIssuerID <issuer>
```
