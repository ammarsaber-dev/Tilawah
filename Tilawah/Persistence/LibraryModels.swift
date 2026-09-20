//
//  LibraryModels.swift
//  Tilawah
//
//  User library models (Phase 5): favorites, playlists, bookmarks, history.
//  Items embed an `AssetSnapshot` blob (self-contained, offline-capable,
//  network-free rebuild) instead of relationships — flat, robust, and the
//  same pattern as download records and playback snapshots.
//

import Foundation
import SwiftData

/// Shared snapshot codec for library items.
enum LibrarySnapshotCodec {
    static func encode(_ asset: AudioAsset) -> Data? {
        try? JSONEncoder().encode(AssetSnapshot(asset: asset))
    }

    static func decode(_ data: Data) -> AssetSnapshot? {
        try? JSONDecoder().decode(AssetSnapshot.self, from: data)
    }
}

/// A favorited surah recording (one row per asset).
@Model
public final class FavoriteItem {
    @Attribute(.unique) public var assetID: String
    public var snapshot: Data
    public var createdAt: Date

    public init(assetID: String, snapshot: Data, createdAt: Date = Date()) {
        self.assetID = assetID
        self.snapshot = snapshot
        self.createdAt = createdAt
    }
}

/// A user playlist (items live in `PlaylistItem`, ordered by `sortIndex`).
@Model
public final class Playlist {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// One playlist entry. Deleted with its playlist (manual cascade in store).
@Model
public final class PlaylistItem {
    @Attribute(.unique) public var id: UUID
    public var playlistID: UUID
    public var sortIndex: Int
    public var snapshot: Data
    public var createdAt: Date

    public init(
        id: UUID = UUID(), playlistID: UUID, sortIndex: Int,
        snapshot: Data, createdAt: Date = Date()
    ) {
        self.id = id
        self.playlistID = playlistID
        self.sortIndex = sortIndex
        self.snapshot = snapshot
        self.createdAt = createdAt
    }
}

/// A user-saved position inside a recording. Tapping resumes playback
/// of the single-item queue at the saved position.
@Model
public final class Bookmark {
    @Attribute(.unique) public var id: UUID
    public var assetID: String
    public var position: Double
    public var snapshot: Data
    public var createdAt: Date

    public init(
        id: UUID = UUID(), assetID: String, position: Double,
        snapshot: Data, createdAt: Date = Date()
    ) {
        self.id = id
        self.assetID = assetID
        self.position = position
        self.snapshot = snapshot
        self.createdAt = createdAt
    }
}

/// Recent plays, one row per asset (re-plays bump `playedAt`).
@Model
public final class HistoryEntry {
    @Attribute(.unique) public var assetID: String
    public var snapshot: Data
    public var playedAt: Date
    public var lastPosition: Double

    public init(
        assetID: String, snapshot: Data,
        playedAt: Date = Date(), lastPosition: Double = 0
    ) {
        self.assetID = assetID
        self.snapshot = snapshot
        self.playedAt = playedAt
        self.lastPosition = lastPosition
    }
}
