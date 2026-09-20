//
//  CatalogStore.swift
//  Tilawah
//
//  Shared catalog state (Phase 2; snapshot persistence added in Phase 6).
//  Views observe this store directly via `@Environment`; no
//  ViewModel-per-screen (AGENTS.md §6). All state lives on `@MainActor`;
//  networking stays inside the injected service.
//
//  Offline rule: the last good network response is persisted to SwiftData.
//  A cold launch with no connectivity shows the snapshot marked stale
//  (`isStale == true`) instead of an error wall; the next successful
//  `reload()` replaces it. The snapshot never orphans downloads — records
//  carry their own metadata (AGENTS.md §5.3).
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

@Observable
@MainActor
public final class CatalogStore {
    private let service: any QuranCatalogService
    private let snapshotStore: CatalogSnapshotStore?

    public private(set) var phase: CatalogLoadPhase = .idle
    public private(set) var reciters: [Reciter] = []
    public private(set) var suwar: [Surah] = []
    public private(set) var riwayat: [Riwayah] = []
    /// True when the visible data came from the persisted snapshot and has
    /// not been revalidated against the network yet this launch.
    public private(set) var isStale = false
    /// Last refresh failure when stale data is shown (nil on fresh loads).
    public private(set) var refreshError: CatalogError?
    public private(set) var lastUpdated: Date?

    private var inFlight: Task<Void, Never>?

    public init(service: any QuranCatalogService, snapshotStore: CatalogSnapshotStore? = nil) {
        self.service = service
        self.snapshotStore = snapshotStore
        if let snapshot = snapshotStore?.load() {
            reciters = snapshot.reciters
            suwar = snapshot.suwar
            riwayat = snapshot.riwayat
            suwarByID = Dictionary(uniqueKeysWithValues: snapshot.suwar.map { ($0.id, $0) })
            lastUpdated = snapshot.updatedAt
            isStale = true
            phase = .loaded
        }
    }

    public var isLoaded: Bool {
        if case .loaded = phase { return true }
        return false
    }

    public var failure: CatalogError? {
        if case let .failed(error) = phase { return error }
        return nil
    }

    /// Loads reciters + suwar + riwayat unless fresh data is already shown.
    /// Stale snapshot data still triggers a network refresh.
    public func load() async {
        if let inFlight {
            await inFlight.value
            return
        }
        guard phase != .loaded || isStale else { return }
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
        let hadData = !reciters.isEmpty
        if !hadData {
            phase = .loading
        }
        do {
            async let fetchedReciters = service.fetchReciters(language: "ar")
            async let fetchedSuwar = service.fetchSuwar(language: "ar")
            async let fetchedRiwayat = service.fetchRiwayat(language: "ar")
            let (reciters, suwar, riwayat) = try await (fetchedReciters, fetchedSuwar, fetchedRiwayat)
            self.reciters = reciters
            self.suwar = suwar
            self.riwayat = riwayat
            self.suwarByID = Dictionary(uniqueKeysWithValues: suwar.map { ($0.id, $0) })
            self.lastUpdated = Date()
            self.isStale = false
            self.refreshError = nil
            phase = .loaded
            snapshotStore?.save(reciters: reciters, suwar: suwar, riwayat: riwayat)
        } catch let error as CatalogError {
            if hadData {
                // Keep showing the snapshot; surface the error as a banner,
                // not an error wall.
                isStale = true
                refreshError = error
                phase = .loaded
            } else {
                phase = .failed(error)
            }
        } catch {
            if hadData {
                isStale = true
                refreshError = .transport(error.localizedDescription)
                phase = .loaded
            } else {
                phase = .failed(.transport(error.localizedDescription))
            }
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
    /// Matching is token-based and typo-tolerant: every query token must
    /// match (substring or one-edit fuzzy) at least one name token, in any
    /// order — so "احمد العجمي" and "العجمي احمد" both match, and a
    /// single-letter typo still finds the reciter.
    public func filteredReciters(query: String) -> [Reciter] {
        let queryTokens = Self.tokenizeArabic(query)
        guard !queryTokens.isEmpty else { return reciters }
        return reciters.filter { reciter in
            let nameTokens = Self.tokenizeArabic(reciter.name)
            guard !nameTokens.isEmpty else { return false }
            return queryTokens.allSatisfy { queryToken in
                nameTokens.contains { Self.tokenMatches(queryToken, in: $0) }
            }
        }
    }

    private static func tokenMatches(_ query: String, in name: String) -> Bool {
        if name.contains(query) { return true }
        // Single-edit tolerance for short tokens, two edits for long ones.
        // Thresholds stay tight to avoid false positives across the catalog.
        let threshold = query.count <= 4 ? 1 : 2
        return levenshtein(query, name) <= threshold
    }

    private static func tokenizeArabic(_ text: String) -> [String] {
        normalizeArabic(text).split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    /// Edit distance over characters (Levenshtein). Pure and testable.
    static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0 ... b.count)
        for i in 1 ... a.count {
            var previous = row[0]
            row[0] = i
            for j in 1 ... b.count {
                let current = row[j]
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + cost)
                previous = current
            }
        }
        return row[b.count]
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
