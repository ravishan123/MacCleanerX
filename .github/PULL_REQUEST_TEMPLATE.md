## What and why

<!-- What does this change, and why? Link the issue if there is one: "Fixes #12" -->

## How it was tested

<!-- Tests added, and anything you checked by hand -->

## Checklist

- [ ] `swift test --package-path Packages/CleanerCore` passes and new behaviour is tested
- [ ] Nothing removes files except through `Remover` / `AppBundleGuard`
- [ ] New allowlist roots are as narrow as possible and inside the home folder
- [ ] Scans stay read-only (checked with `treeSnapshot()`)
- [ ] User-facing text is plain and honest
- [ ] VoiceOver labels and keyboard access for new UI
- [ ] Docs and `CHANGELOG.md` (Unreleased) updated
