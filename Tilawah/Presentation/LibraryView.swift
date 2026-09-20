//
//  LibraryView.swift
//  Tilawah
//
//  User library (Phase 5): favorites, playlists, recent plays, bookmarks.
//  Lists read via `@Query` (auto-updating); mutations go through `LibraryStore`.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var controller

    @Query(sort: \FavoriteItem.createdAt, order: .reverse)
    private var favorites: [FavoriteItem]
    @Query(sort: \Playlist.createdAt, order: .forward)
    private var playlists: [Playlist]
    @Query(sort: \HistoryEntry.playedAt, order: .reverse)
    private var history: [HistoryEntry]
    @Query(sort: \Bookmark.createdAt, order: .reverse)
    private var bookmarks: [Bookmark]

    @State private var newPlaylistName = ""
    @State private var isCreatingPlaylist = false

    var body: some View {
        List {
            favoritesSection
            playlistsSection
            historySection
            bookmarksSection
        }
        .listStyle(.plain)
        .navigationTitle("المكتبة")
        .alert("قائمة جديدة", isPresented: $isCreatingPlaylist) {
            TextField("اسم القائمة", text: $newPlaylistName)
            Button("إنشاء") {
                library.createPlaylist(name: newPlaylistName)
                newPlaylistName = ""
            }
            Button("إلغاء", role: .cancel) {
                newPlaylistName = ""
            }
        }
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        Section {
            if favorites.isEmpty {
                Text("لا توجد مفضلة بعد. اضغط مطولًا على أي سورة لإضافتها.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(favorites) { item in
                    if let asset = library.asset(from: item.snapshot) {
                        Button {
                            controller.play(queue: [asset], index: 0)
                        } label: {
                            LibraryAssetRow(
                                title: asset.surahName ?? "سورة \(asset.surahID)",
                                subtitle: asset.reciterName,
                                isCurrent: controller.current?.id == asset.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        library.removeFavorite(assetID: favorites[offset].assetID)
                    }
                }
            }
        } header: {
            Text("المفضلة")
        }
    }

    // MARK: - Playlists

    private var playlistsSection: some View {
        Section {
            if playlists.isEmpty {
                Text("لا توجد قوائم بعد. أنشئ قائمتك الأولى.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        HStack {
                            Text(playlist.name)
                            Spacer()
                            Text("\(library.playlistAssets(playlistID: playlist.id).count, format: .number)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        library.deletePlaylist(playlists[offset])
                    }
                }
            }
            Button {
                isCreatingPlaylist = true
            } label: {
                Label("قائمة جديدة", systemImage: "plus.circle")
            }
        } header: {
            Text("القوائم")
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section {
            if history.isEmpty {
                Text("لم تستمع إلى شيء بعد.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.prefix(8)) { entry in
                    if let asset = library.asset(from: entry.snapshot) {
                        Button {
                            controller.play(queue: [asset], index: 0)
                        } label: {
                            LibraryAssetRow(
                                title: asset.surahName ?? "سورة \(asset.surahID)",
                                subtitle: "\(asset.reciterName) • \(relativeDate(entry.playedAt))",
                                isCurrent: controller.current?.id == asset.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if history.count > 1 {
                    Button("مسح السجل", role: .destructive) {
                        library.clearHistory()
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Text("الاستماع الأخير")
        }
    }

    // MARK: - Bookmarks

    private var bookmarksSection: some View {
        Section {
            if bookmarks.isEmpty {
                Text("لا توجد علامات بعد. احفظ موضعك من المشغّل الكامل.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bookmarks) { bookmark in
                    if let asset = library.asset(from: bookmark.snapshot) {
                        Button {
                            controller.play(queue: [asset], index: 0, startAt: bookmark.position)
                        } label: {
                            LibraryAssetRow(
                                title: asset.surahName ?? "سورة \(asset.surahID)",
                                subtitle: "\(asset.reciterName) • \(PlaybackTimeFormatter.string(from: bookmark.position))",
                                isCurrent: controller.current?.id == asset.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        library.deleteBookmark(bookmarks[offset])
                    }
                }
            }
        } header: {
            Text("العلامات")
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct LibraryAssetRow: View {
    let title: String
    let subtitle: String
    var isCurrent: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(isCurrent ? .bold : .regular)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("تُشغَّل الآن")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Library") {
    NavigationStack {
        LibraryView()
    }
    .environment(PreviewLibrary.makeStore())
    .environment(PreviewPlayback.makeController())
    .modelContainer(for: [
        FavoriteItem.self, Playlist.self, PlaylistItem.self,
        Bookmark.self, HistoryEntry.self,
    ], inMemory: true)
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
}
