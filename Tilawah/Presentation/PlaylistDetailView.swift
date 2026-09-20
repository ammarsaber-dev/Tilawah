//
//  PlaylistDetailView.swift
//  Tilawah
//
//  One playlist: play, reorder, remove, rename.
//

import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var controller
    let playlist: Playlist

    @Query(sort: \PlaylistItem.sortIndex, order: .forward)
    private var allItems: [PlaylistItem]

    @State private var isRenaming = false
    @State private var renameText: String = ""

    private var items: [PlaylistItem] {
        allItems.filter { $0.playlistID == playlist.id }
    }

    private var assets: [AudioAsset] {
        items.compactMap { library.asset(from: $0.snapshot) }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "قائمة فارغة",
                    systemImage: "list.bullet",
                    description: Text("أضف سورًا من التصفح بالضغط المطوّل.")
                )
            } else {
                ForEach(Array(assets.enumerated()), id: \.element.id) { offset, asset in
                    Button {
                        controller.play(queue: assets, index: offset)
                    } label: {
                        LibraryAssetRow(
                            title: asset.surahName ?? "سورة \(asset.surahID)",
                            subtitle: asset.reciterName,
                            isCurrent: controller.current?.id == asset.id
                        )
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for offset in offsets {
                        library.removeFromPlaylist(items[offset])
                    }
                }
                .onMove { source, destination in
                    library.moveInPlaylist(playlistID: playlist.id, from: source, to: destination)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                EditButton()
                Button("إعادة تسمية") {
                    renameText = playlist.name
                    isRenaming = true
                }
            }
        }
        .alert("إعادة تسمية القائمة", isPresented: $isRenaming) {
            TextField("اسم القائمة", text: $renameText)
            Button("حفظ") {
                library.renamePlaylist(playlist, name: renameText)
            }
            Button("إلغاء", role: .cancel) {}
        }
    }
}
