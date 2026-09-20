//
//  PlaybackTests.swift
//  TilawahTests
//
//  Phase 3 unit tests (AGENTS.md §9): local-vs-remote selection, queue
//  navigation, snapshot round-trips, and the SwiftData state store
//  (in-memory). The AVPlayer engine itself is verified on-simulator.
//

@testable import Tilawah
import Foundation
import SwiftData
import Testing

// MARK: - Local-vs-remote selection

@Suite("PlaybackSource")
struct PlaybackSourceTests {
    private func asset() -> AudioAsset {
        AudioAsset(
            reciterID: 1, mushafID: 1, surahID: 1,
            reciterName: "أ", mushafName: "م", surahName: "الفاتحة",
            streamURL: URL(string: "https://server6.mp3quran.net/akdr/001.mp3")!
        )
    }

    private func sandboxRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("missing local file falls back to stream")
    func missingFallsBackToStream() throws {
        let asset = asset()
        let resolved = PlaybackSource.url(for: asset, localRoot: try sandboxRoot())
        #expect(resolved == asset.streamURL)
    }

    @Test("validated local file wins over stream")
    func localFileWins() throws {
        let asset = asset()
        let root = try sandboxRoot()
        let local = root.appendingPathComponent(asset.relativeStoragePath)
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0xFF, count: PlaybackSource.minimumPlayableBytes + 10).write(to: local)
        #expect(PlaybackSource.url(for: asset, localRoot: root) == local)
    }

    @Test("partial (undersized) files are never playable")
    func partialFileStreams() throws {
        let asset = asset()
        let root = try sandboxRoot()
        let local = root.appendingPathComponent(asset.relativeStoragePath)
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0xFF, count: PlaybackSource.minimumPlayableBytes - 1).write(to: local)
        #expect(PlaybackSource.isPlayableFile(at: local) == false)
        #expect(PlaybackSource.url(for: asset, localRoot: root) == asset.streamURL)
    }

    @Test("directories never qualify as playable")
    func directoryIsNotPlayable() throws {
        let root = try sandboxRoot()
        #expect(PlaybackSource.isPlayableFile(at: root) == false)
    }
}

// MARK: - Queue navigation

@Suite("QueueNavigator")
struct QueueNavigatorTests {
    @Test("repeat-off stops at the tail")
    func repeatOffStops() {
        #expect(QueueNavigator.nextIndex(current: 0, count: 3, repeat: .off) == 1)
        #expect(QueueNavigator.nextIndex(current: 2, count: 3, repeat: .off) == nil)
    }

    @Test("repeat-all wraps")
    func repeatAllWraps() {
        #expect(QueueNavigator.nextIndex(current: 2, count: 3, repeat: .all) == 0)
    }

    @Test("repeat-one stays (controller re-seeks)")
    func repeatOneStays() {
        #expect(QueueNavigator.nextIndex(current: 1, count: 3, repeat: .one) == 1)
    }

    @Test("empty or out-of-range queue yields nil")
    func degenerateQueue() {
        #expect(QueueNavigator.nextIndex(current: 0, count: 0, repeat: .all) == nil)
        #expect(QueueNavigator.nextIndex(current: 9, count: 3, repeat: .all) == nil)
    }

    @Test("previous restarts past the threshold")
    func previousRestartsWhenFarIn() {
        #expect(
            QueueNavigator.previous(current: 1, count: 3, position: 30, repeat: .off)
                == .restart
        )
    }

    @Test("previous steps back when near the start")
    func previousStepsBack() {
        #expect(
            QueueNavigator.previous(current: 1, count: 3, position: 2, repeat: .off)
                == .moveTo(0)
        )
    }

    @Test("previous at head restarts unless repeating the queue")
    func previousAtHead() {
        #expect(
            QueueNavigator.previous(current: 0, count: 3, position: 0, repeat: .off)
                == .restart
        )
        #expect(
            QueueNavigator.previous(current: 0, count: 3, position: 0, repeat: .all)
                == .moveTo(2)
        )
        // Single-item queue under repeat-all: nowhere to move.
        #expect(
            QueueNavigator.previous(current: 0, count: 1, position: 0, repeat: .all)
                == .restart
        )
    }

    @Test("repeat mode cycles off → all → one → off")
    func repeatCycle() {
        #expect(RepeatMode.off.next() == .all)
        #expect(RepeatMode.all.next() == .one)
        #expect(RepeatMode.one.next() == .off)
    }
}

// MARK: - Snapshots and time formatting

@Suite("Playback snapshots")
struct SnapshotTests {
    private func asset() -> AudioAsset {
        AudioAsset(
            reciterID: 1, mushafID: 1, surahID: 114,
            reciterName: "أ", mushafName: "م", surahName: "الناس",
            streamURL: URL(string: "https://server6.mp3quran.net/akdr/114.mp3")!
        )
    }

    @Test("snapshot round-trips through Codable")
    func roundTrip() throws {
        let snapshot = AssetSnapshot(asset: asset())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AssetSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.makeAsset()?.id == asset().id)
    }

    @Test("non-http snapshot URLs are unrestorable")
    func badURLUnrestorable() {
        var snapshot = AssetSnapshot(asset: asset())
        snapshot.streamURL = URL(string: "file:///tmp/evil.mp3")!
        #expect(snapshot.makeAsset() == nil)
    }

    @Test("queue state clamps the index and rejects empty queues")
    func queueClamping() {
        let state = RestorableQueueState(items: [AssetSnapshot(asset: asset())], index: 9, position: 12)
        let queue = try? #require(state.makeQueue())
        #expect(queue?.index == 0)
        #expect(RestorableQueueState(items: [], index: 0, position: 0).makeQueue() == nil)
    }

    @Test("time formatter")
    func timeFormatting() {
        #expect(PlaybackTimeFormatter.string(from: 0) == "0:00")
        #expect(PlaybackTimeFormatter.string(from: -5) == "0:00")
        #expect(PlaybackTimeFormatter.string(from: 61) == "1:01")
        #expect(PlaybackTimeFormatter.string(from: 600) == "10:00")
        #expect(PlaybackTimeFormatter.string(from: 3661) == "1:01:01")
    }
}

// MARK: - SwiftData state store (in-memory)

@Suite("PlaybackStateStore")
struct PlaybackStateStoreTests {
    @MainActor
    private func makeStore() -> PlaybackStateStore {
        PlaybackStateStore(
            context: ModelContext(
                PersistenceFactory.makeContainer(inMemory: true)
            )
        )
    }

    private func state() -> RestorableQueueState {
        let asset = AudioAsset(
            reciterID: 1, mushafID: 1, surahID: 2,
            reciterName: "أ", mushafName: "م", surahName: "البقرة",
            streamURL: URL(string: "https://server6.mp3quran.net/akdr/002.mp3")!
        )
        return RestorableQueueState(items: [AssetSnapshot(asset: asset)], index: 0, position: 42.5)
    }

    @Test("empty store loads nothing")
    @MainActor
    func loadsNothingWhenEmpty() {
        #expect(makeStore().load() == nil)
    }

    @Test("save then load round-trips the snapshot")
    @MainActor
    func saveLoadRoundTrip() {
        let store = makeStore()
        store.save(state())
        let loaded = try? #require(store.load())
        #expect(loaded?.position == 42.5)
        #expect(loaded?.makeQueue()?.assets.first?.surahID == 2)
    }

    @Test("clear removes the snapshot")
    @MainActor
    func clearRemoves() {
        let store = makeStore()
        store.save(state())
        store.clear()
        #expect(store.load() == nil)
    }
}
