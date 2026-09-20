//
//  Phase6Tests.swift
//  TilawahTests
//
//  Phase 6 unit tests (AGENTS.md §9): catalog snapshot persistence +
//  stale fallback, sleep-timer math, typo-tolerant search, and bulk
//  download-all selection. Deterministic, no network.
//

@testable import Tilawah
import Foundation
import SwiftData
import Testing

// MARK: - Catalog snapshot store

@Suite("CatalogSnapshotStore", .serialized)
struct CatalogSnapshotStoreTests {
    @MainActor
    private func makeStore() -> (CatalogSnapshotStore, ModelContainer) {
        let container = PersistenceFactory.makeContainer(inMemory: true)
        return (CatalogSnapshotStore(container: container), container)
    }

    @Test("empty store loads nil")
    @MainActor
    func loadsNilWhenEmpty() {
        let (store, _) = makeStore()
        #expect(store.load() == nil)
    }

    @Test("save then load round-trips fixtures")
    @MainActor
    func roundTrips() throws {
        let (store, _) = makeStore()
        let fixtures = try FixtureCatalogService.loadedFromFixtures()
        store.save(reciters: fixtures.reciters, suwar: fixtures.suwar, riwayat: fixtures.riwayat)
        let payload = try #require(store.load())
        #expect(payload.reciters.count == 2)
        #expect(payload.suwar.count == 3)
        #expect(payload.riwayat.count == 2)
        #expect(payload.reciters.first?.name == "أحمد بن علي العجمي")
    }

    @Test("refuses to persist an empty reciter list")
    @MainActor
    func refusesEmpty() {
        let (store, _) = makeStore()
        store.save(reciters: [], suwar: [], riwayat: [])
        #expect(store.load() == nil)
    }

    @Test("corrupt blobs load as nil, never crash")
    @MainActor
    func corruptLoadsNil() {
        let container = PersistenceFactory.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(PersistedCatalogSnapshot(
            recitersData: Data("not-json".utf8),
            suwarData: Data("not-json".utf8),
            riwayatData: Data("not-json".utf8)
        ))
        try? context.save()
        #expect(CatalogSnapshotStore(context: context).load() == nil)
    }
}

// MARK: - CatalogStore snapshot behavior

private struct SnapshotFailingService: QuranCatalogService {
    func fetchReciters(language: String) async throws -> [Reciter] { throw CatalogError.offline }
    func fetchReciter(id: Int, language: String) async throws -> Reciter { throw CatalogError.offline }
    func fetchSuwar(language: String) async throws -> [Surah] { throw CatalogError.offline }
    func fetchRiwayat(language: String) async throws -> [Riwayah] { throw CatalogError.offline }
}

@Suite("CatalogStore snapshot", .serialized)
struct CatalogStoreSnapshotTests {
    @Test("snapshot pre-populates the store as stale")
    @MainActor
    func snapshotPrepopulatesStale() throws {
        let container = PersistenceFactory.makeContainer(inMemory: true)
        let snapshots = CatalogSnapshotStore(container: container)
        let fixtures = try FixtureCatalogService.loadedFromFixtures()
        snapshots.save(reciters: fixtures.reciters, suwar: fixtures.suwar, riwayat: fixtures.riwayat)

        let store = CatalogStore(
            service: try FixtureCatalogService.loadedFromFixtures(),
            snapshotStore: CatalogSnapshotStore(container: container)
        )
        #expect(store.phase == .loaded)
        #expect(store.isLoaded)
        #expect(store.isStale)
        #expect(store.reciters.count == 2)
    }

    @Test("stale snapshot still refreshes from the network")
    @MainActor
    func staleRefreshes() async throws {
        let container = PersistenceFactory.makeContainer(inMemory: true)
        let fixtures = try FixtureCatalogService.loadedFromFixtures()
        CatalogSnapshotStore(container: container).save(
            reciters: fixtures.reciters, suwar: fixtures.suwar, riwayat: fixtures.riwayat
        )
        let store = CatalogStore(
            service: try FixtureCatalogService.loadedFromFixtures(),
            snapshotStore: CatalogSnapshotStore(container: container)
        )
        #expect(store.isStale)
        await store.load()
        #expect(store.phase == .loaded)
        #expect(!store.isStale)
        #expect(store.refreshError == nil)
    }

    @Test("network failure with a snapshot keeps data + records refresh error")
    @MainActor
    func failureKeepsSnapshot() async throws {
        let container = PersistenceFactory.makeContainer(inMemory: true)
        let fixtures = try FixtureCatalogService.loadedFromFixtures()
        CatalogSnapshotStore(container: container).save(
            reciters: fixtures.reciters, suwar: fixtures.suwar, riwayat: fixtures.riwayat
        )
        let store = CatalogStore(
            service: SnapshotFailingService(),
            snapshotStore: CatalogSnapshotStore(container: container)
        )
        await store.load()
        #expect(store.phase == .loaded)
        #expect(store.isLoaded)
        #expect(store.isStale)
        #expect(store.reciters.count == 2)
        #expect(store.refreshError?.isOffline == true)
    }

    @Test("successful load persists the snapshot")
    @MainActor
    func successPersists() async throws {
        let container = PersistenceFactory.makeContainer(inMemory: true)
        let store = CatalogStore(
            service: try FixtureCatalogService.loadedFromFixtures(),
            snapshotStore: CatalogSnapshotStore(container: container)
        )
        await store.load()
        #expect(store.phase == .loaded)
        let payload = try #require(CatalogSnapshotStore(container: container).load())
        #expect(payload.reciters.count == 2)
    }
}

