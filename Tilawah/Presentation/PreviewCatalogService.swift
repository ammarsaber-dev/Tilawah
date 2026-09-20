//
//  PreviewCatalogService.swift
//  Tilawah
//
//  Static in-memory catalog for SwiftUI previews. Ships no production
//  behavior; the live app always uses `MP3QuranService`.
//

import Foundation

/// Deterministic sample data for previews (mirrors the unit-test fixtures).
struct PreviewCatalogService: QuranCatalogService {
    static let sampleReciters: [Reciter] = [
        Reciter(
            id: 1,
            name: "أحمد بن علي العجمي",
            letter: "ا",
            moshaf: [
                Mushaf(
                    id: 1,
                    name: "المصحف المرتل",
                    rewayaID: 1,
                    server: "https://server6.mp3quran.net/akdr/",
                    surahTotal: 114,
                    moshafType: 11,
                    surahListRaw: "1,2,3,114"
                ),
                Mushaf(
                    id: 2,
                    name: "المصحف المجود",
                    server: "https://server6.mp3quran.net/akdr2/",
                    surahListRaw: "1,114"
                ),
            ]
        ),
        Reciter(
            id: 100,
            name: "قارئ جزئي",
            moshaf: [
                Mushaf(
                    id: 7,
                    name: "تسجيلات مختارة",
                    rewayaID: 1,
                    server: "https://server.example.net/partial/",
                    surahTotal: 113,
                    surahListRaw: "1,3,5,114"
                ),
            ]
        ),
    ]

    static let sampleSuwar: [Surah] = [
        Surah(id: 1, name: "الفاتحة", startPage: 1, endPage: 1, makkia: 1, type: 0),
        Surah(id: 2, name: "البقرة", startPage: 2, endPage: 49, makkia: 0, type: 0),
        Surah(id: 3, name: "آل عمران", makkia: 0),
        Surah(id: 5, name: "المائدة", makkia: 0),
        Surah(id: 114, name: "الناس", makkia: 1),
    ]

    static let sampleRiwayat: [Riwayah] = [
        Riwayah(id: 1, name: "حفص عن عاصم"),
    ]

    func fetchReciters(language: String) async throws -> [Reciter] { Self.sampleReciters }
    func fetchReciter(id: Int, language: String) async throws -> Reciter {
        guard let reciter = Self.sampleReciters.first(where: { $0.id == id }) else {
            throw CatalogError.decodingFailed("Reciter \(id) not found in preview data.")
        }
        return reciter
    }

    func fetchSuwar(language: String) async throws -> [Surah] { Self.sampleSuwar }
    func fetchRiwayat(language: String) async throws -> [Riwayah] { Self.sampleRiwayat }
}

/// Always-failing service for error/offline-state previews.
struct PreviewFailingCatalogService: QuranCatalogService {
    func fetchReciters(language: String) async throws -> [Reciter] { throw CatalogError.offline }
    func fetchReciter(id: Int, language: String) async throws -> Reciter { throw CatalogError.offline }
    func fetchSuwar(language: String) async throws -> [Surah] { throw CatalogError.offline }
    func fetchRiwayat(language: String) async throws -> [Riwayah] { throw CatalogError.offline }
}

@MainActor
enum PreviewPlayback {
    /// Player with an empty in-memory state store (nothing restored).
    static func makeController() -> PlaybackController {
        PlaybackController(
            stateStore: PlaybackStateStore(
                container: PersistenceFactory.makeContainer(inMemory: true)
            )
        )
    }
}
