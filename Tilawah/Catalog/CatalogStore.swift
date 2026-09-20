//
//  CatalogStore.swift
//  Tilawah
//
//  Shared catalog state (Phase 2). Views observe this store directly via
//  `@Environment`; no ViewModel-per-screen (AGENTS.md §6). All state lives
//  on `@MainActor`; networking stays inside the injected service.
//

import Foundation
import Observation

/// Loading lifecycle for the catalog snapshot.
public enum CatalogLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(CatalogError)
}

/// In-memory catalog snapshot with aggressive caching: once loaded, `load()`
/// is a no-op until `reload()` is called. (A persisted SwiftData snapshot
/// replaces this in a later phase per AGENTS.md §6.)
@Observable
@MainActor
public final class CatalogStore {
    private let service: any QuranCatalogService

    public private(set) var phase: CatalogLoadPhase = .idle
    public private(set) var reciters: [Reciter] = []
    public private(set) var suwar: [Surah] = []
    public private(set) var riwayat: [Riwayah] = []

    private var inFlight: Task<Void, Never>?

    public init(service: any QuranCatalogService) {
        self.service = service
    }

    public var isLoaded: Bool {
        if case .loaded = phase { return true }
        return false
    }

    public var failure: CatalogError? {
        if case let .failed(error) = phase { return error }
        return nil
    }

    /// Loads reciters + suwar + riwayat unless already loaded/loading.
    public func load() async {
        if let inFlight {
            await inFlight.value
            return
        }
        guard phase != .loaded else { return }
        let task = Task { await performLoad() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Forces a refetch even when cached (pull-to-refresh / retry).
    public func reload() async {
        if let inFlight {
            await inFlight.value
        }
        let task = Task { await performLoad() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performLoad() async {
        phase = .loading
        do {
            async let fetchedReciters = service.fetchReciters(language: "ar")
            async let fetchedSuwar = service.fetchSuwar(language: "ar")
            async let fetchedRiwayat = service.fetchRiwayat(language: "ar")
            let (reciters, suwar, riwayat) = try await (fetchedReciters, fetchedSuwar, fetchedRiwayat)
            self.reciters = reciters
            self.suwar = suwar
            self.riwayat = riwayat
            self.suwarByID = Dictionary(uniqueKeysWithValues: suwar.map { ($0.id, $0) })
            phase = .loaded
        } catch let error as CatalogError {
            phase = .failed(error)
        } catch {
            phase = .failed(.transport(error.localizedDescription))
        }
    }

    // MARK: - Lookups

    private var suwarByID: [Int: Surah] = [:]

    /// Metadata for a surah ID, if the provider's `suwar` list covers it.
    public func surah(id: Int) -> Surah? {
        suwarByID[id]
    }

    /// Display name for a riwayah ID, if known.
    public func riwayahName(id: Int?) -> String? {
        guard let id else { return nil }
        return riwayat.first(where: { $0.id == id })?.name
    }

    /// Full playable queue for a mushaf: one asset per available surah,
    /// in surah order, with display names resolved from `suwar`.
    public func queueAssets(reciter: Reciter, mushaf: Mushaf) -> [AudioAsset] {
        mushaf.availableSurahIDs.compactMap { surahID in
            audioAsset(reciter: reciter, mushaf: mushaf, surahID: surahID)
        }
    }

    private func audioAsset(reciter: Reciter, mushaf: Mushaf, surahID: Int) -> AudioAsset? {
        guard let url = MP3QuranURLBuilder.streamURL(server: mushaf.server, surahID: surahID) else {
            return nil
        }
        return AudioAsset(
            reciterID: reciter.id, mushafID: mushaf.id, surahID: surahID,
            reciterName: reciter.name, mushafName: mushaf.name,
            surahName: surah(id: surahID)?.name, streamURL: url
        )
    }

    // MARK: - Search

    /// Reciters matching `query` against normalized Arabic names.
    /// Empty query returns all reciters in provider order.
    public func filteredReciters(query: String) -> [Reciter] {
        let normalized = Self.normalizeArabic(query)
        guard !normalized.isEmpty else { return reciters }
        return reciters.filter { Self.normalizeArabic($0.name).contains(normalized) }
    }

    /// Normalizes Arabic for search: strips diacritics (harakat — which
    /// `folding(.diacriticInsensitive)` leaves intact) and tatweel, unifies
    /// alef forms (أإآٱ→ا), teh-marbuta (ة→ه), alef-maksura (ى→ي).
    static func normalizeArabic(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive], locale: .init(identifier: "ar"))
        var result = String(folded.unicodeScalars.filter { scalar in
            !(0x064B ... 0x065F).contains(scalar.value) && scalar.value != 0x0670
        })
        result = result.replacingOccurrences(of: "ـ", with: "")
        let alefs = ["أ", "إ", "آ", "ٱ"]
        for alef in alefs {
            result = result.replacingOccurrences(of: alef, with: "ا")
        }
        result = result.replacingOccurrences(of: "ة", with: "ه")
        result = result.replacingOccurrences(of: "ى", with: "ي")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
