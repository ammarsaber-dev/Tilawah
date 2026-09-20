//
//  CatalogStoreTests.swift
//  TilawahTests
//
//  Phase 2 unit tests: store lifecycle (idle → loading → loaded/failed),
//  caching, retry/reload, Arabic search normalization, and lookups.
//  Deterministic, no network.
//

@testable import Tilawah
import Foundation
import Testing

/// Counts service calls to verify caching behavior.
private struct CountingService: QuranCatalogService {
    let inner: any QuranCatalogService
    let calls: LockedCounter

    func fetchReciters(language: String) async throws -> [Reciter] {
        await calls.increment()
        return try await inner.fetchReciters(language: language)
    }

    func fetchReciter(id: Int, language: String) async throws -> Reciter {
        try await inner.fetchReciter(id: id, language: language)
    }

    func fetchSuwar(language: String) async throws -> [Surah] {
        try await inner.fetchSuwar(language: language)
    }

    func fetchRiwayat(language: String) async throws -> [Riwayah] {
        try await inner.fetchRiwayat(language: language)
    }
}

private actor LockedCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct FailingService: QuranCatalogService {
    let error: CatalogError
    func fetchReciters(language: String) async throws -> [Reciter] { throw error }
    func fetchReciter(id: Int, language: String) async throws -> Reciter { throw error }
    func fetchSuwar(language: String) async throws -> [Surah] { throw error }
    func fetchRiwayat(language: String) async throws -> [Riwayah] { throw error }
}

@Suite("CatalogStore", .serialized)
struct CatalogStoreTests {
    @Test("starts idle and loads fixtures to loaded")
    @MainActor
    func loadsToLoaded() async throws {
        let store = CatalogStore(service: try FixtureCatalogService.loadedFromFixtures())
        #expect(store.phase == .idle)
        #expect(!store.isLoaded)
        await store.load()
        #expect(store.phase == .loaded)
        #expect(store.isLoaded)
        #expect(store.reciters.count == 2)
        #expect(store.suwar.count == 3)
        #expect(store.riwayat.count == 2)
    }

    @Test("second load is cached (no refetch)")
    @MainActor
    func cachesAfterLoad() async throws {
        let counter = LockedCounter()
        let service = CountingService(
            inner: try FixtureCatalogService.loadedFromFixtures(), calls: counter
        )
        let store = CatalogStore(service: service)
        await store.load()
        await store.load()
        #expect(await counter.value == 1)
    }

    @Test("reload forces a refetch")
    @MainActor
    func reloadRefetches() async throws {
        let counter = LockedCounter()
        let service = CountingService(
            inner: try FixtureCatalogService.loadedFromFixtures(), calls: counter
        )
        let store = CatalogStore(service: service)
        await store.load()
        await store.reload()
        #expect(await counter.value == 2)
    }

    @Test("service failure surfaces as failed phase with the error")
    @MainActor
    func failurePhase() async {
        let store = CatalogStore(service: FailingService(error: .offline))
        await store.load()
        #expect(store.phase == .failed(.offline))
        #expect(store.failure?.isOffline == true)
        #expect(!store.isLoaded)
    }

    @Test("empty query returns all reciters in provider order")
    @MainActor
    func emptyQueryReturnsAll() async throws {
        let store = CatalogStore(service: try FixtureCatalogService.loadedFromFixtures())
        await store.load()
        #expect(store.filteredReciters(query: "").map(\.id) == [1, 100])
        #expect(store.filteredReciters(query: "   ").map(\.id) == [1, 100])
    }

    @Test("search matches Arabic names and normalizes alef forms")
    @MainActor
    func arabicSearch() async throws {
        let store = CatalogStore(service: try FixtureCatalogService.loadedFromFixtures())
        await store.load()
        // Exact substring.
        #expect(store.filteredReciters(query: "العجمي").map(\.id) == [1])
        // Alef-with-hamza query matches bare-alef names and vice versa.
        #expect(store.filteredReciters(query: "احمد").map(\.id) == [1])
        #expect(store.filteredReciters(query: "أحمد").map(\.id) == [1])
        // No match.
        #expect(store.filteredReciters(query: "غير موجود").isEmpty)
    }

    @Test("search normalizes teh-marbuta and diacritics")
    func normalization() {
        #expect(CatalogStore.normalizeArabic("مَكْتَبَة") == "مكتبه")
        #expect(CatalogStore.normalizeArabic("أحمد") == CatalogStore.normalizeArabic("احمد"))
        #expect(CatalogStore.normalizeArabic("سورة") == "سوره")
    }

    @Test("surah and riwayah lookups resolve fixture metadata")
    @MainActor
    func lookups() async throws {
        let store = CatalogStore(service: try FixtureCatalogService.loadedFromFixtures())
        await store.load()
        #expect(store.surah(id: 114)?.name == "الناس")
        #expect(store.surah(id: 999) == nil)
        #expect(store.riwayahName(id: 1) == "حفص عن عاصم")
        #expect(store.riwayahName(id: 999) == nil)
        #expect(store.riwayahName(id: nil) == nil)
    }
}
