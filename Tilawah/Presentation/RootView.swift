//
//  RootView.swift
//  Tilawah
//
//  App tab root (Phase 5): Explore / Library / Downloads, each with its own
//  navigation stack. The mini-player lives at this level so it persists
//  across tabs.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(PlaybackController.self) private var controller
    @State private var isPlayerExpanded = false

    var body: some View {
        TabView {
            Tab("تصفح", systemImage: "books.vertical") {
                NavigationStack {
                    RecitersView()
                }
            }
            Tab("المكتبة", systemImage: "heart") {
                NavigationStack {
                    LibraryView()
                }
            }
            Tab("التنزيلات", systemImage: "arrow.down.circle") {
                NavigationStack {
                    DownloadsView()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if controller.current != nil {
                MiniPlayer(isExpanded: $isPlayerExpanded)
            }
        }
        .sheet(isPresented: $isPlayerExpanded) {
            ExpandedPlayer()
        }
    }
}

#Preview("Root") {
    RootView()
        .environment(CatalogStore(service: PreviewCatalogService()))
        .environment(PreviewPlayback.makeController())
        .environment(PreviewDownloads.makeStore())
        .environment(PreviewLibrary.makeStore())
        .modelContainer(for: [
            FavoriteItem.self, Playlist.self, PlaylistItem.self,
            Bookmark.self, HistoryEntry.self, PersistedDownload.self,
        ], inMemory: true)
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
