//
//  MiniPlayer.swift
//  Tilawah
//
//  Compact bar pinned above the bottom edge while something is loaded.
//  Tap the track info to expand the full player sheet.
//

import SwiftUI

struct MiniPlayer: View {
    @Environment(PlaybackController.self) private var controller
    @Binding var isExpanded: Bool

    var body: some View {
        if let asset = controller.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        isExpanded = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "opticaldisc")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.surahName ?? "سورة \(asset.surahID)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Text(asset.reciterName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "المشغّل المصغّر: \(asset.surahName ?? "سورة \(asset.surahID)")، \(asset.reciterName)"
                    )
                    .accessibilityHint("اضغط لفتح المشغّل الكامل")

                    if controller.isBuffering {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("جارٍ التحميل")
                    } else {
                        Button {
                            controller.toggle()
                        } label: {
                            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(controller.isPlaying ? "إيقاف مؤقت" : "تشغيل")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var progress: Double {
        guard let duration = controller.duration, duration > 0 else { return 0 }
        return min(max(controller.position / duration, 0), 1)
    }
}
