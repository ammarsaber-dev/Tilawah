//
//  LibraryStoreTests.swift
//  TilawahTests
//
//  Phase 5 unit tests: favorites, playlists (CRUD, ordering, cascade),
//  bookmarks, history (upsert, positions, cap/prune), and corrupt-snapshot
//  tolerance. In-memory SwiftData, no network.
//

@testable import Tilawah
import Foundation
import SwiftData
import Testing

@Suite("LibraryStore", .serialized)
struct LibraryStoreTests {
    /// Store + sibling verification context over one in-memory container.
    @MainActor
    private func makeWorld() -> (LibraryStore, ModelContext) {
        let container = PersistenceFactory.makeContainer(inMemory: true)
        return (
            LibraryStore(context: ModelContext(container)),
            ModelContext(container)
        )
    }

    private func asset(surahID: Int = 1, name: String = "الفاتحة") -> AudioAsset {
        AudioAsset(
            reciterID: 1, mushafID: 1, surahID: surahID,
            reciterName: "أ", mushafName: "م", surahName: name,
            streamURL: URL(string: "https://example.net/\(String(format: "%03d", surahID)).mp3")!
        )
    }

    // MARK: - Favorites

    @Test("favorite toggle adds then removes")
    @MainActor
    func favoriteToggle() throws {
        let (store, context) = makeWorld()
        let item = asset()
        #expect(!store.isFavorite(assetID: item.id))
        #expect(store.toggleFavorite(item) == true)
        #expect(store.isFavorite(assetID: item.id))
        #expect(try context.fetch(FetchDescriptor<FavoriteItem>()).count == 1)
        #expect(store.toggleFavorite(item) == false)
        #expect(!store.isFavorite(assetID: item.id))
        #expect(try context.fetch(FetchDescriptor<FavoriteItem>()).isEmpty)
    }

    @Test("favorite round-trips the snapshot")
    @MainActor
    func favoriteSnapshot() throws {
        let (store, context) = makeWorld()
        store.toggleFavorite(asset())
        let items = try context.fetch(FetchDescriptor<FavoriteItem>())
        #expect(items.count == 1)
        #expect(store.asset(from: items[0].snapshot)?.id == asset().id)
    }

    // MARK: - Playlists

    @Test("playlist create rejects blank names")
    @MainActor
    func playlistCreateValidation() {
        let (store, _) = makeWorld()
        #expect(store.createPlaylist(name: "   ") == nil)
        #expect(store.createPlaylist(name: "تلاوات الصباح") != nil)
    }

    @Test("add keeps insertion order; move reorders")
    @MainActor
    func playlistOrdering() throws {
        let (store, _) = makeWorld()
        let playlist = try #require(store.createPlaylist(name: "قائمتي"))
        store.addToPlaylist(asset(surahID: 1), playlist: playlist)
        store.addToPlaylist(asset(surahID: 2), playlist: playlist)
        store.addToPlaylist(asset(surahID: 3), playlist: playlist)
        #expect(store.playlistAssets(playlistID: playlist.id).map(\.surahID) == [1, 2, 3])
        store.moveInPlaylist(playlistID: playlist.id, from: IndexSet(integer: 0), to: 3)
        #expect(store.playlistAssets(playlistID: playlist.id).map(\.surahID) == [2, 3, 1])
    }

    @Test("rename rejects blank names; delete cascades items")
    @MainActor
    func playlistRenameDelete() throws {
        let (store, context) = makeWorld()
        let playlist = try #require(store.createPlaylist(name: "قديمة"))
        store.addToPlaylist(asset(), playlist: playlist)
        store.renamePlaylist(playlist, name: "   ")
        #expect(playlist.name == "قديمة")
        store.renamePlaylist(playlist, name: "جديدة")
        #expect(playlist.name == "جديدة")
        store.deletePlaylist(playlist)
        #expect(store.playlistAssets(playlistID: playlist.id).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlaylistItem>()).isEmpty)
    }

    // MARK: - Bookmarks

    @Test("bookmarks keep position and asset")
    @MainActor
    func bookmarks() throws {
        let (store, context) = makeWorld()
        let bookmark = try #require(store.addBookmark(asset(surahID: 114, name: "الناس"), position: 12.5))
        #expect(bookmark.position == 12.5)
        #expect(store.asset(from: bookmark.snapshot)?.surahID == 114)
        store.deleteBookmark(bookmark)
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
    }

    // MARK: - History

    @Test("re-plays upsert instead of duplicating")
    @MainActor
    func historyUpsert() throws {
        let (store, context) = makeWorld()
        store.recordPlay(asset())
        store.recordPlay(asset())
        let entries = try context.fetch(FetchDescriptor<HistoryEntry>())
        #expect(entries.count == 1)
        store.updateHistoryPosition(assetID: asset().id, position: 30)
        #expect(try context.fetch(FetchDescriptor<HistoryEntry>()).first?.lastPosition == 30)
        store.clearHistory()
        #expect(try context.fetch(FetchDescriptor<HistoryEntry>()).isEmpty)
    }

    @Test("history prunes beyond the limit")
    @MainActor
    func historyPrunes() throws {
        let (store, context) = makeWorld()
        for i in 1 ... (LibraryStore.historyLimit + 10) {
            store.recordPlay(asset(surahID: (i % 114) + 1))
        }
        let count = try context.fetch(FetchDescriptor<HistoryEntry>()).count
        #expect(count <= LibraryStore.historyLimit)
    }

    // MARK: - Robustness

    @Test("corrupt snapshots decode to nil, never crash")
    @MainActor
    func corruptSnapshotTolerance() {
        let (store, _) = makeWorld()
        #expect(store.asset(from: Data("garbage".utf8)) == nil)
        #expect(store.asset(from: Data()) == nil)
    }
}
