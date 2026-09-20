//
//  AddToPlaylistSheet.swift
//  Tilawah
//
//  Adds one surah to an existing playlist or a new one.
//

import SwiftUI
import SwiftData

struct AddToPlaylistSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let asset: AudioAsset

    @Query(sort: \Playlist.createdAt, order: .forward)
    private var playlists: [Playlist]

    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("قائمة جديدة", text: $newName)
                        Button("إنشاء وإضافة") {
                            if let playlist = library.createPlaylist(name: newName) {
                                library.addToPlaylist(asset, playlist: playlist)
                                dismiss()
                            }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if !playlists.isEmpty {
                    Section("القوائم") {
                        ForEach(playlists) { playlist in
                            Button {
                                library.addToPlaylist(asset, playlist: playlist)
                                dismiss()
                            } label: {
                                Text(playlist.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("إضافة إلى قائمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") {
                        dismiss()
                    }
                }
            }
        }
    }
}
