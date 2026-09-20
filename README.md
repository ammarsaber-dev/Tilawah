# تلاوة — Tilawah

Native iOS audio app for streaming and offline listening to Quran recitations
from multiple reciters. Swift + SwiftUI, Arabic-first (RTL), iPhone-only.
First-party Apple frameworks only — no third-party dependencies.

- **Minimum:** iOS 26.0 · **SDK:** iOS 27.0 · **Xcode:** 27 (`27A266a`)
- **Status:** v1 in development on stacked pull requests (see below).

## What v1 does

- Browse and search the reciter catalog (full-surah recordings plus whatever
  collections the provider exposes — never a hardcoded "114 surahs each").
- Stream over the network; download surahs for offline in-app playback.
- Library: favorites, playlists, bookmarks, listening history (local only).
- Sleep timer, repeat modes, background audio with lock-screen controls.

## Content provider + rights

Audio catalog and streams come from the **MP3Quran API v3**
(`https://www.mp3quran.net`, docs at `https://www.mp3quran.net/ar/api`).
The app shows a provider attribution in Settings. Recordings are for
**personal use inside the app**; all rights remain with their owners.

No release clearance is claimed: technical download capability is not
permission to redistribute. Files are never re-hosted, shared, or exported
by the app. If you reuse this project, verify the provider's current terms
yourself.

## Privacy

- No accounts, no login, no cross-device sync, no backend.
- No subscriptions, no ads, no analytics, no external SDKs or services.
- Everything (catalog snapshot, library, downloads, playback position) stays
  on-device. Deleting the app deletes all of it.

## Offline storage (App Review note)

- Intentional downloads live in `Application Support/Audio/…` (private,
  non-purgeable), flagged `isExcludedFromBackup`.
- Never in `Documents/` (no Files app exposure), never in `Caches/`.
- No document browser, no file sharing, no audio export/share sheet.

This restricts *ordinary* access to the files. It is explicitly **not DRM**
and **not extraction-proof** — it only keeps downloads inside the app.

## Project layout

```
Tilawah/                 # App source (filesystem-synced group)
  Catalog/               # QuranCatalogService protocol + MP3Quran adapter,
                         # models, CatalogStore, persisted snapshot
  Playback/              # PlaybackController (one AVPlayer), queue, sleep timer
  Downloads/             # DownloadStore (background URLSession) + validation
  Persistence/           # SwiftData models + stores (library, playback, catalog)
  Presentation/          # SwiftUI: Explore / Library / Downloads + player
TilawahTests/            # Unit tests — deterministic fixtures, no network
TilawahUITests/          # UI smoke tests — launch + tab navigation
```

Architecture: Views + Stores + Services (not strict MVVM). Views observe
shared `@Observable` stores via `@Environment`; services hide behind
protocols. See `AGENTS.md` (authoritative working plan) for the full
contracts on identity, storage, UX, and validation.

## Build + test

```sh
# Build
xcodebuild -scheme Tilawah -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# Unit + UI tests (offline unit suite; UI suite drives the live app)
xcodebuild test -scheme Tilawah -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Use `xcrun simctl list devices` if the simulator name differs on your Mac.
CI (`.github/workflows/ci.yml`) resolves an available iPhone simulator
dynamically and runs the same scheme.

## Localization

UI language for v1 is **Arabic-only (RTL)**. All user-facing strings go
through `LocalizedStringKey`-compatible SwiftUI APIs with a
`Localizable.xcstrings` String Catalog (`Tilawah/Localizable.xcstrings`,
source language `ar`), so a future `en` localization is unblocked without
string-hardcoding debt. No English localization ships in v1.

## Contributing

Every change ships as its own pull request — no direct pushes to `main`:

1. Branch per change: `feature/<slug>`, `fix/<slug>`, `chore/<slug>`.
2. Small conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`).
3. Before pushing: build the scheme, run the unit tests, review the diff.
4. `git push -u origin <branch>`, then `gh pr create` with what/why,
   test evidence, and explicit notes on anything unverified.
5. Merge only after owner approval. Delete the branch after merge.
