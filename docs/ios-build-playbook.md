# iOS Build Playbook (Fastlane + Match)

This file captures the build pipeline setup and the fixes required to get a SwiftUI app reliably building and uploading to TestFlight.

## Repo Separation (Why Two Repos)
- `beboop` (public): app code + CI workflow. This repo holds GitHub Actions secrets for App Store Connect and Match.
- `beboop-certificates` (private): encrypted signing assets managed by Fastlane Match (certs + provisioning profiles). No API keys live here.

## One-Time Human Setup
1) App Store Connect: create the app record and accept the Free Apps Agreement.
2) App Store Connect API key: create an Admin key and download the `.p8` file once.
3) TestFlight: create the internal group (e.g., `Family`) and add testers.

## Secrets and Where They Belong
**GitHub Actions secrets in `beboop`:**
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64, no newlines)
- `MATCH_GIT_URL` (private certs repo)
- `MATCH_GIT_PRIVATE_KEY` (deploy key private key for the certs repo)
- `MATCH_PASSWORD` (Match encryption passphrase)
- `TEAM_ID`, `FASTLANE_USER`, `ITC_TEAM_ID` (optional)

**Local env exports (optional for local Fastlane):**
Same values as above so `bundle exec fastlane beta` runs without prompts.

## CI Expectations (Workflow)
- Use Xcode 16 on `macos-14` runners (explicit `xcode-select` step).
- Pin Ruby 3.1 to avoid dependency issues with Fastlane.
- Bundler version must match `Gemfile.lock` (2.4.19).

## Code-Level Fixes Required
**Xcode project:**
- Add a shared scheme at `Beboop.xcodeproj/xcshareddata/xcschemes/Beboop.xcscheme` so CI can build.
- Force manual signing in the project (`CODE_SIGN_STYLE = Manual`). This avoids conflicts with explicit profile selection in CI.

**Info.plist:**
- `CFBundleExecutable = $(EXECUTABLE_NAME)` and `CFBundlePackageType = APPL` to prevent “bundle executable missing” errors.
- `ITSAppUsesNonExemptEncryption = false` to bypass export compliance prompts.

**Fastlane lane:**
- Use Match’s profile mapping and pass it into `build_app`:
  - `MATCH_PROVISIONING_PROFILE_MAPPING`
  - `PROVISIONING_PROFILE_SPECIFIER='match AppStore …'`
  - `export_options: { provisioningProfiles: mapping }`
- Quote `CODE_SIGN_IDENTITY='Apple Distribution'` to avoid `xcodebuild: Unknown build action 'Distribution'`.
- `upload_to_testflight(groups: ["Family"])` to auto-distribute builds.

## Local Debugging (Build Only)
Build an archive without uploading:
```sh
xcodebuild -scheme Beboop -project ./Beboop.xcodeproj \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/Beboop.xcarchive \
  archive
```
Then verify the app bundle contains the executable:
```sh
ls /tmp/Beboop.xcarchive/Products/Applications/Beboop.app
```

## Common Errors and Fixes
- **“Invalid Bundle: does not contain a bundle executable”**
  - Add `CFBundleExecutable` to Info.plist.
- **“Unknown build action 'Distribution'”**
  - Quote `CODE_SIGN_IDENTITY='Apple Distribution'` in `xcargs`.
- **“Conflicting provisioning settings”**
  - Set `CODE_SIGN_STYLE = Manual` in the project.
- **API token invalid/expired**
  - Check system time, confirm key/issuer match, base64 `.p8` with no newlines.
- **Ruby/Bundler errors**
  - Pin Ruby 3.1 in CI and keep Bundler at 2.4.19.
- **Match encryption errors locally**
  - Set `MATCH_FORCE_LEGACY_ENCRYPTION=1` during initial setup.

Use this playbook as the baseline for future apps with the same workflow.
