# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Swift unit tests for voice-command rewrite intent parsing and rewrite-text extraction.
- Swift unit tests for parsing explicit "type ... and press send" desktop-action intents.
- GitHub Actions CI for Swift build/test and script syntax checks.
- Contributor docs (`CONTRIBUTING.md`, issue templates, PR template).
- Security and conduct policies (`SECURITY.md`, `CODE_OF_CONDUCT.md`).

### Changed
- Moved rewrite intent parsing logic into a dedicated helper (`VoiceCommandIntents`) for easier testing and maintenance.
- Added a local deterministic bridge path for explicit type-and-send voice commands so the app no longer relies on model self-report for those actions.
- Added a response guardrail to avoid claiming unverified desktop actions as completed.
- Added `relayOnlyMode` (default `true`) so clawIsland forwards voice transcripts directly to OpenClaw unless local helpers are explicitly enabled.
