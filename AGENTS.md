# AGENTS.md — تلاوة (Tilawah)

> This file is the authoritative working plan for AI/human contributors in this repo.
> It records verified facts, owner decisions, and explicitly-marked provisional choices.
> Do not present provisional choices as owner-approved. Keep them reversible.

## 1. What this is

- Native iOS audio app: **تلاوة — Tilawah**.
- Swift + SwiftUI. Audio-only Quran recitations from multiple reciters.
- Core (confirmed): browse/search catalog, stream online, download for offline playback in-app.
- Downloads must live in private app storage, excluded from backup, with **no** Files app exposure,
  **no** Documents sharing, **no** export/share sheet for audio files.
- No UI prototype or inert buttons: every shipped screen must work against real provider data
  or clearly-handled empty/error/offline states.

## 2. Owner-confirmed decisions (2026-09-20, via direct Q&A)

These are approved. Do not re-ask unless blocked.

1. **Content scope v1: full-surah + extras.**
   Support full-surah recordings AND any additional collections the provider exposes
   (e.g. partial mushafs, mujawwad/murattal variants, Taraweeh-style or excerpt collections
   if present in API data). Do not hardcode "114 surahs for every reciter".
2. **UI language v1: Arabic-only (RTL).**
   Arabic-first UI, RTL layout, Arabic typography. All user strings localizable
   (String Catalogs). No English localization required for v1, but do not hardcode
   strings in a way that blocks a future `en` localization.
3. **Devices v1: iPhone-only.**
   Set `TARGETED_DEVICE_FAMILY = 1`. Do not build a dedicated iPad layout for v1.
   Keep layouts adaptive enough not to break if run on iPad.
4. **Accounts/monetization v1: none.**
   No login, no cross-device sync, no backend, no subscriptions, no ads,
   no analytics, no external services. Local-only persistence.
5. **Supported iOS versions v1: iOS 26 minimum, iOS 27 included.**
   Minimum deployment target = `26.0`; build with iOS SDK `27.0`.
   Lower the current `.pbxproj` default of `IPHONEOS_DEPLOYMENT_TARGET = 27.0`
   to `26.0` in the implementation step. iOS 26+ APIs (e.g. Liquid Glass styling)
   may be used with correct availability handling; no iOS 17–25 back-compat work.
6. **Architecture style: Views + Stores + Services (not strict MVVM).**
   No ViewModel-per-screen. Views observe shared `@Observable` stores directly
   (`PlaybackController`, `DownloadStore`, catalog/persistence stores) via
   `@Environment`; feature-local state in `@State` or small `@Observable` types;
   services hidden behind protocols. See §6.

Still unresolved (do not assume): required reciter list, visual branding beyond the name.
No subscriptions/ads/login/analytics to be invented.

## 3. Provisional engineering choices (NOT owner-approved, reversible)

> Prefix commits/discussions touching these with `PROVISIONAL:` until the owner confirms.

- **P1 — (SUPERSEDED by owner decision §2.5): deployment target is iOS 26.0.**
  The earlier provisional 17.0 is dropped. SDK stays 27.0. No back-compat work for iOS 17–25.
- **P2 — Primary provider: MP3Quran v3.** Fallback noted, not implemented in v1 unless needed.
  Rationale: verified full-surah single-file MP3s + `surah_list` per mushaf (see §5).
- **P3 — Persistence: SwiftData for catalog snapshot + user data** (favorites, playlists,
  bookmarks, history, download records, playback position).
  Rationale: first-party, works at iOS 17+, schema evolution via versioned models.
  Alternative (Codable JSON stores) allowed only if SwiftData proves problematic; do not add
  Core Data stack, Realm, or any third-party DB without owner approval.
- **P4 — No third-party dependencies for v1.** Pure Apple frameworks.
  Revisit only with purpose + license + maintenance + version-compat note per the brief.
- **P5 — Audio URL rule is a provider detail, not a global assumption:**
  `server + 3-digit-zero-padded-surah + .mp3` (e.g. `…/akdr/001.mp3`). Verified 2026-09-20.
  Must live behind the provider adapter so a server naming change does not touch playback.

## 4. Verified toolchain (2026-09-20)

Distinguish installed vs. latest-available. Both were checked today.

