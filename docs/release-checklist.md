# Release Checklist

Use this checklist for every public release. A green local build is not a release criterion by itself.

## Before the release candidate

- [ ] `master` is green in the required **Clean Build & Test** GitHub Actions check.
- [ ] Run `xcodegen generate` from a fresh clone, then run the release build and full test suite.
- [ ] Run `xcodebuild -project Anchored.xcodeproj -scheme Anchored -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
- [ ] Run `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`.
- [ ] Test the installed release app in `/Applications`: menu bar startup, profile switch, focus prompt, countdown, dimming, and return-to-work.
- [ ] Test a browser with an active tab and with no active tab; confirm the app remains responsive when Accessibility is unavailable.
- [ ] Confirm cloud classification is off by default and that disabling it prevents remote requests.
- [ ] Confirm screenshots are not persisted and local context-history retention matches the selected setting.

## Publishing

- [ ] Update `CHANGELOG.md` and version metadata.
- [ ] Create an annotated semantic-version tag (`vMAJOR.MINOR.PATCH`).
- [ ] Archive, sign, and notarize the release build with the stable Developer ID Application certificate; validate with Gatekeeper on a clean macOS user account.
- [ ] Update the Sparkle appcast and confirm the `SUFeedURL` and `SUPublicEDKey` values match the published release.
- [ ] Publish a GitHub Release with release notes, supported macOS version, known limitations, and a signed/notarized artifact.
- [ ] Verify the README install link and CI badge after publishing.

## Release automation

- [ ] Keep the GitHub Actions release workflow on `v*` tags only.
- [ ] Store the stable signing certificate in `MACOS_CERTIFICATE_P12_BASE64` and `MACOS_CERTIFICATE_PASSWORD`.
- [ ] Store notarization credentials in `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`.
- [ ] Store the Sparkle Ed25519 private key in `SPARKLE_ED25519_PRIVATE_KEY` so the generated appcast stays signed.
- [ ] Upload the versioned app zip and `appcast.xml` together on every release so `releases/latest/download/appcast.xml` stays valid.

## Repository controls

- [ ] Require the **Clean Build & Test** check before merging to `master`.
- [ ] Protect `master` from direct pushes and require pull-request review.
- [ ] Keep Dependabot pull requests enabled and review dependency updates through the normal CI gate.
