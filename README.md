# Beboop

Tiny SwiftUI toy app that plays a quick boop sound. The repo is wired for a push-to-TestFlight workflow using GitHub Actions + Fastlane.

## Local Development
- Open `Beboop.xcodeproj` in Xcode.
- Set your signing team when prompted.
- Run on device or simulator.

## Local Fastlane (Optional)
`bundle exec fastlane beta` builds and uploads to TestFlight, so it needs the same App Store Connect API values as CI.

One-time local setup:
```sh
gem install bundler -v 2.4.19 --user-install
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
bundle _2.4.19_ install
```

Per-session env vars:
```sh
export ASC_KEY_ID="..."
export ASC_ISSUER_ID="..."
export ASC_KEY_P8="$(base64 -i /path/to/AuthKey_XXXX.p8 | tr -d '\n')"
export MATCH_GIT_URL="git@github.com:jeffsharris/beboop-certificates.git"
export MATCH_PASSWORD="..."
export TEAM_ID="YS8CD5VJH4"
export FASTLANE_USER="jeff.s.harris@gmail.com"
```

## One-Time CI Setup (TestFlight)
1) **Create the app in App Store Connect**
   - Bundle ID: `com.jeffharris.beboop`
   - Platform: iOS

2) **Create an App Store Connect API key** (App Store Connect → Users and Access → Keys)
   - Role: Admin
   - Download the `.p8` file

3) **Create a private certificates repo for Match**
   - Example: `beboop-certificates`
   - This repo only stores encrypted signing assets (no API keys or secrets).

4) **Initialize signing assets locally**
   ```sh
   bundle install
   bundle exec fastlane match appstore
   ```

5) **Add GitHub Secrets** (Repo → Settings → Secrets and variables → Actions)
   - `ASC_KEY_ID`: API key ID
   - `ASC_ISSUER_ID`: API key issuer ID
   - `ASC_KEY_P8`: base64 of the `.p8` file
     - Example: `base64 -i AuthKey_XXXX.p8 | pbcopy`
   - `MATCH_GIT_URL`: HTTPS or SSH URL of the certs repo
    - `MATCH_GIT_PRIVATE_KEY`: deploy key private key for the certs repo
    - `MATCH_PASSWORD`: encryption passphrase for Match
    - `TEAM_ID`: your Apple Developer Team ID
    - `FASTLANE_USER`: your Apple ID email (used for Match setup)
    - `ITC_TEAM_ID`: optional, only if you belong to multiple App Store Connect teams

6) **Add TestFlight testers** in App Store Connect.
   - Internal groups can be set to auto-distribute new builds.

## Build Trigger Policy
Pushes to `main` only trigger a TestFlight build when the commit message includes `[testflight]`.
Manual builds are always available via **Actions → TestFlight → Run workflow**.

Examples:
- Normal push (no build): `git commit -m "Tweak UI spacing"`
- Trigger build: `git commit -m "Add new sound [testflight]"`

After this, pushes with the flag will build and upload a new TestFlight build.

## Fastlane
- `bundle exec fastlane beta` builds and uploads a TestFlight build.
- CI auto-sets build numbers using the GitHub run number.

## Notes
- `fastlane match appstore` only needs to run locally when you create or renew signing assets.
- Update the version in `Beboop/Info.plist` when shipping meaningful milestones.
- Aurora Voice audio notes and tuning workflow live in `docs/voice-aurora.md`.

## Troubleshooting
- **Invalid bundle / missing executable**: ensure `CFBundleExecutable` exists in `Beboop/Info.plist`.
- **Provisioning conflicts**: project must use manual signing (`CODE_SIGN_STYLE = Manual`).
- **Token invalid/expired**: confirm `ASC_KEY_ID`, `ASC_ISSUER_ID`, and base64 `ASC_KEY_P8` match the same API key and your system time is correct.
- **Ruby/Bundler errors in CI**: workflow pins Ruby 3.1 and Bundler 2.4.19 for Fastlane compatibility.
