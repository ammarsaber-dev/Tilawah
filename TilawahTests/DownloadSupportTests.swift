//
//  DownloadSupportTests.swift
//  TilawahTests
//
//  Phase 4 unit tests (AGENTS.md §9): completion validation, queue policy,
//  asset-ID parsing, identity codec, library measurement, and backup
//  exclusion. The live session engine is verified on-simulator.
//

@testable import Tilawah
import Foundation
import Testing

@Suite("DownloadValidator")
struct DownloadValidatorTests {
    private func validate(
        statusCode: Int, mimeType: String?, fileSize: Int, expectedLength: Int64?
    ) -> Result<Void, DownloadValidationError> {
        DownloadValidator.validate(
            statusCode: statusCode, mimeType: mimeType,
            fileSize: fileSize, expectedLength: expectedLength
        )
    }

    private func isSuccess(_ result: Result<Void, DownloadValidationError>) -> Bool {
        if case .success = result { return true }
        return false
    }

    private func failure(_ result: Result<Void, DownloadValidationError>) -> DownloadValidationError? {
        if case let .failure(error) = result { return error }
        return nil
    }

    @Test("accepts a complete audio response")
    func acceptsComplete() {
        #expect(isSuccess(validate(
            statusCode: 200, mimeType: "audio/mpeg",
            fileSize: 1_000_000, expectedLength: 1_000_000
        )))
    }

    @Test("accepts resumed (206) responses")
    func acceptsResumed() {
        #expect(isSuccess(validate(
            statusCode: 206, mimeType: "audio/mpeg",
            fileSize: 500_000, expectedLength: 500_000
        )))
    }

    @Test("rejects non-2xx status")
    func rejectsBadStatus() {
        #expect(
            failure(validate(
                statusCode: 404, mimeType: "audio/mpeg",
                fileSize: 1_000_000, expectedLength: nil
            )) == .httpStatus(404)
        )
        #expect(
            failure(validate(
                statusCode: 500, mimeType: "audio/mpeg",
                fileSize: 1_000_000, expectedLength: nil
            )) == .httpStatus(500)
        )
    }

    @Test("rejects non-audio MIME, case-insensitively")
    func rejectsBadMIME() {
        #expect(
            failure(validate(
                statusCode: 200, mimeType: "text/html",
                fileSize: 1_000_000, expectedLength: nil
            )) == .unexpectedMIME("text/html")
        )
        #expect(
            failure(validate(
                statusCode: 200, mimeType: nil,
                fileSize: 1_000_000, expectedLength: nil
            )) == .unexpectedMIME(nil)
        )
        #expect(isSuccess(validate(
            statusCode: 200, mimeType: "Audio/MPEG",
            fileSize: 1_000_000, expectedLength: nil
        )))
    }

    @Test("rejects short files and truncated lengths")
    func rejectsShortFiles() {
        #expect(
            failure(validate(
                statusCode: 200, mimeType: "audio/mpeg",
                fileSize: PlaybackSource.minimumPlayableBytes - 1, expectedLength: nil
            )) == .fileTooSmall(PlaybackSource.minimumPlayableBytes - 1)
        )
        #expect(
            failure(validate(
                statusCode: 200, mimeType: "audio/mpeg",
                fileSize: 100, expectedLength: 1_000_000
            )) == .fileTooSmall(100)
        )
    }
}

@Suite("PendingDownloadQueue")
struct PendingDownloadQueueTests {
    @Test("starts up to three concurrent downloads")
    func maxThreeConcurrent() {
        var queue = PendingDownloadQueue()
        for id in ["a", "b", "c", "d"] { queue.request(id) }
        #expect(queue.takeNext() == "a")
        #expect(queue.takeNext() == "b")
        #expect(queue.takeNext() == "c")
        #expect(queue.takeNext() == nil)
        #expect(queue.activeCount == 3)
    }

    @Test("finishing frees a slot for the next waiter")
    func freesSlot() {
        var queue = PendingDownloadQueue()
        for id in ["a", "b", "c", "d"] { queue.request(id) }
        _ = queue.takeNext()
        _ = queue.takeNext()
        _ = queue.takeNext()
        queue.markFinished("a")
        #expect(queue.takeNext() == "d")
    }

    @Test("duplicates are ignored")
    func noDuplicates() {
        var queue = PendingDownloadQueue()
        queue.request("a")
        #expect(queue.request("a") == true)
        #expect(queue.contains("a"))
        _ = queue.takeNext()
        #expect(queue.request("a") == true)
        queue.remove("a")
        #expect(!queue.contains("a"))
        #expect(queue.request("a") == false)
    }
}

@Suite("Asset identity")
struct AssetIdentityTests {
    @Test("components parse from stable IDs")
    func parsesComponents() {
        let parts = AssetIDComponents.parse("mp3quran:v3:reciter:1:mushaf:2:surah:114")
        #expect(parts == AssetIDComponents(reciterID: 1, mushafID: 2, surahID: 114))
        #expect(parts?.relativeStoragePath == "1/2/114.mp3")
    }

    @Test("malformed IDs fail to parse")
    func rejectsMalformed() {
        #expect(AssetIDComponents.parse("") == nil)
        #expect(AssetIDComponents.parse("mp3quran:v3:reciter:1:mushaf:1") == nil)
        #expect(AssetIDComponents.parse("other:v3:reciter:1:mushaf:1:surah:2") == nil)
        #expect(AssetIDComponents.parse("mp3quran:v3:reciter:x:mushaf:1:surah:2") == nil)
    }

    @Test("task description round-trips the asset ID")
    func taskDescriptionRoundTrip() {
        let id = "mp3quran:v3:reciter:1:mushaf:1:surah:2"
        #expect(DownloadTaskIdentity.decode(DownloadTaskIdentity.encode(id)) == id)
        #expect(DownloadTaskIdentity.decode(nil) == nil)
        #expect(DownloadTaskIdentity.decode("") == nil)
    }
}

@Suite("DownloadFilesystem")
struct DownloadFilesystemTests {
    @Test("destination nests under the library root")
    func destinationPath() throws {
        let asset = AudioAsset(
            reciterID: 7, mushafID: 3, surahID: 5,
            reciterName: "أ", mushafName: "م",
            streamURL: URL(string: "https://example.net/005.mp3")!
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = DownloadFilesystem.destination(for: asset, localRoot: root)
        #expect(destination.path.hasPrefix(root.path))
        #expect(destination.lastPathComponent == "005.mp3")
    }

    @Test("library size sums real file bytes only")
    func librarySize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("a.mp3"))
        let nested = root.appendingPathComponent("1/1", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 50).write(to: nested.appendingPathComponent("001.mp3"))
        #expect(DownloadFilesystem.librarySize(localRoot: root) == 150)
        #expect(DownloadFilesystem.librarySize(localRoot: root.appendingPathComponent("nope")) == 0)
    }

    @Test("backup exclusion sticks on files")
    func backupExclusion() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp3")
        try Data(repeating: 3, count: 64).write(to: file)
        try DownloadFilesystem.setExcludedFromBackup(file)
        let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
