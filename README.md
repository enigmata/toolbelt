# Toolbelt

A personal inventory app for power tools and hand tools. iOS 26+, SwiftUI + SwiftData, Swift 6.

## Features

- **Hierarchical taxonomy** — power vs hand → type → subtype → size, seeded with sensible defaults and fully editable in-app (Taxonomy sidebar item).
- **Rich tool records** — photos (library or camera), storage location, purchase info, brand, links, notes, lifecycle disposition (in use / sold / retired).
- **Search & sort** — search across every attribute; sort by ten different keys, ascending or descending, with your choice persisted as the default.
- **Statistics with drill-down** — roll-ups by kind, category, subtype, and battery platform (e.g. "18V 4Ah within Drills"), each level linking to the matching tools.
- **Bulk actions** — multi-select to change disposition or delete, always behind a confirmation.
- **AI auto-fill (pluggable provider)** — look up details from brand + model, a scanned barcode, or a photo of the packaging; auto-suggest manufacturer/how-to links and companion tools. Choose the backing model in AI Settings:
  - **Apple Intelligence (on-device)** — free, private, works offline (text-only)
  - **Claude (Anthropic)** — API key required
  - **Gemini (Google)** — API key required
  Suggestions only ever fill *empty* fields, after review. Everything degrades gracefully to manual entry offline.
- **Identify by photo** — photograph a tool at hand and jump to its record; Vision feature-print matching against stored photos, entirely on-device.
- **CloudKit sync** — private-database sync across your devices (SwiftData + CloudKit), offline-first with a local fallback store.
- **Export** — CSV or JSON of the inventory via the share sheet.

## Development

```sh
# Build
xcodebuild -project toolbelt.xcodeproj -scheme toolbelt \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build

# Unit tests (Swift Testing)
xcodebuild test -project toolbelt.xcodeproj -scheme toolbelt \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:toolbeltTests

# UI tests
xcodebuild test -project toolbelt.xcodeproj -scheme toolbelt \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:toolbeltUITests
```

CI runs both suites on every push (`.github/workflows/ci.yml`).

See `CLAUDE.md` for architecture notes, `Specifications.md` for product requirements, and `TODO.md` for remaining work.
