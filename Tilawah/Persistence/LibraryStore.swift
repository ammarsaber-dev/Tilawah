//
//  LibraryStore.swift
//  Tilawah
//
//  User library actions (Phase 5): favorites, playlists, bookmarks, history.
//  Views read lists via `@Query` (auto-updating); the store owns mutations,
//  snapshot codecs, ordering, and pruning. Deleting library entries never
//  touches downloads or playback state.
//

import Foundation
import SwiftData

@Observable
@MainActor
public final class LibraryStore {
    public static let historyLimit = 100

    private let context: ModelContext
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(container: ModelContainer) {
        context = ModelContext(container)
    }

    /// For tests with a custom context.
    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Snapshots

    public func snapshot(of asset: AudioAsset) -> Data? {
        try? encoder.encode(AssetSnapshot(asset: asset))
    }

    public func asset(from snapshot: Data) -> AudioAsset? {
        (try? decoder.decode(AssetSnapshot.self, from: snapshot))?.makeAsset()
    }

    // MARK: - Favorites

    public func isFavorite(assetID: String) -> Bool {
        favorite(assetID: assetID) != nil
    }

    @discardableResult
    public func toggleFavorite(_ asset: AudioAsset) -> Bool {
        if let existing = favorite(assetID: asset.id) {
            context.delete(existing)
            try? context.save()
            return false
        }
        guard let blob = snapshot(of: asset) else { return false }
        context.insert(FavoriteItem(assetID: asset.id, snapshot: blob))
        try? context.save()
        return true
    }

    public func removeFavorite(assetID: String) {
        if let existing = favorite(assetID: assetID) {
            context.delete(existing)
            try? context.save()
        }
    }

    private func favorite(assetID: String) -> FavoriteItem? {
        let id = assetID
        let descriptor = FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.assetID == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Playlists

    @discardableResult
    public func createPlaylist(name: String) -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let playlist = Playlist(name: trimmed)
        context.insert(playlist)
        try? context.save()
        return playlist
    }

    public func renamePlaylist(_ playlist: Playlist, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlist.name = trimmed
        try? context.save()
    }

    public func deletePlaylist(_ playlist: Playlist) {
        let id = playlist.id
        let descriptor = FetchDescriptor<PlaylistItem>(predicate: #Predicate { $0.playlistID == id })
        for item in (try? context.fetch(descriptor)) ?? [] {
            context.delete(item)
        }
        context.delete(playlist)
        try? context.save()
    }

    public func addToPlaylist(_ asset: AudioAsset, playlist: Playlist) {
        guard let blob = snapshot(of: asset) else { return }
        let items = playlistItems(playlistID: playlist.id)
        let nextIndex = (items.map(\.sortIndex).max() ?? -1) + 1
        context.insert(PlaylistItem(
            playlistID: playlist.id, sortIndex: nextIndex, snapshot: blob
        ))
        try? context.save()
    }

    public func removeFromPlaylist(_ item: PlaylistItem) {
        context.delete(item)
        try? context.save()
    }

    /// Moves items within their playlist and renormalizes `sortIndex`.
    /// (Manual move — `Array.move(fromOffsets:)` lives in SwiftUI and this
    /// store stays UI-framework-free.)
    public func moveInPlaylist(playlistID: UUID, from source: IndexSet, to destination: Int) {
        var items = playlistItems(playlistID: playlistID)
        let sorted = source.sorted().filter { $0 < items.count }
        guard !sorted.isEmpty else { return }
        let moving = sorted.map { items[$0] }
        for index in sorted.reversed() {
            items.remove(at: index)
        }
        var adjusted = max(0, min(destination, items.count + sorted.count))
        for index in sorted where index < destination {
            adjusted -= 1
        }
        adjusted = max(0, min(adjusted, items.count))
        items.insert(contentsOf: moving, at: adjusted)
        for (index, item) in items.enumerated() {
            item.sortIndex = index
        }
        try? context.save()
    }

    public func playlistAssets(playlistID: UUID) -> [AudioAsset] {
        playlistItems(playlistID: playlistID).compactMap { asset(from: $0.snapshot) }
    }

    private func playlistItems(playlistID: UUID) -> [PlaylistItem] {
        let id = playlistID
        var descriptor = FetchDescriptor<PlaylistItem>(predicate: #Predicate { $0.playlistID == id })
        descriptor.sortBy = [SortDescriptor(\.sortIndex)]
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Bookmarks

    @discardableResult
    public func addBookmark(_ asset: AudioAsset, position: Double) -> Bookmark? {
        guard let blob = snapshot(of: asset) else { return nil }
        let bookmark = Bookmark(assetID: asset.id, position: max(0, position), snapshot: blob)
        context.insert(bookmark)
        try? context.save()
        return bookmark
    }

    public func deleteBookmark(_ bookmark: Bookmark) {
        context.delete(bookmark)
        try? context.save()
    }

    // MARK: - History

    /// Records a play (upsert per asset: re-plays bump recency).
    public func recordPlay(_ asset: AudioAsset) {
        guard let blob = snapshot(of: asset) else { return }
        if let existing = historyEntry(assetID: asset.id) {
            existing.snapshot = blob
            existing.playedAt = Date()
            existing.lastPosition = 0
        } else {
            context.insert(HistoryEntry(assetID: asset.id, snapshot: blob))
        }
        pruneHistoryIfNeeded()
        try? context.save()
    }

    public func updateHistoryPosition(assetID: String, position: Double) {
        guard let existing = historyEntry(assetID: assetID) else { return }
        existing.lastPosition = max(0, position)
        try? context.save()
    }

    public func clearHistory() {
        let descriptor = FetchDescriptor<HistoryEntry>()
        for entry in (try? context.fetch(descriptor)) ?? [] {
            context.delete(entry)
        }
        try? context.save()
    }

    private func historyEntry(assetID: String) -> HistoryEntry? {
        let id = assetID
        let descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.assetID == id })
        return try? context.fetch(descriptor).first
    }

    private func pruneHistoryIfNeeded() {
        var descriptor = FetchDescriptor<HistoryEntry>()
        descriptor.sortBy = [SortDescriptor(\.playedAt, order: .reverse)]
        guard let all = try? context.fetch(descriptor), all.count > Self.historyLimit else {
            return
        }
        for stale in all.dropFirst(Self.historyLimit) {
            context.delete(stale)
        }
    }
}
