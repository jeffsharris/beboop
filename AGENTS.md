# Repository Guidelines

## Project Structure & Module Organization
This repository is currently empty (no source or test directories). When adding code, place application logic in `src/`, automated tests in `tests/`, static assets in `assets/`, and helper scripts in `scripts/`. Keep modules small and cohesive, and prefer one primary export per file.

## Build, Test, and Development Commands
No build or test commands are configured yet. When you add tooling, document the exact commands here.
Example format: `make test` - run the full test suite; `npm run dev` - start a local dev server.

## Coding Style & Naming Conventions
Use spaces, not tabs. Follow the standard formatter for the chosen language (for example, `gofmt`, `black`, or `prettier`) and add it to the repo when the language is selected. File names should be lowercase with dashes (for example, `user-service.ts`). Test files should mirror the source name with a suffix (for example, `user-service.test.ts`).

## Testing Guidelines
Place tests under `tests/` and mirror the `src/` tree. Prefer fast unit tests; add integration tests only for critical workflows. Name tests clearly with "should" or "when".

## Commit & Pull Request Guidelines
There is no commit history yet. Use short, imperative commit subjects (for example, `Add user model`), and include a scope if it clarifies intent (for example, `api: add health check`). PRs should include a brief summary, tests run, and screenshots for UI changes. Link relevant issues.

## Security & Configuration
Store local secrets in `.env` and commit a `.env.example` with safe defaults. Never commit credentials or tokens.

## Agent-Specific Instructions
For major changes, propose a plan before coding. Ask for confirmation before adding new production dependencies.
