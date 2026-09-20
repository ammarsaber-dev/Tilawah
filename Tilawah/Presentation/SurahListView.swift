//
//  SurahListView.swift
//  Tilawah
//
//  Surahs actually available in one mushaf (parsed `surah_list` — never a
//  hardcoded 114). Rows are informational until the playback phase ships:
//  deliberately no play buttons, so nothing here is inert.
//

import SwiftUI

struct SurahListView: View {
    @Environment(CatalogStore.self) private var store
    @Environment(PlaybackController.self) private var controller
    @Environment(DownloadStore.self) private var downloads
    @Environment(LibraryStore.self) private var library
    let reciter: Reciter
    let mushaf: Mushaf

    @State private var playlistAsset: AudioAsset?

    private var queue: [AudioAsset] {
        store.queueAssets(reciter: reciter, mushaf: mushaf)
    }

    private var remainingCount: Int {
        downloads.remainingDownloads(in: queue)
    }

    var body: some View {
        List {
            if queue.isEmpty {
                ContentUnavailableView(
                    "لا توجد سور متاحة",
                    systemImage: "book.closed",
                    description: Text("لا يتوفّر أي تسجيل في هذه المجموعة حاليًا.")
                )
            } else {
                Section {
                    ForEach(Array(queue.enumerated()), id: \.element.id) { offset, asset in
                        HStack(spacing: 8) {
                            Button {
                                controller.play(queue: queue, index: offset)
                            } label: {
                                SurahRow(
                                    asset: asset,
                                    surah: store.surah(id: asset.surahID),
                                    isCurrent: controller.current?.id == asset.id,
                                    isPlaying: controller.isPlaying
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    library.toggleFavorite(asset)
                                } label: {
                                    Label(
                                        library.isFavorite(assetID: asset.id)
                                            ? "إزالة من المفضلة" : "إضافة إلى المفضلة",
                                        systemImage: library.isFavorite(assetID: asset.id)
                                            ? "heart.slash" : "heart"
                                    )
                                }
                                Button {
                                    playlistAsset = asset
                                } label: {
                                    Label("إضافة إلى قائمة…", systemImage: "text.badge.plus")
                                }
                            }
                            DownloadControl(asset: asset)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(queue.count, format: .number) سورة متاحة")
                        Spacer()
                        if remainingCount > 0 {
                            Button {
                                downloads.downloadAll(queue)
                            } label: {
                                Label(
                                    "تنزيل الكل (\(remainingCount, format: .number))",
                                    systemImage: "arrow.down.circle"
                                )
                            }
                            .font(.footnote)
                            .accessibilityLabel(
                                "تنزيل كل السور المتاحة في هذه المجموعة، \(remainingCount) سورة متبقية"
                            )
                        }
                    }
                } footer: {
                    Text("اضغط على أي سورة لبدء الاستماع، أو نزّلها للاستماع دون إنترنت.")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(mushaf.name)
        .sheet(item: $playlistAsset) { asset in
            AddToPlaylistSheet(asset: asset)
        }
    }
}

private struct SurahRow: View {
    let asset: AudioAsset
    let surah: Surah?
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(asset.surahID, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let name = surah?.name {
                    Text(name)
                        .font(.headline)
                        .fontWeight(isCurrent ? .bold : .regular)
                } else {
                    Text("سورة \(asset.surahID, format: .number)")
                        .font(.headline)
                        .fontWeight(isCurrent ? .bold : .regular)
                }
                if let surah, let makkia = surah.makkia {
                    if makkia == 1 {
                        Text("مكية")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("مدنية")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: isPlaying ? "waveform" : "pause")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(isPlaying ? "تُشغَّل الآن" : "متوقفة مؤقتًا")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Surah list") {
    NavigationStack {
        SurahListView(
            reciter: PreviewCatalogService.sampleReciters[0],
            mushaf: PreviewCatalogService.sampleReciters[0].moshaf[0]
        )
    }
    .environment(CatalogStore(service: PreviewCatalogService()))
    .environment(PreviewPlayback.makeController())
    .environment(PreviewDownloads.makeStore())
    .environment(PreviewLibrary.makeStore())
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
}
