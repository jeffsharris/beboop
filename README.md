# Beboop

Tiny SwiftUI toy app that plays a quick boop sound. The repo is wired for a push-to-TestFlight workflow using GitHub Actions + Fastlane.

## Local Development
- Open `Beboop.xcodeproj` in Xcode.
- Set your signing team when prompted.
- Run on device or simulator.

## One-Time CI Setup (TestFlight)
1) **Create the app in App Store Connect**
   - Bundle ID: `com.jeffharris.beboop`
   - Platform: iOS

2) **Create an App Store Connect API key** (App Store Connect → Users and Access → Keys)
   - Role: Admin
   - Download the `.p8` file

3) **Create a private certificates repo for Match**
   - Example: `beboop-certificates`

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
   - `MATCH_PASSWORD`: encryption passphrase for Match
   - `TEAM_ID`: your Apple Developer Team ID
   - `FASTLANE_USER`: your Apple ID email (used for Match setup)
   - `ITC_TEAM_ID`: optional, only if you belong to multiple App Store Connect teams

6) **Add TestFlight testers** in App Store Connect.

After this, every push to `main` will build and upload a new TestFlight build.

## Fastlane
- `bundle exec fastlane beta` builds and uploads a TestFlight build.
- CI auto-sets build numbers using the GitHub run number.

## Notes
- `fastlane match appstore` only needs to run locally when you create or renew signing assets.
- Update the version in `Beboop/Info.plist` when shipping meaningful milestones.
