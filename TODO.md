# TODO

Remaining work from `Specifications.md`, plus suggested engineering tasks.

## Spec features not yet implemented

- [ ] **CloudKit sync** — add iCloud/CloudKit entitlements (requires a development team in Signing & Capabilities), configure the `ModelContainer` for CloudKit, and verify offline changes sync when connectivity returns. The schema is already CloudKit-compatible (all properties optional or defaulted).
- [ ] **Auto-populate on add** — pre-fill tool details from a distinguishing characteristic:
  - [ ] Brand + model number lookup
  - [ ] QR / bar code scan (VisionKit `DataScannerViewController` on iOS)
  - [ ] Photo of the product box / packaging
- [ ] **Identify tool by photo** — take a picture of a tool at hand and jump to its detail page (Vision / Core ML matching against stored photos).
- [ ] **Auto-populated links** — fetch manufacturer specs, documentation, and how-to video links when a tool is added (currently manual URL fields).
- [ ] **Companion tool suggestions** — suggest complementary tools; link to owned ones, or where to buy if not owned.
- [ ] **Taxonomy editing UI** — add / rename / delete types and subtypes (model supports it; no UI yet — the seeded defaults are fixed in practice).
- [ ] **Bulk disposition changes** — select multiple tools and mark sold/retired at once (currently one at a time via context menu).
- [ ] **Sort by any shared attribute** — spec calls for sorting on any attribute; currently type/name/brand/purchase-date (default persistence is done).
- [ ] **Deeper statistics roll-ups** — drill down like "18V 4Ah within Drills"; current stats stop at kind › category and battery platform.

## Known gaps in current scaffold

- [ ] **Camera capture for photos** — the form only supports the photo library picker; add direct camera capture on iOS.
- [ ] **Manage existing photos** — the edit form can only append new photos; add viewing/removing photos already attached to a tool.
- [ ] **Delete confirmation** — tool deletion from the context menu is immediate; add a confirmation dialog.

## Suggested engineering tasks

- [ ] **Unit tests** — model behavior (disposition/power-source accessors, `matches(_:)` search, age computation), seed idempotency; Swift Testing framework.
- [ ] **UI tests** — add/edit/delete flow, search, disposition changes.
- [ ] **CI** — GitHub Actions running the macOS and iOS builds (and tests) on push.
- [ ] **Code signing** — set a development team so simulator-free device installs and CloudKit work; removes the ad-hoc `codesign -s -` step for local macOS launches.
- [ ] **Icon Composer icon** — replace the generated PNG icon set with a layered `.icon` file for macOS 26 / iOS 26 liquid-glass rendering.
- [ ] **Export / backup** — CSV or JSON export of the inventory.
- [ ] **Layout polish** — consider a three-column split view (taxonomy tree in the sidebar), photo full-screen viewer, richer detail layout.
