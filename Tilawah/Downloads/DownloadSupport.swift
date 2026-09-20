//
//  DownloadSupport.swift
//  Tilawah
//
//  Pure download helpers (Phase 4): validation rules, concurrency queue,
//  task-identity codec, and filesystem helpers. No URLSession, no MainActor
//  — fully unit-tested.
//

import Foundation

// MARK: - Validation

public enum DownloadValidationError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case unexpectedMIME(String?)
    case fileTooSmall(Int)
    case missingTempFile
}

public enum DownloadValidator {
    /// Validates a finished download before it may enter the audio library.
    /// - HTTP must be 2xx (200 fresh, 206 resumed).
    /// - MIME must be `audio/*` (servers verified `audio/mpeg`).
    /// - File must meet the shared playability floor, and — when the server
    ///   advertised a length — must contain at least that many bytes.
    /// Anything else is rejected: partials never become playable.
    public static func validate(
        statusCode: Int, mimeType: String?, fileSize: Int,
        expectedLength: Int64?, minimumBytes: Int = PlaybackSource.minimumPlayableBytes
    ) -> Result<Void, DownloadValidationError> {
        guard (200 ... 299).contains(statusCode) else {
            return .failure(.httpStatus(statusCode))
        }
        let mime = (mimeType ?? "").lowercased()
        guard mime.hasPrefix("audio/") else {
            return .failure(.unexpectedMIME(mimeType))
        }
        if let expected = expectedLength, expected > 0, Int64(fileSize) < expected {
            return .failure(.fileTooSmall(fileSize))
        }
        guard fileSize >= minimumBytes else {
            return .failure(.fileTooSmall(fileSize))
        }
        return .success(())
    }

    public static func arabicMessage(for error: DownloadValidationError) -> String {
        switch error {
        case let .httpStatus(code): "خطأ في الشبكة (HTTP \(code))"
        case .unexpectedMIME: "ملف غير صوتي من الخادم"
        case .fileTooSmall: "ملف ناقص من الخادم"
        case .missingTempFile: "تعذّر حفظ الملف"
        }
    }
}

// MARK: - Concurrency queue (pure policy)

/// FIFO queue enforcing max-concurrent downloads + no duplicates.
/// The store mirrors task state here; the policy itself is pure.
public struct PendingDownloadQueue: Sendable {
    public static let maxConcurrent = 3

    /// Asset IDs waiting for a slot, in request order.
    public private(set) var waiting: [String] = []
    /// Asset IDs currently holding a slot.
    public private(set) var active: Set<String> = []

    public init() {}

    public var activeCount: Int { active.count }

    /// Request a slot. Returns true when already tracked (duplicate ignored).
    @discardableResult
    public mutating func request(_ id: String) -> Bool {
        if waiting.contains(id) || active.contains(id) { return true }
        waiting.append(id)
        return false
    }

    /// Take the next waiting ID when a slot is free, marking it active.
    public mutating func takeNext() -> String? {
        guard active.count < Self.maxConcurrent, !waiting.isEmpty else { return nil }
        let id = waiting.removeFirst()
        active.insert(id)
        return id
    }

    public mutating func markFinished(_ id: String) {
        waiting.removeAll { $0 == id }
        active.remove(id)
    }

    /// Marks an ID active without going through `waiting`
    /// (reattaching live tasks after relaunch).
    public mutating func markActive(_ id: String) {
        waiting.removeAll { $0 == id }
        active.insert(id)
    }

    public mutating func remove(_ id: String) {
        waiting.removeAll { $0 == id }
        active.remove(id)
    }

    public func contains(_ id: String) -> Bool {
        waiting.contains(id) || active.contains(id)
    }
}

// MARK: - Task identity

public enum DownloadTaskIdentity {
    /// Stable asset ID round-trips through `taskDescription`, surviving
    /// app relaunch for background sessions (taskIdentifiers do not).
    public static func encode(_ assetID: String) -> String { assetID }
    public static func decode(_ taskDescription: String?) -> String? {
        guard let taskDescription, !taskDescription.isEmpty else { return nil }
        return taskDescription
    }
}

// MARK: - Asset ID components

public struct AssetIDComponents: Equatable, Sendable {
    public var reciterID: Int
    public var mushafID: Int
    public var surahID: Int

    /// Parses `mp3quran:v3:reciter:{r}:mushaf:{m}:surah:{s}`.
    /// Lets relaunch reconciliation derive storage paths without records.
    public static func parse(_ assetID: String) -> AssetIDComponents? {
        // [mp3quran, v3, reciter, r, mushaf, m, surah, s]
        let parts = assetID.split(separator: ":")
        guard parts.count == 8, parts[0] == "mp3quran",
              parts[2] == "reciter", parts[4] == "mushaf", parts[6] == "surah",
              let r = Int(parts[3]), let m = Int(parts[5]), let s = Int(parts[7])
        else { return nil }
        return AssetIDComponents(reciterID: r, mushafID: m, surahID: s)
    }

    public var relativeStoragePath: String {
        AudioAsset.makeRelativeStoragePath(reciterID: reciterID, mushafID: mushafID, surahID: surahID)
    }
}

// MARK: - Filesystem

public enum DownloadFilesystem {
    /// Final destination for a validated asset inside `localRoot`
    /// (`Application Support/Audio` in production).
    public static func destination(for asset: AudioAsset, localRoot: URL) -> URL {
        localRoot.appendingPathComponent(asset.relativeStoragePath)
    }

    /// Creates the parent chain and marks the library root excluded from
    /// backup. Each moved file is additionally marked at move time
    /// (exclusion is set per-item, never assumed inherited).
    public static func prepareLibrary(localRoot: URL) throws {
        try FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
        try setExcludedFromBackup(localRoot)
    }

    public static func setExcludedFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }

    /// Measured on-disk size of the audio library (real bytes, not estimates).
    public static func librarySize(localRoot: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: localRoot, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
