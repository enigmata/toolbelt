# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project State

Early scaffold. `Specifications.md` defines the product requirements — read it before adding features. The Xcode project (`toolbelt.xcodeproj`) uses filesystem-synchronized groups (Xcode 16+ format): any file added under `toolbelt/` is automatically part of the target, no pbxproj edits needed.

## Commands

```sh
# Build for iOS (generic device; use a simulator destination when CoreSimulator works)
xcodebuild -project toolbelt.xcodeproj -scheme toolbelt -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# Build for iOS Simulator
xcodebuild -project toolbelt.xcodeproj -scheme toolbelt -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build

# Unit tests (Swift Testing, toolbeltTests target)
xcodebuild test -project toolbelt.xcodeproj -scheme toolbelt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:toolbeltTests

# UI tests (XCUITest, toolbeltUITests target; app launches with -uiTesting → in-memory store)
xcodebuild test -project toolbelt.xcodeproj -scheme toolbelt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:toolbeltUITests
```

`CODE_SIGNING_ALLOWED=NO` avoids needing a signing team for CLI builds. CI runs both test suites via `.github/workflows/ci.yml`. Note: SwiftData test helpers must keep the `ModelContainer` alive for the test body — returning only `mainContext` lets the store deallocate and crash.

## Architecture

Single iOS-only target (iPhone + iPad, deployment target iOS 26.0), SwiftUI + SwiftData, Swift 6 with default MainActor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

- `Models/` — SwiftData `@Model` classes. `ToolType` is a self-referential tree giving the taxonomy arbitrary depth (kind → type → subtype → size). `Tool` holds all attributes plus raw-string-backed enum accessors (`disposition`, `powerSource`). `ToolPhoto` stores image bytes with `.externalStorage`. All model properties are optional or defaulted deliberately: that keeps the schema CloudKit-compatible for the planned sync (CloudKit entitlements not yet added — requires a dev team).
- `Data/SeedData.swift` — default taxonomy inserted once into an empty store, at app launch from `toolbeltApp.init`.
- `Views/` — `ContentView` (NavigationSplitView sidebar: all/power/hand/sold/retired/stats) → `ToolListView` (search, grouped-by-category, persisted sort default via `@AppStorage`) → `ToolDetailView`; `ToolFormView` is the shared add/edit sheet; `PhotoImage` renders stored image data.
- Filtering/search runs in memory over `@Query` results, not in `#Predicate` — fine at personal-inventory scale; revisit if that assumption changes.

The app is iOS-only: UIKit-backed APIs (`EditButton`, `.tabViewStyle(.page)`, UIViewControllerRepresentable wrappers) are fine. Schema changes must stay CloudKit-safe: properties optional or defaulted, no `#Unique`, relationships optional.

Remaining and suggested work is tracked in `TODO.md` — check it before starting a feature, and check items off as they land.

## What Is Being Built

"toolbelt" — a personal inventory app for power tools and hand tools, targeting iOS (latest OS version only), using the latest strategic, long-term-supported Apple APIs and frameworks (i.e., SwiftUI and modern Swift).

Key requirements from `Specifications.md` that shape the architecture:

- **Hierarchical tool taxonomy**: power vs hand → type → subtype, with power tools further distinguished by corded vs battery (voltage/amp-hour variants). Ships with a complete editable set of default categories.
- **Tool records** carry rich attributes: photos, storage location, purchase info, brand, links to manufacturer docs and how-to videos (ideally auto-populated on add), and suggested companion tools.
- **Lifecycle dispositions**: currently-used tools are foremost; sold and retired tools remain accessible.
- **Primary UI**: a categorized, sortable list with roll-up statistics, drill-down to a detail view, and search across any attribute (including identify-by-photo if possible).
- **Adding a tool** should auto-populate details via automation (brand/model lookup, QR/bar code scan, photo of packaging).
- **Sync and offline**: inventory syncs across all of the user's devices (no sharing with other users), which points to CloudKit-backed storage (e.g., SwiftData + CloudKit). Most features must work offline and gracefully degrade, with changes syncing when connectivity returns.
