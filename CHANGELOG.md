# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Fixed
- Cancel and Rescan now really stop a running scan. Before, the old scan kept walking the disk and new ones piled up, which could freeze the app.
- Storage and Large & old files are much faster: cloud-provider folders, other volumes and generated folders such as `node_modules` are skipped, and small files are dropped early.
- Smart Care and Cleanup run at most 4 scan tasks at a time, so the app stays responsive.
- Smart Care and Cleanup screens no longer search the whole findings list for every row.

## [1.0.0] - 2026-11-12

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
- App icon (drawn in code by `scripts/make-icon.swift`), download website, author credits in Settings → About.

[Unreleased]: https://github.com/ravishan123/MacCleanerX/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ravishan123/MacCleanerX/releases/tag/v1.0.0
