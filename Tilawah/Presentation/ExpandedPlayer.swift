//
//  ExpandedPlayer.swift
//  Tilawah
//
//  Full player sheet: identity, seek, transport, repeat, error + retry.
//  Neutral placeholder artwork — the provider supplies none (§8).
//

import SwiftUI

struct ExpandedPlayer: View {
    @Environment(PlaybackController.self) private var controller
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let asset = controller.current {
                VStack(spacing: 20) {
                    Spacer(minLength: 8)

                    Image(systemName: "opticaldisc")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text(asset.surahName ?? "سورة \(asset.surahID)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        Text(asset.reciterName)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(asset.mushafName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    if let error = controller.playbackError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error)
                                .font(.footnote)
                            Button("إعادة المحاولة") {
                                controller.retry()
                            }
                            .font(.footnote)
                            .fontWeight(.semibold)
                        }
                        .foregroundStyle(.red)
                    }

                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { controller.position },
                                set: { controller.seek(to: $0) }
                            ),
                            in: 0 ... max(controller.duration ?? 0, 1)
                        )
                        .disabled(controller.duration == nil)
                        .accessibilityLabel("موضع التشغيل")
                        HStack {
                            Text(PlaybackTimeFormatter.string(from: controller.position))
                            Spacer()
                            Text(PlaybackTimeFormatter.string(from: controller.duration ?? 0))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "الموضع \(PlaybackTimeFormatter.string(from: controller.position))" +
                                " من \(PlaybackTimeFormatter.string(from: controller.duration ?? 0))"
                        )
                    }

                    HStack(spacing: 36) {
                        Button {
                            controller.previous()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.title2)
                        }
                        .disabled(!controller.hasPrevious && controller.position <= 5)
                        .accessibilityLabel("السابق")

                        Button {
                            controller.toggle()
                        } label: {
                            Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                        }
                        .disabled(controller.isBuffering)
                        .accessibilityLabel(controller.isPlaying ? "إيقاف مؤقت" : "تشغيل")

                        Button {
                            controller.next()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                        }
                        .disabled(!controller.hasNext && controller.repeatMode != .all)
                        .accessibilityLabel("التالي")
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.cycleRepeat()
                    } label: {
                        Label(controller.repeatMode.label, systemImage: repeatIcon)
                    }
                    .font(.footnote)
                    .foregroundStyle(controller.repeatMode == .off ? Color.secondary : Color.accentColor)

                    HStack(spacing: 24) {
                        Button {
                            library.toggleFavorite(asset)
                        } label: {
                            Label(
                                isFavorite ? "في المفضلة" : "إضافة إلى المفضلة",
                                systemImage: isFavorite ? "heart.fill" : "heart"
                            )
                        }
                        Button {
                            library.addBookmark(asset, position: controller.position)
                        } label: {
                            Label("حفظ علامة هنا", systemImage: "bookmark")
                        }
                    }
                    .font(.footnote)

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 24)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .accessibilityLabel("إغلاق المشغّل")
                    }
                }
            } else {
                ContentUnavailableView(
                    "لا يوجد تشغيل",
                    systemImage: "opticaldisc",
                    description: Text("اختر سورة من التصفح لبدء الاستماع.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .accessibilityLabel("إغلاق المشغّل")
                    }
                }
            }
        }
    }

    private var repeatIcon: String {
        switch controller.repeatMode {
        case .off: "repeat"
        case .all: "repeat"
        case .one: "repeat.1"
        }
    }

    private var isFavorite: Bool {
        guard let asset = controller.current else { return false }
        return library.isFavorite(assetID: asset.id)
    }
}
