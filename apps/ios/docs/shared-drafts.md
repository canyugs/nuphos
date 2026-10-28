# System shares and local drafts

The Share Extension stages content; it does not sign in, upload, send a message or open a runtime. After **Save draft**, open Nuphos and choose **Shared drafts**. Review/edit the share, choose **Use in new agent**, then review the normal composer and tap **Send** explicitly. An occupied composer is never silently replaced. Cancel in the extension discards its temporary copies; Edits in the review editor are saved locally as you type; Cancel leaves the draft available for later.

## Supported content and bounds

Plain text, HTTP(S) URLs, images and readable regular files are accepted. Unsupported or unreadable items fail the whole share with a visible error. Up to ten files, 20 MiB each, 256 KiB of text, 100 drafts and 100 MiB across draft storage are retained. Drafts expire seven days after their last edit. Provider files are copied before their callback expires. The app uses its existing image-conversion and attachment-delivery contracts.

The App Group contains opaque account/workspace IDs, a revocable scope lease, text and local attachment copies. It never contains an authentication token. A scope must have been established by the signed-in app with a selected workspace and accepted AI notice. Changing account/workspace invalidates an extension's captured lease. Drafts remain scoped to the original account and workspace. Sign-out/consent withdrawal removes that account's drafts and revokes the lease. Import atomically changes the share into one new-composer draft; retrying the same share ID cannot import it twice. Removing/discarding a draft reclaims unreferenced files. A POSIX lock serializes app/extension transactions and an atomic index commit publishes completed copies. Files use complete data protection and are excluded from backups.

## Signing / release prerequisites

Local simulator builds do not establish App Store provisioning readiness. Before a device build or distribution:

1. Register `group.ai.nuphos.ios.drafts` with the existing Apple Developer team.
2. Register the Share Extension App ID `ai.nuphos.ios.share` and enable the App Group for it and `ai.nuphos.ios`.
3. Regenerate development/distribution profiles for the main app with this group, and create the matching extension profiles. Main and extension must use the same team and group. The widget does not join this group.
4. Configure the extension distribution profile (`Nuphos Share App Store`, or update the build setting to the approved profile name) and include its profile mapping in the distribution export workflow. Keep push entitlements on the main app.
5. Verify a signed device archive contains both group entitlements and the embedded extension. Do not strip the group entitlement or use a private-API launch workaround to bypass a provisioning failure.

No developer-account capability/profile change, signing-secret mutation or release is performed by this feature's simulator validation.

Image-object providers are normalized to PNG before staging (up to 16 megapixels and the existing 20 MB per-file limit). Generic `public.image` file representations can be keyed archives rather than encoded image data; these are not treated as directly decodable image files. Unsupported or oversized image objects show an error and keep Save disabled.
