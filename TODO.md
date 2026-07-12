# TODO

Remaining work from `Specifications.md`, plus suggested engineering tasks.

## Spec features not yet implemented

- [x] **CloudKit sync** — entitlements, CloudKit-backed `ModelContainer` (with local fallback for unsigned builds), CloudKit-safe seed idempotency + duplicate-root merge. *Manual step outstanding: build once to a device from Xcode with automatic signing so the `iCloud.com.enigmata.toolbelt` container registers with the team, then verify two-device sync; deploy the CloudKit schema to Production before release.*
- [x] **Auto-populate on add** — via the pluggable AI provider layer (`toolbelt/AI/`):
  - [x] Brand + model number lookup ("Look Up Brand + Model" in the add/edit form)
  - [x] QR / bar code scan (VisionKit `DataScannerViewController`, `BarcodeScannerView`)
  - [x] Photo of the product box / packaging (cloud providers only; on-device model is text-only)
- [x] **Identify tool by photo** — Vision feature prints compared against stored photos, on-device (`PhotoMatchService`, "Identify by Photo" sidebar item).
- [x] **Auto-populated links** — manufacturer/how-to links fetched during lookup, applied to empty fields only.
- [x] **Companion tool suggestions** — "Companions" section in the detail view; owned tools link to their detail page, others get a shop-search link.
- [x] **Taxonomy editing UI** — add/rename/delete types at any depth ("Taxonomy" sidebar item), with cascade-delete warnings.
- [x] **Bulk disposition changes** — Edit mode multi-select with a bottom-bar actions menu (mark in use/sold/retired, bulk delete behind confirmation).
- [x] **Sort by any shared attribute** — 10 sort keys + ascending/descending, persisted as default.
- [x] **Deeper statistics roll-ups** — stats rows drill kind → category → subtype → battery platform → tools (e.g. "18V 4Ah within Drills").

## Known gaps in current scaffold

- [x] **Camera capture for photos** — AVFoundation `CameraCaptureView` alongside the library picker.
- [x] **Manage existing photos** — edit form shows existing photos with remove buttons; deletion deferred to Save.
- [x] **Delete confirmation** — confirmation dialogs for single, bulk, and detail-view deletes, plus taxonomy deletes.

## Suggested engineering tasks

- [x] **Unit tests** — Swift Testing (`toolbeltTests`): model accessors, `matches(_:)`, age, seed idempotency + dedupe, sort/filter/group, CSV/JSON export, AI guard chain + DTO decoding. 41 tests.
- [x] **UI tests** — `toolbeltUITests`: add/search, delete-with-confirmation, disposition change (in-memory store via `-uiTesting`).
- [x] **CI** — `.github/workflows/ci.yml` builds + runs both suites on an iOS simulator.
- [x] **Code signing** — development team set; CloudKit entitlements wired (see CloudKit manual step above).
- [ ] **Icon Composer icon** — replace the generated PNG icon with a layered `.icon` file for iOS 26 liquid-glass rendering. *Manual authoring in the Icon Composer app.*
- [x] **Export / backup** — CSV + JSON export via ShareLink in the tool list.
- [x] **Layout polish** — full-screen zoomable photo gallery; stats drill-down; detail-view companions section.

## New follow-ups

- [ ] Live-test Claude / Gemini providers with real API keys (AI Settings → add key → Look Up); Foundation Models requires a device with Apple Intelligence enabled.
- [ ] Two-device CloudKit sync verification (see manual step above).
- [ ] Tune `PhotoMatchService` confidence buckets once real photo libraries exist.
- [ ] Consider persisting feature prints if identify-by-photo becomes slow at larger photo counts.
