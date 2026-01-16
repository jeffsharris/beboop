# Repository Guidelines

## Project Structure & Module Organization
Core app code lives in `Beboop/`, with assets in `Beboop/Assets.xcassets`, bundled resources in `Beboop/Resources`, and the Xcode project in `Beboop.xcodeproj`. CI and release automation live in `.github/workflows` and `fastlane/`. Keep Swift files focused and small.

## Build, Test, and Development Commands
- `bundle exec fastlane beta` - build and upload a TestFlight build.
- Open `Beboop.xcodeproj` in Xcode for local development and device runs.

## Coding Style & Naming Conventions
Use 4-space indentation and Swift conventions: `UpperCamelCase` for types, `lowerCamelCase` for functions and variables. Keep SwiftUI views in their own files and name them to match the view type (for example, `ContentView.swift`).

## Testing Guidelines
No test target is configured yet. When adding tests, use XCTest and mirror the app structure inside a dedicated test target.

## Commit & Pull Request Guidelines
Use short, imperative commit subjects (for example, `Add sound button`), and include a scope if it clarifies intent (for example, `ios: tune boop sound`). PRs should include a brief summary, tests run, and screenshots for UI changes. Link relevant issues.

## Security & Configuration
Store local secrets in `.env` and commit a `.env.example` with safe defaults. Never commit credentials or tokens.

## Agent-Specific Instructions
For major changes, propose a plan before coding. Ask for confirmation before adding new production dependencies. When requirements are under-specified, choose tasteful, playful defaults and minimize back-and-forth unless a decision is blocking.

## Agent Notes
- When adding new Swift files, register them in `Beboop.xcodeproj/project.pbxproj` (group + Sources build phase). If you only add the file on disk, CI builds will fail with missing symbol/compile errors.
- When asked to tag a build for TestFlight, use a `testflight-YYYYMMDD-HHMM` tag (no spaces) and include `[testflight]` in the commit message to trigger CI.
