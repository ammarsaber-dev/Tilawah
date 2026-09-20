//
//  DownloadRecord.swift
//  Tilawah
//
//  SwiftData download records (schema: alongside v1 playback state —
//  additive change, no shipped users to migrate). A record is metadata only;
//  the file on disk is authoritative: launch reconciliation drops records
//  whose files vanished and resets interrupted ones to retryable.
//

import Foundation
import SwiftData

/// Persisted download state per asset. Deleting a download removes the file
/// + record but never touches favorites/playlists (those live elsewhere).
@Model
public final class PersistedDownload {
    @Attribute(.unique) public var assetID: String
    public var reciterID: Int
    public var mushafID: Int
    public var surahID: Int
    public var reciterName: String
    public var mushafName: String
    public var surahName: String?
    public var streamURL: String
    public var relativePath: String
    /// True only after a validated file was moved into place.
    public var isComplete: Bool
    public var totalBytes: Int64
    public var updatedAt: Date

    public init(
        assetID: String, reciterID: Int, mushafID: Int, surahID: Int,
        reciterName: String, mushafName: String, surahName: String? = nil,
        streamURL: String, relativePath: String, isComplete: Bool = false,
        totalBytes: Int64 = 0, updatedAt: Date = Date()
    ) {
        self.assetID = assetID
        self.reciterID = reciterID
        self.mushafID = mushafID
        self.surahID = surahID
        self.reciterName = reciterName
        self.mushafName = mushafName
        self.surahName = surahName
        self.streamURL = streamURL
        self.relativePath = relativePath
        self.isComplete = isComplete
        self.totalBytes = totalBytes
        self.updatedAt = updatedAt
    }

    public convenience init(asset: AudioAsset, isComplete: Bool = false) {
        self.init(
            assetID: asset.id, reciterID: asset.reciterID, mushafID: asset.mushafID,
            surahID: asset.surahID, reciterName: asset.reciterName,
            mushafName: asset.mushafName, surahName: asset.surahName,
            streamURL: asset.streamURL.absoluteString,
            relativePath: asset.relativeStoragePath, isComplete: isComplete
        )
    }
}
