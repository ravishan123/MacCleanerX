# Contributing to Mac Cleaner

Thanks for helping! Bug reports, ideas, documentation and code are all welcome.

## Ground rules

- **Safety first.** A change that could make Mac Cleaner remove something it shouldn't will not be merged, however useful it is. Read [docs/SAFETY.md](docs/SAFETY.md) before touching anything that removes files.
- **Be kind.** Everyone here follows the [code of conduct](CODE_OF_CONDUCT.md).
- **Security problems go to [SECURITY.md](SECURITY.md)**, not public issues.

## Reporting a bug

Open an issue with the **Bug report** template. Include:
- your macOS version and Mac (Apple silicon or Intel)
- the Mac Cleaner version (Settings → About)
- what you did, what happened and what you expected
- relevant lines from **Settings → Activity**, if the bug involves cleaning

Please remove personal file names from logs and screenshots if you'd rather not share them.

## Suggesting a feature or cleanup category

Open an issue with the **Feature request** template. For a new cleanup category, tell us:
- the exact folder(s) involved
- why the files are safe to remove (who recreates them, and when)
- whether it should be **Safe** or **Review**

## Making a change

1. Fork and clone, then follow [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) to build.
2. Create a branch: `git checkout -b fix/short-description`.
3. Keep the change focused. Put logic in `CleanerCore` and keep the app layer to UI.
4. Add or update tests. They must only use `Fixture` folders and the fake Trash (see the test rules in the development guide).
5. Run everything:
   ```sh
   swift test --package-path Packages/CleanerCore
   xcodegen generate && xcodebuild -project MacCleaner.xcodeproj -scheme MacCleaner build
   ```
6. Update docs if behaviour changed, and add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
7. Open a pull request and fill in the template.

## Pull request checklist

- [ ] Tests pass and new behaviour is tested
- [ ] Nothing removes files except through `Remover` / `AppBundleGuard`
- [ ] New allowlist roots are as narrow as possible and inside the home folder
- [ ] Scans stay read-only (checked with `treeSnapshot()`)
- [ ] User-facing text is plain and honest
- [ ] VoiceOver labels and keyboard access for new UI
- [ ] Docs and changelog updated

## Commit messages

Short summary line in the imperative ("Add Gradle cache category"), then a blank line and details if needed.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
