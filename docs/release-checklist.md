# Release Checklist

Use this checklist for every public release. A green local build is not a release criterion by itself.

## Release type

Choose one:

- [ ] Unsigned technical preview
- [ ] Signed public release

## Before the release candidate

- [ ] `master` is green in the required **Clean Build & Test** GitHub Actions check.
- [ ] Run `xcodegen generate` from a fresh clone, then run the release build and full test suite.
- [ ] Run `xcodebuild -project Anchored.xcodeproj -scheme Anchored -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
- [ ] Run `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`.
- [ ] Test the installed release app in `/Applications`: menu bar startup, profile switch, focus prompt, countdown, dimming, and return-to-work.
- [ ] Test a browser with an active tab and with no active tab; confirm the app remains responsive when Accessibility is unavailable.
- [ ] Confirm cloud classification is off by default and that disabling it prevents remote requests.
- [ ] Confirm screenshots are not persisted and local context-history retention matches the selected setting.

## Session and lifecycle verification

- [ ] Return to work before countdown expiry; confirm dimming is cancelled.
- [ ] Leave and re-enter the same distraction; confirm an old callback cannot dim.
- [ ] Start and manually end a committed break.
- [ ] Let a committed break expire normally.
- [ ] Leave and return to work during a committed break; confirm the 15-second grace behavior.
- [ ] Sleep during a countdown and confirm no stale escalation occurs after wake.
- [ ] Lock during a break and confirm no stale resume occurs after unlock.
- [ ] Stop or quit during a pending timer and confirm no callback survives relaunch.
- [ ] Let an active session expire normally.
- [ ] End an active session before expiry and confirm it ends only once.
- [ ] Change the doomscroll threshold while a timer is pending.
- [ ] Disable Doomscroll Loop Breaker while its timer is pending.

## Display and overlay verification

- [ ] Trigger countdown and dimming on the built-in display.
- [ ] Trigger countdown and dimming on an external display.
- [ ] Confirm only the display containing the distraction is dimmed.
- [ ] Disconnect an external display while an overlay is visible.
- [ ] Confirm overlay windows remain click-through.
- [ ] Confirm Quit remains available while dimming is active.
- [ ] Confirm the dim-center panel appears on the correct display.

## Diagnostics verification

- [ ] Copy a report before any session activity.
- [ ] Copy a report after a normal session.
- [ ] Copy a report after a cancelled countdown.
- [ ] Copy a report after a stale callback rejection.
- [ ] Copy a report after sleep/wake or lock/unlock.
- [ ] Confirm the report identifies the relevant subsystem and event category.
- [ ] Confirm the buffer is bounded.
- [ ] Confirm copying the report does not alter or clear the buffer.
- [ ] Confirm no sensitive context appears.

## Verified in installed Release app

- [x] Quit available in the application menu.
- [x] Quit available during onboarding and permission flow.
- [x] Settings search returns real settings.
- [x] Search result navigation reaches the actual controls.
- [x] No-result search state renders clearly.
- [x] Clearing search restores the split view.
- [x] Diagnostic report copies successfully.
- [x] Diagnostic report remains sanitized and contains no raw titles, URLs, OCR text, typed text, screenshots, browsing history, or API keys.
- [x] Release launcher works under macOS Bash 3.2.

## Publishing

## Publishing - unsigned technical preview

- [ ] Update `CHANGELOG.md` and version metadata.
- [ ] Create an annotated semantic-version tag (`vMAJOR.MINOR.PATCH`).
- [ ] Build the Release app from a clean clone.
- [ ] Package the app as a versioned zip.
- [ ] Publish a GitHub Release with:
  - release notes
  - supported macOS version
  - known limitations
  - clear notice that the build is unsigned and not notarized
  - Gatekeeper installation instructions
  - build-from-source instructions
- [ ] Publish a SHA-256 checksum for the artifact.
- [ ] Verify the downloaded artifact on a separate macOS user account.
- [ ] Verify the README download and installation instructions.
- [ ] Do not advertise automatic updates as production-ready.

## Publishing - signed public release

- [ ] Update `CHANGELOG.md` and version metadata.
- [ ] Create an annotated semantic-version tag (`vMAJOR.MINOR.PATCH`).
- [ ] Archive, sign, and notarize the release build using the stable Developer ID Application certificate.
- [ ] Validate the artifact with Gatekeeper on a clean macOS user account.
- [ ] Update the Sparkle appcast.
- [ ] Confirm `SUFeedURL` and `SUPublicEDKey` match the published release.
- [ ] Publish a GitHub Release with release notes, supported macOS version, known limitations, and the signed/notarized artifact.
- [ ] Verify the README install link and CI badge after publishing.

## Release automation

- [ ] Keep the GitHub Actions release workflow on `v*` tags only.
- [ ] Store the stable signing certificate in `MACOS_CERTIFICATE_P12_BASE64` and `MACOS_CERTIFICATE_PASSWORD`.
- [ ] Store notarization credentials in `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`.
- [ ] Store the Sparkle Ed25519 private key in `SPARKLE_ED25519_PRIVATE_KEY` so the generated appcast stays signed.
- [ ] Pass `SPARKLE_UPDATES_ENABLED=YES` when archiving the tagged release so only published release builds expose Sparkle update checks.
- [ ] Upload the versioned app zip and `appcast.xml` together on every release so `releases/latest/download/appcast.xml` stays valid.

## Repository controls

- [ ] Require the **Clean Build & Test** check before merging to `master`.
- [ ] Protect `master` from accidental direct pushes where practical.
- [ ] Keep Dependabot pull requests enabled and review dependency updates through the normal CI gate.
- [ ] Use pull requests for release-bound changes, even when self-merging.
- [ ] Do not require an external reviewer until another maintainer exists.
