# Architecture

Mac Cleaner has two parts:

- **`App/MacCleaner`**: the SwiftUI app. Screens, view models, design system. No file-system logic.
- **`Packages/CleanerCore`**: a Swift package with all scanning, measuring, cleaning, safety and storage code. It never imports SwiftUI or AppKit, so it is fully unit-testable.

Contents:
1. [Use cases](#1-use-cases)
2. [System architecture](#2-system-architecture)
3. [Scan, then clean (sequence)](#3-scan-then-clean)
4. [Cleanup modules](#4-cleanup-modules)
5. [Smart Care concurrency](#5-smart-care-concurrency)
6. [App state](#6-app-state)
7. [Database](#7-database)
8. [Build and deployment](#8-build-and-deployment)
9. [Source map](#9-source-map)

The safety rules have their own document: [SAFETY.md](SAFETY.md).

---

## 1. Use cases

```mermaid
flowchart LR
    user(("User"))
    macos(("macOS<br/>services"))

    subgraph app["Mac Cleaner"]
        direction TB
        subgraph sc["Smart Care"]
            uc1["Run one-click scan"]
            uc2["Review summary and<br/>recommendations"]
            uc3["Apply recommended actions"]
        end
        subgraph cl["Cleanup and space tools"]
            uc4["Review cleanup categories"]
            uc5["See storage by type"]
            uc6["Find large, old and<br/>duplicate files"]
            uc7["Uninstall an app<br/>with its leftovers"]
            uc8["Clean selected items"]
        end
        subgraph setup["Setup"]
            uc9["Grant Full Disk Access"]
            uc10["Manage exclusions,<br/>dry run, activity log"]
        end
        inc1["Preview every item"]
        inc2["Confirm count and size"]
        inc3["Move to Trash"]
    end

    user --- uc1 & uc2 & uc3 & uc4 & uc5 & uc6 & uc7 & uc8 & uc9 & uc10
    uc3 -. include .-> inc2
    uc8 -. include .-> inc1
    uc8 -. include .-> inc2
    inc2 -. include .-> inc3
    uc9 --- macos
    inc3 --- macos
```

---

## 2. System architecture

```mermaid
flowchart TB
    subgraph P["Presentation (SwiftUI)"]
        direction LR
        V1["Smart Care"] ~~~ V2["Cleanup"] ~~~ V3["Storage · Large & old · Duplicates"] ~~~ V4["Uninstaller"] ~~~ V5["Settings · Onboarding"]
    end

    subgraph A["App layer (@MainActor @Observable)"]
        direction LR
        M1["SmartCareModel"] ~~~ M2["CleanupModel<br/>(selection, confirmation, perform)"] ~~~ M3["FindingsTool · StorageModel<br/>UninstallerModel"] ~~~ M4["AppSettings<br/>(exclusions, dry run, FDA)"]
    end

    subgraph C["CleanerCore (Swift package, no UI)"]
        direction TB
        O["ScanOrchestrator<br/>TaskGroup"] --> R["RuleEngine<br/>findings → Safe/Review"]
        O --> MODS["Cleanup modules (12)"]
        O --> SEC["SecurityScanner<br/>launch items · signatures"]
        O --> PERF["PerformanceChecker<br/>memory · CPU · disk"]
        TOOLS["Space and app tools<br/>Storage · LargeOld · Duplicates<br/>Uninstall · Leftovers"]
        SVC["CleanupService<br/>routes + logs"] --> MODS & TOOLS
        MODS & TOOLS --> RM["Remover<br/>the only code that removes"]
        RM --> SG["SafetyGuard<br/>path allowlist"]
        TOOLS --> AG["AppBundleGuard<br/>/Applications rule"]
        DB[("AppDatabase<br/>GRDB · SQLite")]
        SVC --> DB
    end

    subgraph OS["macOS"]
        direction LR
        FS["FileManager<br/>trashItem"] ~~~ LP["libproc · Mach · sysctl"] ~~~ SF["Security.framework<br/>spctl · xcrun simctl"] ~~~ TCC["Full Disk Access (TCC)"]
    end

    P --> A --> C --> OS
```

**Rules between layers**
- Views never call `FileManager`. They go through a model, which goes through `CleanerCore`.
- Every removal goes `CleanupModel.perform` → `CleanupService` → module `clean` → `Remover` (or `AppBundleGuard` for `.app` bundles) → `FileOperations`.
- Anything with side effects (file operations, commands, clock, open-file snapshot) is injected through `ModuleContext`, so tests can swap in fakes.

---

## 3. Scan, then clean

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant UI as SmartCareView
    participant VM as SmartCareModel / CleanupModel
    participant O as ScanOrchestrator
    participant M as Modules
    participant G as SafetyGuard
    participant OS as macOS

    rect rgba(128,128,128,0.08)
    note over U,OS: A. Scan (read-only)
    U->>UI: Scan
    UI->>VM: start()
    VM->>O: run(scope)
    par every module concurrently
        O->>M: scan()
        M->>G: validate(path)
        G-->>M: canonical path + identity
        M->>OS: stat, enumerate, measure
        OS-->>M: sizes, dates
        M-->>O: [Finding]
    end
    O-->>VM: progress … report + recommendations
    VM-->>UI: results (nothing changed yet)
    end

    rect rgba(215,25,33,0.06)
    note over U,OS: B. Clean (only after confirmation)
    U->>UI: Clean up (selection)
    UI->>VM: requestClean → CleanPlan
    VM-->>U: "Move 42 items (3.1 GB) to the Trash?"
    U->>VM: Confirm (and confirm again if permanent)
    VM->>M: CleanupService.clean(findings, mode)
    M->>G: revalidate(identity)
    G-->>M: still the same file?
    M->>M: in use? changed in last 10 min?
    M->>OS: trashItem(url)
    OS-->>M: new location in Trash
    M-->>VM: CleanResult (removed / skipped + reasons)
    VM->>VM: write activity log
    VM-->>U: "Freed 3.1 GB"
    end
```

---

## 4. Cleanup modules

Every cleaner implements one protocol. Path-based modules share `PathModuleSupport`, so they all follow the same scan and removal rules.

```mermaid
classDiagram
    class CleanupModule {
        <<protocol>>
        +category: CleanupCategory
        +scan() Finding[]
        +clean(findings, mode) CleanResult
    }
    class Finding {
        +category
        +target: path or command
        +group
        +reclaimableBytes
        +risk: safe or review
        +skipReason?
        +scannedIdentity?
    }
    class PathModuleSupport {
        +scan(sources) Finding[]
        +clean(findings, mode) CleanResult
    }
    class FindingBuilder {
        +make(url, group) Finding?
    }
    class Remover {
        +remove(findings, mode) CleanResult
    }
    class SafetyGuard {
        +validate(url) ValidatedPath
        +revalidate(ValidatedPath) ValidatedPath
    }
    class AppBundleGuard {
        +validate(app, running) ValidatedPath
    }
    class FileOperations {
        +moveToTrash(url)
        +deletePermanently(url)
    }

    CleanupModule <|.. CachesModule
    CleanupModule <|.. LogsModule
    CleanupModule <|.. TemporaryFilesModule
    CleanupModule <|.. BrokenDownloadsModule
    CleanupModule <|.. MailAttachmentsModule
    CleanupModule <|.. TrashModule
    CleanupModule <|.. XcodeJunkModule
    CleanupModule <|.. DeveloperCachesModule
    CleanupModule <|.. IOSUpdatesModule
    CleanupModule <|.. IOSBackupsModule
    CleanupModule <|.. InstallersModule
    CleanupModule <|.. BrokenStartupItemsModule
    CleanupModule <|.. LargeOldFilesModule
    CleanupModule <|.. DuplicatesModule
    CleanupModule <|.. AppUninstallModule
    CleanupModule <|.. AppLeftoversModule

    CachesModule --> PathModuleSupport
    DuplicatesModule --> PathModuleSupport
    AppUninstallModule --> PathModuleSupport
    AppUninstallModule --> AppBundleGuard
    PathModuleSupport --> FindingBuilder
    PathModuleSupport --> Remover
    FindingBuilder --> SafetyGuard
    Remover --> SafetyGuard
    Remover --> FileOperations
    CleanupModule ..> Finding
```

| Category | Module | Looks in | Risk |
|---|---|---|---|
| System cache | `CachesModule` | `~/Library/Caches/*` | Safe |
| Application logs | `LogsModule` | `~/Library/Logs`, `DiagnosticReports/*` | Safe |
| Temporary files | `TemporaryFilesModule` | `$TMPDIR/*` | Safe |
| Broken downloads | `BrokenDownloadsModule` | `~/Downloads/**/*.crdownload, .download, .part` | Safe |
| Mail attachments | `MailAttachmentsModule` | Mail's `Mail Downloads` | Review |
| Trash | `TrashModule` | `~/.Trash/*` (permanent only) | Review |
| Xcode junk | `XcodeJunkModule` | DerivedData, DeviceSupport, simulator caches, Archives, `simctl delete unavailable` | Safe / Review |
| Developer caches | `DeveloperCachesModule` | `~/.npm/_cacache`, `~/.gradle/caches`, … | Safe / Review |
| iOS update files | `IOSUpdatesModule` | `~/Library/iTunes/* Software Updates/*.ipsw` | Safe |
| iOS backups | `IOSBackupsModule` | `MobileSync/Backup/*` | Review |
| Old installers | `InstallersModule` | `~/Downloads/*.dmg, .pkg` older than 7 days | Review |
| Broken startup items | `BrokenStartupItemsModule` | `~/Library/LaunchAgents/*.plist` with missing program | Review |
| Large & old files | `LargeOldFilesModule` | Documents, Downloads, Desktop, Movies, Music, Pictures | Review |
| Duplicates | `DuplicatesModule` | same personal folders | Review |
| Applications | `AppUninstallModule` | `.app` bundles + `~/Library` leftovers | Review / Safe |
| Leftovers | `AppLeftoversModule` | `~/Library/*/<bundle id>` of uninstalled apps | Review |

---

## 5. Smart Care concurrency

```mermaid
flowchart LR
    S["run(scope)"] --> TG{{"withTaskGroup"}}
    TG --> J1["CachesModule.scan"]
    TG --> J2["LogsModule.scan"]
    TG --> J3["… 10 more modules"]
    TG --> SEC["SecurityScanner.scan<br/>(apps checked 6 at a time)"]
    TG --> PERF["PerformanceChecker.run<br/>(1 s CPU sample)"]
    J1 & J2 & J3 & SEC & PERF --> P["for await result<br/>progress(completed/total)"]
    P --> RE["RuleEngine.recommendations"]
    RE --> REP["SmartCareReport"]
```

- Child tasks run off the main actor. Progress is sent back to the `@MainActor` model.
- Cancelling the scan task stops long walks: `SizeCalculator` and the storage scanner check `Task.isCancelled`.
- External tools (`spctl`, `xcrun`) have a 30-second timeout and come from a fixed allowlist in `CommandRunner`.

---

## 6. App state

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Scanning: Scan
    Scanning --> Idle: Stop
    Scanning --> Ready: all modules finished
    Ready --> Scanning: Scan again
    Ready --> Confirming: Clean up (selection)
    Confirming --> Ready: Cancel
    Confirming --> ConfirmingPermanent: permanent items or toggle on
    ConfirmingPermanent --> Ready: Cancel, the default
    Confirming --> Cleaning: Move to Trash
    ConfirmingPermanent --> Cleaning: Delete permanently
    Cleaning --> Ready: result sheet + activity log
```

Models (`App/MacCleaner/Model`):

```mermaid
flowchart TB
    AM["AppModel"] --> ST["AppSettings<br/>database · exclusions · dry run · FDA status"]
    AM --> CM["CleanupModel<br/>findings · selection · pendingPlan · perform()"]
    AM --> SM["SmartCareModel<br/>phase · scope · recommendations"]
    AM --> TM["FindingsTool ×2<br/>large & old · duplicates"]
    AM --> UM["UninstallerModel<br/>apps · plan · leftovers"]
    AM --> STO["StorageModel"]
    SM & TM & UM -->|"requestClean(items)"| CM
    CM -->|"pendingPlan"| CONF["CleanConfirmation<br/>(one dialog flow for every screen)"]
```

---

## 7. Database

Stored at `~/Library/Application Support/Mac Cleaner/MacCleaner.sqlite` (GRDB, migration `v1`).

```mermaid
erDiagram
    actionLog {
        INTEGER id PK
        DATETIME date
        TEXT mode "moveToTrash | deletePermanently | dryRun"
        TEXT category
        TEXT target "path or command"
        INTEGER bytes
        TEXT outcome "movedToTrash | deleted | simulated | skipped"
        TEXT detail "reason when skipped"
        TEXT trashedPath
    }
    exclusion {
        TEXT path PK "canonical (realpath)"
        DATETIME addedAt
    }
    scanHistory {
        INTEGER id PK
        DATETIME startedAt
        DATETIME finishedAt
        INTEGER junkBytes
        INTEGER junkItemCount
        INTEGER threatCount
        INTEGER performanceIssueCount
    }
```

The tables are independent. Exclusions are read into `ModuleContext.exclusions` before each scan and checked again before each removal.

---

## 8. Build and deployment

```mermaid
flowchart LR
    subgraph build["Build and publish"]
        DEV["Developer Mac<br/>Xcode · XcodeGen · swift test"] -->|"git push / tag v*"| GH["GitHub repository"]
        GH --> CI["GitHub Actions<br/>macOS runner<br/>test → universal build"]
        CI -->|"make-dmg.sh"| REL["GitHub Releases<br/>ad-hoc signed .dmg + SHA-256"]
    end
    subgraph mac["User's Mac"]
        DL["Download .dmg"] --> GK["Gatekeeper<br/>first launch: Open Anyway"]
        GK --> APP["Mac Cleaner.app<br/>runs as the user, no helper"]
        APP --> DBF[("Local SQLite<br/>history · exclusions · log")]
        APP --> TCC["Full Disk Access (TCC)<br/>granted in System Settings"]
        TCC --> FILES["User files<br/>~/Library · Downloads · Trash · Xcode"]
    end
    REL --> DL
```

- **No sandbox, no privileged helper.** Mac Cleaner can only do what your user account can do.
- **Ad-hoc signature.** Each build has a new signature, so macOS may ask for Full Disk Access again after an update.
- **Updates:** download the new `.dmg` from Releases. Automatic updates (Sparkle) could come later.

---

## 9. Source map

```
App/MacCleaner/
  MacCleanerApp.swift        App entry, window, menu commands
  Sidebar/                   RootView (shell + confirmation), NavigationModel
  Model/                     AppModel, AppSettings, CleanupModel, SmartCareModel, ToolModels, CleanOutcome
  SmartCare/  Cleanup/  Space/  Apps/  Settings/  Onboarding/   Screens
  Shared/                    CleanConfirmation (alerts + result sheet), ToolList
  Design/                    Theme tokens, DotMatrix font, components
Packages/CleanerCore/Sources/CleanerCore/
  Safety/SafetyGuard.swift   Path allowlist
  FileSystem/                SizeCalculator, Remover, FileOperations, OpenFileSnapshot
  Modules/                   CleanupModule, PathModuleSupport, FindingBuilder, 12 junk modules, CleanupService, ModuleRegistry
  Space/                     StorageScanner, LargeOldFilesModule, DuplicatesModule, PersonalFolders
  Apps/                      AppInventory, AppBundleGuard, AppUninstallModule, AppLeftoversModule
  SmartCare/                 ScanOrchestrator, RuleEngine
  Security/                  LaunchItems, SignatureChecker, SecurityScanner
  Performance/               PerformanceChecker, PerformanceRules
  Store/                     AppDatabase, Records
  Model/                     Finding, CleanResult, CleanPlan
  Support/                   ModuleContext, CommandRunner, FullDiskAccess, AppNameResolver
Packages/CleanerCore/Tests/CleanerCoreTests/   131 Swift Testing tests (fixtures in $TMPDIR)
```
