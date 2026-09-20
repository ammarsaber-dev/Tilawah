//
//  PlaybackSource.swift
//  Tilawah
//
//  Local-vs-remote selection (AGENTS.md §6 Playback, §7 storage rules):
//  a validated local file always wins over streaming. Validation is
//  deliberately conservative — missing files and partial downloads
//  (non-trivial length heuristic) fall back to the stream and are never
//  treated as playable.
//

import Foundation

public enum PlaybackSource {
    /// Files smaller than this are treated as partial/corrupt, never playable.
    /// Downloads are moved into place atomically only when complete, so any
    /// undersized file is a leftover worth ignoring (stream instead).
    public static let minimumPlayableBytes: Int = 1_024

    /// Root for intentional offline copies:
    /// `Application Support/Audio/<reciterID>/<mushafID>/<surahID>.mp3`
    /// (private, non-purgeable, excluded from backup — set by Downloads).
    /// No directory is created here; existence is only ever probed.
    public static func audioDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audio", isDirectory: true)
    }

    /// Resolves the URL to hand to `AVPlayer` for an asset.
    public static func url(for asset: AudioAsset, localRoot: URL) -> URL {
        let local = localRoot.appendingPathComponent(asset.relativeStoragePath)
        if isPlayableFile(at: local) {
            return local
        }
        return asset.streamURL
    }

    /// True for regular files meeting the minimum-size heuristic.
    /// symlinks/directories never qualify (prevents path-confusion playback).
    public static func isPlayableFile(at url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true, let size = values?.fileSize else {
            return false
        }
        return size >= minimumPlayableBytes
    }
}
