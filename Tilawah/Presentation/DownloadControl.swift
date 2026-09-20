//
//  DownloadControl.swift
//  Tilawah
//
//  Per-surah download affordance: download → progress/pause →
//  completed → delete, plus failed → retry. Indeterminate progress while
//  the server length is unknown.
//

import SwiftUI

struct DownloadControl: View {
    @Environment(DownloadStore.self) private var store
    let asset: AudioAsset

    @State private var confirmsDelete = false

    var body: some View {
        Group {
            switch store.status(for: asset) {
            case .notDownloaded:
                Button {
                    store.download(asset)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                }
                .accessibilityLabel("تنزيل سورة \(asset.surahName ?? "\(asset.surahID)") للاستماع دون إنترنت")

            case .queued:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("بانتظار التنزيل")

            case let .downloading(progress):
                HStack(spacing: 8) {
                    if let progress {
                        ProgressView(value: progress)
                            .frame(width: 56)
                            .accessibilityLabel("جارٍ التنزيل")
                            .accessibilityValue("\(Int(progress * 100))٪")
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("جارٍ التنزيل")
                    }
                    Button {
                        store.pause(assetID: asset.id)
                    } label: {
                        Image(systemName: "pause.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("إيقاف التنزيل مؤقتًا")
                }

            case let .paused(progress):
                HStack(spacing: 8) {
                    Button {
                        store.resume(assetID: asset.id)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("استئناف التنزيل")
                    Button {
                        store.cancel(assetID: asset.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("إلغاء التنزيل")
                    if let progress {
                        Text("\(Int(progress * 100))٪")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }

            case .completed:
                Button {
                    confirmsDelete = true
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .accessibilityLabel("تم التنزيل")
                .accessibilityHint("اضغط لحذف التنزيل")
                .confirmationDialog(
                    "حذف التنزيل؟",
                    isPresented: $confirmsDelete,
                    titleVisibility: .visible
                ) {
                    Button("حذف التنزيل", role: .destructive) {
                        store.delete(assetID: asset.id)
                    }
                    Button("إلغاء", role: .cancel) {}
                } message: {
                    Text("سيُحذف الملف الصوتي من الجهاز. يمكنك إعادة تنزيله لاحقًا.")
                }

            case .failed:
                Button {
                    store.download(asset)
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.title3)
                }
                .accessibilityLabel("فشل التنزيل. اضغط لإعادة المحاولة")
            }
        }
        .buttonStyle(.plain)
    }
}