- **Installed (this Mac):** Xcode `27.0 (27A266a)`, Swift `Apple Swift 6.4
  (swiftlang-6.4.0.34.1 clang-2100.3.34.1)`, iOS SDK `27.0`, Simulator runtime
  `iOS 27.0 (24A434)`, macOS `27.0 (26A428)`.
  Commands used: `xcodebuild -version`, `swift --version`, `xcodebuild -showsdks`,
  `xcrun simctl list runtimes`.
- **Latest stable per official Apple source:** Xcode `27 (27A266a)` released **2026-09-14**,
  with iOS/iPadOS `27.0`, macOS `27.0`. Source: `https://developer.apple.com/news/releases/`
  (lists "Xcode 27 (27A266a) — September 14, 2026"). Installed build **matches** latest stable.
  Older references (e.g. Wikipedia/Xcode 26.6) are stale; trust developer.apple.com.
- **SDK vs. deployment target:** SDK = 27.0 (what we build with). Deployment target = `26.0`
  (who can install; owner-confirmed §2.5). These are separate; do not conflate them.
- **Existing project state:** template app (`TilawahApp.swift`, `ContentView.swift`),
  filesystem-synchronized group, `SWIFT_VERSION = 5.0`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, bundle `dev.ammarsaber.Tilawah`,
  `DEVELOPMENT_TEAM = KG6ZP8B8D2`. Keep signing user-configurable; do not invent teams/credentials.
- **Framework direction (stable, first-party, availability-checked against iOS 17):**
  SwiftUI, Observation (`@Observable`), structured concurrency (`async/await`, actors),
  `AVFoundation`/`AVFAudio` (`AVPlayer`), `MediaPlayer` (Now Playing + remote commands),
  Foundation networking (`URLSession`, background `URLSessionDownloadTask`),
  SwiftData. No beta APIs. No deprecated APIs. iOS 26+ APIs (e.g. Liquid Glass styling)
  may be used with correct availability handling; no iOS 17–25 back-compat work.

## 5. Verified provider integration (live responses checked 2026-09-20)

### 5.1 Primary: MP3Quran v3 — `https://www.mp3quran.net/api/v3/...`

> Host matters: bare `https://mp3quran.net/api/...` returns `301` (Cloudflare).
> Use `https://www.mp3quran.net/api/v3/...` with redirect-following client.

Verified live (curl, HTTP 200):

- `GET /reciters?language=ar` → `{ "reciters": [{ id, name, letter, date?, moshaf: [...] }] }`
- `GET /reciters?language=ar&reciter=1` → single reciter + mushafs.
- `GET /suwar?language=ar` → `{ "suwar": [{ id: 1..114, name, start_page, end_page, makkia, type }] }`
- `GET /riwayat?language=ar` → `{ "riwayat": [{ id, name }] }` (e.g. 1 = حفص عن عاصم).
- Mushaf object: `{ id, name, rewaya_id?, server, surah_total, moshaf_type, surah_list }`.
  Example: reciter 1 / mushaf 1: `server = https://server6.mp3quran.net/akdr/`,
  `surah_list = "1,2,…,114"`. Reciter 100 proves partial lists exist (113 surahs, missing 2).
- Audio asset construction verified: `HEAD https://server6.mp3quran.net/akdr/001.mp3`
  → `200`, `content-type: audio/mpeg`, `accept-ranges: bytes`; `Range: bytes=0-1` → `206`.
  Supports streaming, seeking, and resume. AlQuran CDN ayah files also verified
  (`accept-ranges: bytes`), but ayah-granularity is out of scope for the v1 full-surah player.

What MP3Quran does **not** guarantee (do not assume):

- Every reciter has all 114 surahs (false — see reciter 100).
- Multiple quality levels per recording (not in `moshaf` payload; servers are single-bitrate).
- Duration, file size, artwork, verse timestamps in catalog responses (absent).
- Unlimited use: free API ≠ unlimited quota; cache catalog aggressively, no polling loops.
- Redistribution rights: technical download capability ≠ permission to redistribute.
  Rights status is **unresolved**. Ship streaming + private in-app offline copies for personal use,
  attribute MP3Quran in-app + README, do not claim release clearance, do not re-host files.

Docs: `https://www.mp3quran.net/ar/api` (Arabic; `…/eng/api` for English field names).

### 5.2 Evaluated alternatives (not primary for v1)

