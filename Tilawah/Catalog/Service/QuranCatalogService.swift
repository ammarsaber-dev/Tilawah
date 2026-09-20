//
//  QuranCatalogService.swift
//  Tilawah
//
//  Catalog service boundary (Phase 1). Views and stores depend on this
//  protocol — never on the concrete MP3Quran adapter — so the provider
//  stays replaceable (AGENTS.md §5–§6).
//

import Foundation

/// Errors surfaced by catalog fetching and asset construction.
public enum CatalogError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case httpStatus(Int)
    case decodingFailed(String)
    case transport(String)
    case offline
    case missingServer(reciterID: Int, mushafID: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url): "رابط غير صالح: \(url)"
        case let .httpStatus(code): "خطأ في الشبكة (HTTP \(code))"
        case let .decodingFailed(detail): "تعذّر تحليل البيانات: \(detail)"
        case let .transport(detail): "تعذّر الاتصال: \(detail)"
        case .offline: "لا يوجد اتصال بالإنترنت. تحقق من الشبكة وحاول مجددًا."
        case let .missingServer(reciterID, mushafID):
            "لا يتوفر خادم للتسجيل (reciter \(reciterID), mushaf \(mushafID))"
        }
    }

    /// True when the failure is a connectivity loss (eligible for the offline UI).
    public var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }
}

/// Provider-agnostic catalog boundary. All networking lives behind this;
/// callers work with `Reciter` / `Mushaf` / `Surah` / `Riwayah` value types.
public protocol QuranCatalogService: Sendable {
    /// All reciters with their mushafs, e.g. `GET /reciters?language=ar`.
    func fetchReciters(language: String) async throws -> [Reciter]
    /// A single reciter with mushafs, e.g. `GET /reciters?language=ar&reciter=1`.
    func fetchReciter(id: Int, language: String) async throws -> Reciter
    /// The 114-surah metadata list, e.g. `GET /suwar?language=ar`.
    func fetchSuwar(language: String) async throws -> [Surah]
    /// Riwayat list, e.g. `GET /riwayat?language=ar`.
    func fetchRiwayat(language: String) async throws -> [Riwayah]

    /// Surah IDs actually available for a mushaf (parsed `surah_list`).
    func availableSurahIDs(for mushaf: Mushaf) -> [Int]
    /// Derived stream URL for a surah recording, or nil when unbuildable.
    func streamURL(forSurahID surahID: Int, in mushaf: Mushaf) -> URL?
    /// Full stable asset for a surah recording, or nil when unbuildable.
    func audioAsset(
        reciter: Reciter, mushaf: Mushaf, surahID: Int, surahName: String?
    ) -> AudioAsset?
}

public extension QuranCatalogService {
    func availableSurahIDs(for mushaf: Mushaf) -> [Int] {
        mushaf.availableSurahIDs
    }

    func streamURL(forSurahID surahID: Int, in mushaf: Mushaf) -> URL? {
        MP3QuranURLBuilder.streamURL(server: mushaf.server, surahID: surahID)
    }

    func audioAsset(
        reciter: Reciter, mushaf: Mushaf, surahID: Int, surahName: String?
    ) -> AudioAsset? {
        guard let url = streamURL(forSurahID: surahID, in: mushaf) else { return nil }
        return AudioAsset(
            reciterID: reciter.id, mushafID: mushaf.id, surahID: surahID,
            reciterName: reciter.name, mushafName: mushaf.name,
            surahName: surahName, streamURL: url
        )
    }
}
