//
//  DownloadsView.swift
//  Tilawah
//
//  Completed offline copies (Phase 5): play offline-first, delete, usage.
//  Reads records via `@Query` so the list tracks download completions live.
//

import SwiftUI
import SwiftData

struct DownloadsView: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(PlaybackController.self) private var controller

    @Query(
        filter: #Predicate<PersistedDownload> { $0.isComplete },
        sort: \PersistedDownload.updatedAt, order: .reverse
    )
    private var completed: [PersistedDownload]

    private var queue: [AudioAsset] {
        completed.compactMap { $0.makeAsset() }
    }

    var body: some View {
        List {
            if completed.isEmpty {
                ContentUnavailableView(
                    "لا توجد تنزيلات",
                    systemImage: "arrow.down.circle",
                    description: Text("نزّل السور من التصفح للاستماع دون إنترنت.")
                )
            } else {
                Section {
                    ForEach(Array(queue.enumerated()), id: \.element.id) { offset, asset in
                        HStack(spacing: 8) {
                            Button {
                                controller.play(queue: queue, index: offset)
                            } label: {
                                LibraryAssetRow(
                                    title: asset.surahName ?? "سورة \(asset.surahID)",
                                    subtitle: asset.reciterName,
                                    isCurrent: controller.current?.id == asset.id
                                )
                            }
                            .buttonStyle(.plain)
                            Button {
                                downloads.delete(assetID: asset.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("حذف تنزيل سورة \(asset.surahName ?? "\(asset.surahID)")")
                        }
                    }
                } header: {
                    Text("\(completed.count, format: .number) من السور • \(usageString)")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("التنزيلات")
    }

    private var usageString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: downloads.storageUsage())
    }
}

#Preview("Downloads") {
    NavigationStack {
        DownloadsView()
    }
    .environment(PreviewDownloads.makeStore())
    .environment(PreviewPlayback.makeController())
    .modelContainer(for: [PersistedDownload.self], inMemory: true)
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
}