- **AlQuran.cloud** (`https://api.alquran.cloud/v1/...`, CDN `cdn.islamic.network`):
  verified `GET /surah/1/ar.alafasy` (ayah-level `audio` + `audioSecondary` 64/128kbps)
  and `GET /edition/format/audio` (~15+ reciters). Model is per-ayah, not per-surah-file,
  so it would require gapless ayah concatenation for surah playback — rejected as primary
  for v1. Keep as documented fallback. Terms (2026-06-14, `…/terms-and-conditions`):
  free key-less API with soft per-IP rate limit; audio licensed for free non-commercial
  redistribution/personal use; reciter copyrights retained; attribution required.
- **Quran.foundation** (`https://api-docs.quran.foundation/`): requires client credentials;
  never embed a confidential secret in the app; would need a backend (out of scope for
  no-backend v1). Not used.

### 5.3 Domain model + stable identity (required)

Isolate provider networking/models behind a small `QuranCatalogService` protocol.
Preserve these as distinct entities (never collapse):

`Provider → Reciter → Mushaf (recording collection) → Riwayah → Surah → AudioAsset`

- `AudioAsset.id` (stable, persisted): `mp3quran:v3:reciter:{reciterID}:mushaf:{mushafID}:surah:{surahID}`.
  Different recordings of the same surah must never collide.
- Audio URL is derived, never used as identity; persist `relativeStoragePath`, never absolute
  sandbox paths.
- `surah_list` is a comma-separated string — parse defensively (whitespace, trailing commas,
  non-numeric tokens). Show only available surahs. Parse `surah_total` as advisory only;
  trust the parsed list.
- Catalog refresh must never orphan downloads: downloads carry their own metadata snapshot
  (reciter/mushaf/surah names, server, relative path) so airplane-mode cold launch works.

## 6. Architecture (pragmatic, testable, no over-layering)

**Style (owner-confirmed §2.6): Views + Stores + Services — not strict MVVM.**
No ViewModel-per-screen: a per-screen VM duplicating store state creates two sources
of truth and sync bugs. Instead, views observe shared `@Observable` stores directly
via `@Environment` (`PlaybackController`, `DownloadStore`, catalog/persistence stores);
feature-local state lives in `@State` or small `@Observable` types owned by the view;
services hide behind protocols. State-ownership rule: use the narrowest tool that fits
(`@State` local → `@Binding` child-mutates-parent → injected `@Observable` reference →
`@Environment` only for truly shared app services). Testability comes from
protocol-isolated services and actor stores, not from VMs.

- `TilawahApp` — composition root. Builds service graph once, injects via environment.
- `Presentation` (SwiftUI) — Home / Explore / Library / Downloads + mini-player + expanded player.
  All UI state on `@MainActor`. No networking/file I/O on the main actor.
- `Catalog` — `QuranCatalogService` protocol + `MP3QuranService` adapter (URLSession + Codable
  with tolerant optionals) + in-memory cache + SwiftData snapshot. Fixture-backed fake for tests.
- `Playback` — single `PlaybackController` (`@Observable`, `@MainActor`), one `AVPlayer` only.
  Local file preferred when validated; else stream. Persists queue + position; restores session
  on relaunch **without auto-playing**. Background audio + lock-screen/headphone commands +
  interruptions/route changes via `AVAudioSession`, `MPNowPlayingInfoCenter`,
  `MPRemoteCommandCenter`. No crossfade/trim of recitations. No verse-level navigation
  without verified timing data. Repeat + sleep-timer + bookmarks/playlists are allowed
  additions, secondary to core transport.
- `Downloads` — separate `DownloadStore` actor + background `URLSessionDownloadDelegate`.
  Reconciles task identity after relaunch; max ~3 concurrent; no duplicates;
  pause/resume only with valid resume data else restart; validates HTTP + content
  (`audio/mpeg`, non-trivial length) before atomic move into
  `Application Support/Audio/<reciterID>/<mushafID>/<surahID>.mp3`; sets
  `isExcludedFromBackup`; never marks partial files playable.
- `Persistence` — SwiftData models for catalog snapshot, favorites, playlists, history,
  bookmarks, download records, playback state. Versioned schema; stale-catalog and
  missing-file reconciliation on launch.

Concurrency: structured concurrency throughout; actors for stores; `async/await`, never
semaphores/blocking calls on main. File work off-main.

## 7. Offline storage + privacy rules (App Review–sensitive)

- Location: `Application Support/Audio/…` (persistent, private, non-purgeable).
  Never `Caches/` for intentional downloads. Never `Documents/` (avoids Files exposure).
