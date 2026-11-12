# Security policy

Mac Cleaner removes files, so we treat any way to make it remove the wrong thing as a security issue.

## Report privately

Please **don't open a public issue.** Use GitHub's private reporting instead:

**[Report a vulnerability](https://github.com/ravishan123/MacCleaner/security/advisories/new)** (Security tab → *Report a vulnerability*)

Include the Mac Cleaner and macOS versions, the steps or files needed to reproduce it, and what was removed (or could be).

We aim to reply within 7 days, publish a fix as soon as possible, and credit you in the release notes unless you'd rather stay anonymous.

## In scope

- Mac Cleaner removing, moving or changing anything outside the locations described in [docs/SAFETY.md](docs/SAFETY.md)
- Bypassing `SafetyGuard` or `AppBundleGuard`: path traversal, symlink or hard-link tricks, race conditions between scan and removal
- Removing an item that wasn't selected and confirmed, or permanently deleting without the second confirmation
- Running commands other than the allowlisted `xcrun`, `codesign` and `spctl`
- A scan changing anything on disk

## Out of scope

- The malware check not detecting a particular piece of malware. It's a heuristic check, not antivirus software (feature requests welcome).
- Problems that need an attacker who already controls your user account
- macOS asking for "Open Anyway" or Full Disk Access (expected for an ad-hoc signed app)

## Supported versions

Only the latest release gets security fixes.
