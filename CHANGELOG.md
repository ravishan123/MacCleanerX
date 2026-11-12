# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

## [1.0.0] - 2026-11-11

First public release.

### Added
- **Smart Care:** one scan for junk, startup-item warning signs and performance, with Safe/Review recommendations and scan history.
- **Cleanup** with 12 categories: system cache, application logs and crash reports, temporary files, broken downloads, Mail attachments, Trash, Xcode junk (including unavailable simulators), developer caches, iOS update files, iPhone/iPad backups, old installers and broken startup items.
- **Storage overview:** disk usage by type with the largest items per category.
- **Large & old files** in your personal folders.
- **Duplicates** confirmed with SHA-256; one copy always stays.
- **Uninstaller:** removes apps with their `~/Library` leftovers, and finds leftovers of deleted apps.
- **Startup check:** launch agents and daemons, code signatures and Gatekeeper status, worded as "No known threats found".
- **Performance checks:** memory pressure, CPU-heavy apps, startup items, disk space.
- **Safety:** path allowlist (`SafetyGuard`), separate `AppBundleGuard`, recheck before removal, skip of in-use and recently changed items, Trash by default, two-step confirmation for permanent deletion, dry-run mode, activity log and exclusions.
- Full Disk Access onboarding, dark mode, VoiceOver labels and keyboard navigation.
- Monochrome "Mono" design with dot-matrix type.
- Universal, ad-hoc signed `.dmg` with SHA-256 checksum, built by GitHub Actions.

[Unreleased]: https://github.com/ravishan123/MacCleaner/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ravishan123/MacCleaner/releases/tag/v1.0.0
