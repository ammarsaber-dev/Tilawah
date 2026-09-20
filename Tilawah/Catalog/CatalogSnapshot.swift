//
//  CatalogSnapshot.swift
//  Tilawah
//
//  Persisted catalog snapshot (Phase 6, AGENTS.md §6 Catalog).
//  The browse catalog is cached aggressively in SwiftData so a cold launch
//  without connectivity still shows the last good catalog (marked stale).
//  Refresh always comes from the network; the snapshot is a fallback, never
//  authoritative — downloads/playback carry their own metadata (§5.3) so a
//  stale catalog can never orphan them.
//

import Foundation
import SwiftData

/// Single-row catalog snapshot. `key` is always `"singleton"`.
/// Payloads are JSON-encoded arrays (tolerant Codable models); corrupt blobs
/// decode to nil and are treated as "no snapshot", never a crash.
@Model
public final class PersistedCatalogSnapshot {
    @Attribute(.unique) public var key: String
    public var recitersData: Data?
    public var suwarData: Data?
    public var riwayatData: Data?
    public var updatedAt: Date

    public init(
        key: String = "singleton",
        recitersData: Data? = nil,
        suwarData: Data? = nil,
        riwayatData: Data? = nil,
        updatedAt: Date = Date()
    ) {
        self.key = key
        self.recitersData = recitersData
        self.suwarData = suwarData
        self.riwayatData = riwayatData
        self.updatedAt = updatedAt
    }
}

/// Decoded snapshot payload. Nil when absent or corrupt.
public struct CatalogSnapshotPayload: Sendable, Equatable {
    public var reciters: [Reciter]
    public var suwar: [Surah]
    public var riwayat: [Riwayah]
    public var updatedAt: Date

    public init(reciters: [Reciter], suwar: [Surah], riwayat: [Riwayah], updatedAt: Date) {
        self.reciters = reciters
        self.suwar = suwar
        self.riwayat = riwayat
        self.updatedAt = updatedAt
    }
}

/// Main-actor gateway to the persisted snapshot. Best-effort: every method
/// tolerates a missing/corrupt store and returns nil instead of throwing.
@MainActor
public final class CatalogSnapshotStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(container: ModelContainer) {
        context = ModelContext(container)
    }

    /// For tests/previews with a custom context.
    public init(context: ModelContext) {
        self.context = context
    }

    public func load() -> CatalogSnapshotPayload? {
        let descriptor = FetchDescriptor<PersistedCatalogSnapshot>(
            predicate: #Predicate { $0.key == "singleton" }
        )
        guard let row = try? context.fetch(descriptor).first,
              let recitersData = row.recitersData,
              let suwarData = row.suwarData,
              let riwayatData = row.riwayatData,
              let reciters = try? decoder.decode([Reciter].self, from: recitersData),
              let suwar = try? decoder.decode([Surah].self, from: suwarData),
              let riwayat = try? decoder.decode([Riwayah].self, from: riwayatData),
              !reciters.isEmpty
        else { return nil }
        return CatalogSnapshotPayload(
            reciters: reciters, suwar: suwar, riwayat: riwayat, updatedAt: row.updatedAt
        )
    }

    public func save(reciters: [Reciter], suwar: [Surah], riwayat: [Riwayah]) {
        guard !reciters.isEmpty else { return }
        let descriptor = FetchDescriptor<PersistedCatalogSnapshot>(
            predicate: #Predicate { $0.key == "singleton" }
        )
        let row: PersistedCatalogSnapshot
        if let existing = try? context.fetch(descriptor).first {
            row = existing
        } else {
            row = PersistedCatalogSnapshot()
            context.insert(row)
        }
        row.recitersData = try? encoder.encode(reciters)
        row.suwarData = try? encoder.encode(suwar)
        row.riwayatData = try? encoder.encode(riwayat)
        row.updatedAt = Date()
        try? context.save()
    }

    public func clear() {
        let descriptor = FetchDescriptor<PersistedCatalogSnapshot>(
            predicate: #Predicate { $0.key == "singleton" }
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            try? context.save()
        }
    }
}