// MARK: - Sleep timer math

@Suite("SleepTimer")
struct SleepTimerTests {
    @Test("minutes option has a deadline, off/end-of-surah do not")
    func deadlines() {
        #expect(SleepTimerOption.off.deadline() == nil)
        #expect(SleepTimerOption.endOfSurah.deadline() == nil)
        let now = Date()
        let deadline = try! #require(SleepTimerOption.minutes(15).deadline(from: now))
        #expect(abs(deadline.timeIntervalSince(now) - 900) < 1)
    }

    @Test("remaining counts down and floors at zero")
    func remaining() {
        let now = Date()
        #expect(SleepTimerMath.remaining(until: nil, now: now) == nil)
        #expect(SleepTimerMath.remaining(
            until: now.addingTimeInterval(90), now: now
        )! <= 90.001)
        #expect(SleepTimerMath.remaining(
            until: now.addingTimeInterval(-5), now: now
        ) == 0)
    }

    @Test("remaining labels are Arabic minute/second strings")
    func labels() {
        #expect(SleepTimerMath.remainingLabel(nil) == nil)
        #expect(SleepTimerMath.remainingLabel(90) == "1 د 30 ث")
        #expect(SleepTimerMath.remainingLabel(45) == "45 ث")
        #expect(SleepTimerOption.minutes(5).label == "بعد 5 دقيقة")
        #expect(SleepTimerOption.endOfSurah.label == "بعد نهاية السورة")
    }
}

// MARK: - Typo-tolerant search

@Suite("CatalogStore fuzzy search", .serialized)
struct CatalogFuzzySearchTests {
    @Test("single-letter typo still matches")
    @MainActor
    func typoMatches() async throws {
        let store = CatalogStore(service: try FixtureCatalogService.loadedFromFixtures())
        await store.load()
        // ي→و is one edit on the العجمي token.
        #expect(store.filteredReciters(query: "العجمو").map(\.id) == [1])
    }

    @Test("token order does not matter")
    @MainActor
    func tokenOrderIndependent() async throws {
        let store = CatalogStore(service: try FixtureCatalogService.loadedFromFixtures())
        await store.load()
        #expect(store.filteredReciters(query: "احمد العجمي").map(\.id) == [1])
        #expect(store.filteredReciters(query: "العجمي احمد").map(\.id) == [1])
    }

    @Test("every query token must match somewhere")
    @MainActor
    func allTokensMustMatch() async throws {
        let store = CatalogStore(service: try FixtureCatalogService.loadedFromFixtures())
        await store.load()
        #expect(store.filteredReciters(query: "احمد غيرموجود").isEmpty)
        #expect(store.filteredReciters(query: "غير موجود").isEmpty)
    }

    @Test("levenshtein distances are exact")
    func levenshtein() {
        #expect(CatalogStore.levenshtein("", "") == 0)
        #expect(CatalogStore.levenshtein("ا", "") == 1)
        #expect(CatalogStore.levenshtein("احمد", "احمد") == 0)
        #expect(CatalogStore.levenshtein("احمد", "احمر") == 1)
        #expect(CatalogStore.levenshtein("kitten", "sitting") == 3)
    }
}

// MARK: - Bulk download-all

@Suite("DownloadStore bulk", .serialized)
struct DownloadStoreBulkTests {
    @MainActor
    private func makeStore(localRoot: URL) -> DownloadStore {
        DownloadStore(
            container: PersistenceFactory.makeContainer(inMemory: true),
            localRoot: localRoot,
            makeSession: { delegate in URLSession(
                configuration: .ephemeral, delegate: delegate, delegateQueue: nil
            ) }
        )
    }

    private func sandboxRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func assets(count: Int) -> [AudioAsset] {
        (1 ... count).map { surah in
            AudioAsset(
                reciterID: 9, mushafID: 9, surahID: surah,
                reciterName: "ق", mushafName: "م", surahName: nil,
                streamURL: URL(string: "https://127.0.0.1:1/\(surah).mp3")!
            )
        }
    }

    @Test("downloadAll enqueues every missing asset once")
    @MainActor
    func enqueuesMissing() throws {
        let store = makeStore(localRoot: try sandboxRoot())
        let list = assets(count: 3)
        #expect(store.remainingDownloads(in: list) == 3)
        #expect(store.downloadAll(list) == 3)
        #expect(store.remainingDownloads(in: list) == 3) // none finished yet
        // Second tap enqueues nothing new (no duplicates).
        #expect(store.downloadAll(list) == 0)
        for asset in list { store.cancel(assetID: asset.id) }
    }

    @Test("already-completed assets are skipped")
    @MainActor
    func skipsCompleted() throws {
        let root = try sandboxRoot()
        let store = makeStore(localRoot: root)
        let list = assets(count: 2)
        // Seed a valid local file for the first asset: adopted, not requeued.
        let local = root.appendingPathComponent(list[0].relativeStoragePath)
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0xFF, count: PlaybackSource.minimumPlayableBytes + 10).write(to: local)
        #expect(store.downloadAll(list) == 1)
        #expect(store.status(for: list[0]) == .completed)
        for asset in list { store.cancel(assetID: asset.id) }
    }
}
