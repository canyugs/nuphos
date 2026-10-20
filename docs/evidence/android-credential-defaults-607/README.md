# PR 607 visual evidence

Product source HEAD: 844e9dba465d2b52df4b08036b6ad68768ac3085.
Merged as c563d9fb0139a97586f8e5ac26abcdc35f8c0956; all twelve changed source hashes match.
Two isolated UI tests passed in 17.251s. Seven original light app screenshots were individually inspected.
The app uses local light theme; the unchanged system keyboard remains dark.

The baseline image reconstructs the former empty selection using the current production components.
It is not an old APK or a live-account capture. The remaining frames exercise current production
ChatComposer/CredentialPickerSheet/AgentStore through synthetic intercepted GETs and private fixture
preferences. Screens cover initial send disabled, failed-catalog send ready and picker error,
first-success defaults, offline-device absence, explicit Resend exclusion, deselection surviving
refresh, and explicit Resend opt-in surviving refresh. No Send action or real integration mutation.
Fixture source is local test-only; only applicationId changes to ai.nuphos.android.credentialfixture.
No production source change, real app data/auth/preferences change or FLAG_SECURE change.
Before/after Play installation, system theme and rotation snapshots are equal.

Maintainer visual approval remains separate. This evidence does not authorize a release.
