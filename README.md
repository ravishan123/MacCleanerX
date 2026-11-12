<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/banner-dark.svg">
    <img alt="Mac Cleaner" src="docs/images/banner-light.svg" width="100%">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/ravishan123/MacCleaner/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/ravishan123/MacCleaner?label=download&color=000000"></a>
  <a href="https://github.com/ravishan123/MacCleaner/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/ravishan123/MacCleaner/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-000000">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-000000"></a>
</p>

# Mac Cleaner

A free, open-source Mac cleaner that finds junk, shows where your disk space goes, removes apps with their leftovers, and checks startup items for warning signs. **It never removes anything without asking you first.**

> [!WARNING]
> **Use at your own risk.** Mac Cleaner only touches your own files, moves items to the Trash by default and asks before every cleanup, but no cleaner can guarantee that removing a file is harmless. Keep a backup (for example with Time Machine). The malware check looks for common warning signs; it is **not antivirus software** and cannot promise your Mac is free of malware.

## Download

**[⬇ Download the latest version](https://github.com/ravishan123/MacCleaner/releases/latest)**: get `MacCleaner-<version>.dmg`, open it and drag **Mac Cleaner** to **Applications**.

Mac Cleaner is free and not notarized by Apple (that needs a paid developer account), so the first time you open it macOS blocks it. **[Follow these four steps once](docs/USER_GUIDE.md#first-launch-open-anyway)** to allow it. Then **[give it Full Disk Access](docs/USER_GUIDE.md#full-disk-access)** so it can check every folder.

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

## Features

| | |
|---|---|
| **Smart Care** | One Scan button checks junk, startup items and performance at the same time, then recommends what to do, labeled **Safe** or **Review**. |
| **Cleanup** | Twelve categories: system cache, app logs and crash reports, temporary files, broken downloads, Mail attachments, Trash, Xcode junk, developer caches (npm, Gradle, Cargo…), iOS update files, iPhone/iPad backups, old installers and broken startup items. |
| **Storage** | See what fills your disk (documents, images, videos, audio, archives, apps, developer files, caches, backups, Mail) and the largest items in each. |
| **Large & old files** | Big files, and files you haven't opened in months, in your personal folders. |
| **Duplicates** | Exact copies, confirmed byte for byte. One copy always stays. |
| **Uninstaller** | Remove an app together with the files it left in `~/Library`, and find leftovers of apps you deleted long ago. |
| **Startup check** | Flags startup items that are hidden, run from temporary folders, download code, or have broken signatures. Checks app signatures and Gatekeeper status. |
| **Performance** | Memory pressure, apps using a lot of CPU, how many items start at login, and free disk space. |

Also: dry-run mode, an activity log of everything moved or deleted, an exclusion list, dark mode, VoiceOver and full keyboard navigation.

## How it keeps your files safe

```mermaid
flowchart LR
    A["Scan<br/>(read-only)"] --> B["You review<br/>every item"]
    B --> C["Confirm:<br/>exact count and size"]
    C --> D{"Permanent?"}
    D -- "No (default)" --> E["Move to Trash"]
    D -- "Yes" --> F["Second confirmation<br/>(default: Cancel)"] --> G["Delete"]
    E --> H["Activity log"]
    G --> H
```

- **Scans never change anything.** Tests compare every file before and after each scan.
- **A hard allowlist.** Every path is resolved with `realpath` and must be inside a known cleanable folder. System folders, your home folder itself, symlinks that point elsewhere and SIP-protected files are always refused, and every item is checked again right before it's removed.
- **Trash first.** Permanent deletion is off by default, resets on every launch and asks twice.
- **Busy files are skipped.** Anything open in an app or changed in the last 10 minutes is left alone.
- **Honest numbers.** Sizes count the space you'd actually get back (APFS clones and hard links included).

Read the full **[safety design](docs/SAFETY.md)**.

## Documentation

| For users | For developers |
|---|---|
| [User guide](docs/USER_GUIDE.md): install, first launch, every screen, FAQ | [Development guide](docs/DEVELOPMENT.md): build, test, add a cleanup module |
| [Safety design](docs/SAFETY.md): what is and isn't touched | [Architecture](docs/ARCHITECTURE.md): diagrams of every layer |
| [Changelog](CHANGELOG.md) | [Releasing](docs/RELEASING.md): build the `.dmg` and publish |
| [Security policy](SECURITY.md) | [Contributing](CONTRIBUTING.md) · [Code of conduct](CODE_OF_CONDUCT.md) |

## Build from source

```sh
brew install xcodegen
git clone https://github.com/ravishan123/MacCleaner.git
cd MacCleaner
xcodegen generate
open MacCleaner.xcodeproj           # press ⌘R

swift test --package-path Packages/CleanerCore   # 131 tests, fixtures only
scripts/make-dmg.sh 1.0.0                        # → build/MacCleaner-1.0.0.dmg
```

Details in the [development guide](docs/DEVELOPMENT.md).

## Not included on purpose

- **Removing language files or "thinning" apps:** breaks app code signatures.
- **Cleaning inside the Photos library or Messages:** corrupts them.
- **RAM "boosters", maintenance scripts, system-wide cleaning:** need administrator rights and do little on modern macOS.
- **File shredding:** not reliable on SSDs.

## Contributing

Bug reports, ideas and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md). Found a way Mac Cleaner could remove something it shouldn't? Please follow the [security policy](SECURITY.md) instead of opening a public issue.

## License

[MIT](LICENSE). Uses [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT).
