//
//  PlaybackPersistence.swift
//  Tilawah
//
//  SwiftData playback state (Phase 3; schema v1 per AGENTS.md P3/Persistence).
//  A single-row snapshot — queue items carry their own metadata so a cold
//  launch restores the session without network and without auto-playing.
//

import Foundation
import SwiftData

/// Self-contained snapshot of one queue item. Rebuilds an `AudioAsset`
/// without touching the network (mirrors the download-metadata rule §5.3).
public struct AssetSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var reciterID: Int
    public var mushafID: Int
    public var surahID: Int
    public var reciterName: String
    public var mushafName: String
    public var surahName: String?
    public var streamURL: URL
    public var relativeStoragePath: String

    public init(asset: AudioAsset) {
        id = asset.id
        reciterID = asset.reciterID
        mushafID = asset.mushafID
        surahID = asset.surahID
        reciterName = asset.reciterName
        mushafName = asset.mushafName
        surahName = asset.surahName
        streamURL = asset.streamURL
        relativeStoragePath = asset.relativeStoragePath
    }

    /// Rebuilds the asset; nil when the persisted URL is unusable.
    public func makeAsset() -> AudioAsset? {
        guard let scheme = streamURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        let asset = AudioAsset(
            reciterID: reciterID, mushafID: mushafID, surahID: surahID,
            reciterName: reciterName, mushafName: mushafName,
            surahName: surahName, streamURL: streamURL
        )
        // `AudioAsset.init` derives id/path deterministically; keep the
        // persisted values only if they agree (guards stale schema drift).
        guard asset.id == id, asset.relativeStoragePath == relativeStoragePath else {
            return nil
        }
        return asset
    }
}

/// Restorable queue position (Codable so the store stays transport-agnostic).
public struct RestorableQueueState: Codable, Equatable, Sendable {
    public var items: [AssetSnapshot]
    public var index: Int
    public var position: Double

    public init(items: [AssetSnapshot], index: Int, position: Double) {
        self.items = items
        self.index = index
        self.position = max(0, position)
    }

    /// Valid queue with a clamped index, or nil when unrestorable.
    public func makeQueue() -> (assets: [AudioAsset], index: Int)? {
        let assets = items.compactMap { $0.makeAsset() }
        guard !assets.isEmpty else { return nil }
        return (assets, min(max(0, index), assets.count - 1))
    }
}

/// Single-row persisted playback state. `key` is always `"singleton"`.
@Model
public final class PersistedPlaybackState {
    @Attribute(.unique) public var key: String
    public var queueData: Data?
    public var index: Int
    public var position: Double
    public var updatedAt: Date

    public init(
        key: String = "singleton", queueData: Data? = nil,
        index: Int = 0, position: Double = 0, updatedAt: Date = Date()
    ) {
        self.key = key
        self.queueData = queueData
        self.index = index
        self.position = position
        self.updatedAt = updatedAt
    }
}

/// Main-actor gateway to the persisted snapshot. One instance per app,
/// owned by the composition root and handed to `PlaybackController`.
@MainActor
public final class PlaybackStateStore {
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

    public func load() -> RestorableQueueState? {
        let descriptor = FetchDescriptor<PersistedPlaybackState>(
            predicate: #Predicate { $0.key == "singleton" }
        )
        guard let row = try? context.fetch(descriptor).first,
              let data = row.queueData,
              let state = try? decoder.decode(RestorableQueueState.self, from: data),
              state.makeQueue() != nil
        else { return nil }
        return state
    }

    public func save(_ state: RestorableQueueState) {
        let descriptor = FetchDescriptor<PersistedPlaybackState>(
            predicate: #Predicate { $0.key == "singleton" }
        )
        let row: PersistedPlaybackState
        if let existing = try? context.fetch(descriptor).first {
            row = existing
        } else {
            row = PersistedPlaybackState()
            context.insert(row)
        }
        row.queueData = try? encoder.encode(state)
        row.index = state.index
        row.position = state.position
        row.updatedAt = Date()
        try? context.save()
    }

    public func clear() {
        let descriptor = FetchDescriptor<PersistedPlaybackState>(
            predicate: #Predicate { $0.key == "singleton" }
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            try? context.save()
        }
    }
}

/// Builds the app's ModelContainer (schema v1). Falls back to in-memory so
/// a corrupt store file can never brick launch; the fallback is honest —
/// persistence is best-effort, playback never depends on it.
public enum PersistenceFactory {
    public static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([PersistedPlaybackState.self, PersistedDownload.self])
        if inMemory {
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("In-memory ModelContainer failed to initialize: \(error)")
            }
        }
        do {
            return try ModelContainer(for: schema)
        } catch {
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("ModelContainer failed to initialize: \(error)")
            }
        }
    }
}
