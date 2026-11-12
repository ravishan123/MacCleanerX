# Diagrams

Every diagram in the project, in one place. They're written in [Mermaid](https://mermaid.js.org), so GitHub draws them and they're edited as plain text alongside the code.

## Index

| Diagram | Type | Where |
|---|---|---|
| User journey: download to first clean | Flowchart | [below](#user-journey) |
| Repository and dependencies | Flowchart | [below](#repository-and-dependencies) |
| How Mac Cleaner keeps your files safe | Flowchart | [README](../README.md#how-it-keeps-your-files-safe) |
| How it's built (overview) | Component | [README](../README.md#how-its-built) |
| Use cases | Use-case | [ARCHITECTURE §1](ARCHITECTURE.md#1-use-cases) |
| System architecture (layers) | Component | [ARCHITECTURE §2](ARCHITECTURE.md#2-system-architecture) |
| Scan, then clean | Sequence | [ARCHITECTURE §3](ARCHITECTURE.md#3-scan-then-clean) |
| Cleanup modules | Class | [ARCHITECTURE §4](ARCHITECTURE.md#4-cleanup-modules) |
| Smart Care concurrency | Flowchart | [ARCHITECTURE §5](ARCHITECTURE.md#5-smart-care-concurrency) |
| App state machine and models | State + flowchart | [ARCHITECTURE §6](ARCHITECTURE.md#6-app-state) |
| Database | Entity-relationship | [ARCHITECTURE §7](ARCHITECTURE.md#7-database) |
| Build and deployment | Deployment | [ARCHITECTURE §8](ARCHITECTURE.md#8-build-and-deployment) |
| The removal pipeline | Flowchart | [SAFETY](SAFETY.md#the-removal-pipeline) |
| SafetyGuard path checks | Decision tree | [SAFETY](SAFETY.md#safetyguard-the-path-allowlist) |
| AppBundleGuard | Decision tree | [SAFETY](SAFETY.md#appbundleguard-the-one-exception-for-applications) |
| First launch ("Open Anyway") | Flowchart | [USER_GUIDE](USER_GUIDE.md#first-launch-open-anyway) |
| Adding a cleanup category | Flowchart | [DEVELOPMENT](DEVELOPMENT.md#adding-a-cleanup-category) |
| Release pipeline | Flowchart | [RELEASING](RELEASING.md) |

## User journey

From finding Mac Cleaner to the first cleanup.

```mermaid
journey
    title Download to first clean
    section Get the app
      Open the Releases page: 5: User
      Download MacCleaner.dmg: 5: User
      Drag to Applications: 5: User
    section First launch
      macOS blocks the unnotarized app: 2: User, macOS
      Privacy & Security → Open Anyway: 3: User, macOS
      Grant Full Disk Access: 3: User, macOS
    section First clean
      Turn on dry-run mode (optional): 4: User
      Smart Care → Scan: 5: User, Mac Cleaner
      Review Safe and Review items: 4: User
      Confirm "Move N items to the Trash": 5: User, Mac Cleaner
      Check Settings → Activity: 4: User
```

## Repository and dependencies

```mermaid
flowchart LR
    subgraph repo["github.com/ravishan123/MacCleanerX"]
        direction TB
        YML["project.yml"] -->|"xcodegen generate"| XP["MacCleaner.xcodeproj<br/>(generated, not committed)"]
        APPSRC["App/MacCleaner<br/>SwiftUI"] --> XP
        PKG["Packages/CleanerCore<br/>Swift package"] --> XP
        TESTS["CleanerCoreTests<br/>134 tests"] -.->|"swift test"| PKG
        SCRIPTS["scripts/<br/>make-dmg.sh · make-icon.swift"]
        WF[".github/workflows<br/>ci.yml · release.yml"]
        DOCS["docs/<br/>guides · diagrams · website"]
    end
    GRDB["GRDB.swift 7<br/>(SwiftPM)"] --> PKG
    XP -->|"xcodebuild"| APPB["Mac Cleaner.app<br/>arm64 + x86_64"]
    SCRIPTS -->|"codesign · hdiutil"| DMG["MacCleaner-x.y.z.dmg<br/>+ .sha256"]
    APPB --> DMG
    WF -->|"on tag v*"| DMG
    DMG --> REL["GitHub Releases"]
    DOCS -->|"GitHub Pages"| SITE["ravishan123.github.io/MacCleanerX"]
    SITE -->|"Download button"| REL
```

## Editing diagrams

- Preview while editing: the [Mermaid live editor](https://mermaid.live), or VS Code with a Mermaid extension.
- Keep labels short, and use `<br/>` for line breaks.
- When code changes a flow shown here (a new module, a new safety rule), update the diagram in the same pull request.