- `URLResourceValues.isExcludedFromBackup = true` on the audio subtree.
- No `UISupportsDocumentBrowser`, no `UIFileSharingEnabled`, no `LSSupportsOpeningDocumentsInPlace`,
  no audio export/share activity. State this in README as restriction of ordinary access,
  explicitly **not** DRM and **not** extraction-proof.
- Deleting a download ≠ deleting a favorite/playlist entry. If the playing asset's file is
  deleted, coordinator pauses/seeks safely and updates UI state.
- Settings: Wi-Fi-only downloads toggle; storage usage (measured via file sizes, not estimates);
  per-asset download + delete; indeterminate progress when length unknown.

## 8. UX / accessibility contract

- Arabic RTL, calm restrained styling, strong light/dark, Dynamic Type, VoiceOver labels in Arabic,
  sufficient contrast, Reduce Motion respected. No invented popularity/editorial/biographies/photos.
  Neutral placeholder where artwork is absent (there is no provider artwork).
- Every async surface needs loading / empty / error / offline / retry states.
- Background audio entitlement: `UIBackgroundModes = audio`; `AVAudioSession.Category.playback`;
  InfoPlist microphone usage strings are forbidden (no recording). Lock-screen metadata in Arabic.

## 9. Validation

- Unit tests (deterministic fixtures, no network): provider decoding incl. missing optionals;
  `surah_list` parsing edge cases; stable asset IDs; local-vs-remote selection;
  download completion/failure/retry/cancel/duplicate-prevention; favorites/playlists/bookmarks/
  position persistence; deletion + missing-file reconciliation.
- Live smoke checks (separate target/scheme step, never in unit tests): browse → stream →
  download → terminate → relaunch → airplane mode → play offline → seek → verify saved progress
  → delete → verify UI. Plus background/lock-screen/interruption, Arabic layout, large text.
  State simulator vs. physical-device results honestly. Never claim an unperformed build/test passed.
- Build/test commands (Xcode 27):
  `xcodebuild -scheme Tilawah -destination 'platform=iOS Simulator,name=iPhone 17' build`
  `xcodebuild test -scheme Tilawah -destination 'platform=iOS Simulator,name=iPhone 17'`
  (Update simulator name to an installed runtime; `xcrun simctl list devices` is authoritative.)

## 10. Sources

- Apple releases (latest-stable evidence): `https://developer.apple.com/news/releases/`
- MP3Quran API docs: `https://www.mp3quran.net/ar/api` and `https://www.mp3quran.net/eng/api`
- Live endpoints: `https://www.mp3quran.net/api/v3/reciters?language=ar`,
  `…/suwar?language=ar`, `…/riwayat?language=ar`
- AlQuran.cloud API: `https://alquran.cloud/api`, CDN: `https://alquran.cloud/cdn`,
  Terms: `https://alquran.cloud/terms-and-conditions`
- Quran.foundation docs: `https://api-docs.quran.foundation/`

## 11. Forbidden

- No subscriptions, ads, login, analytics, external SDKs, or backend in v1.
- No secrets in the app or repo. No invented team IDs/credentials.
- No beta/deprecated APIs. No third-party package without purpose+license+maintenance+compat note.
- No claiming provider rights clearance, unlimited quota, or verse-level features without timing data.
- No `TODO` replacing core functionality in shipped code.

## 12. Contribution workflow (owner-required: branch → push → PR per change)

Every change and every new feature ships as its own pull request. No direct pushes to `main`.

- **Branch per change:** `feature/<short-slug>`, `fix/<short-slug>`, or `chore/<short-slug>`
  (e.g. `feature/catalog-service`, `fix/download-retry`). One concern per branch.
- **Commits:** small, conventional (`feat:`, `fix:`, `chore:`, `docs:`, `test:`),
  each building cleanly. Prefix `PROVISIONAL:` where §3 applies.
- **Before pushing:** build the scheme, run the unit tests, `git status`/`git diff` review.
  Never commit secrets, credentials, `.env`, or user-specific signing overrides.
- **Push + PR via `gh`:** `git push -u origin <branch>`, then `gh pr create` with:
  a clear title, what/why summary, test evidence (commands + simulator/device result),
  and explicit notes on anything unverified. Link any related issue/phase.
- **Professional bar:** PRs stay focused and reviewable; CI (once added) must be green;
  merge only after owner approval (squash unless history matters). Delete the branch after merge.
