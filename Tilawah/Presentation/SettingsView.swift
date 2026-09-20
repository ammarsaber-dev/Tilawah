//
//  SettingsView.swift
//  Tilawah
//
//  Settings (Phase 4): Wi-Fi-only downloads, measured storage usage,
//  delete-all, and the required provider attribution (AGENTS.md §5).
//

import SwiftUI

struct SettingsView: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    @State private var usageBytes: Int64 = 0
    @State private var confirmsDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("التنزيل عبر Wi-Fi فقط", isOn: wifiBinding)
                    HStack {
                        Text("المساحة المستخدمة")
                        Spacer()
                        Text(formattedUsage)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    Button("حذف جميع التنزيلات", role: .destructive) {
                        confirmsDeleteAll = true
                    }
                    .disabled(usageBytes == 0 && downloads.completedRecords().isEmpty)
                } header: {
                    Text("التنزيلات")
                } footer: {
                    Text("تُحفظ التنزيلات داخل التطبيق فقط ولا تظهر في تطبيق الملفات.")
                }

                Section {
                    HStack {
                        Text("المزوّد")
                        Spacer()
                        Text("MP3Quran")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    Text("التسجيلات للاستخدام الشخصي داخل التطبيق. الحقوق محفوظة لأصحابها.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("المحتوى الصوتي")
                }

                Section {
                    HStack {
                        Text("الإصدار")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("عن تلاوة")
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("إغلاق الإعدادات")
                }
            }
            .task {
                refreshUsage()
            }
            .confirmationDialog(
                "حذف جميع التنزيلات؟",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("حذف الكل", role: .destructive) {
                    downloads.deleteAllDownloads()
                    refreshUsage()
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيُحذف كل الصوت المُنزّل من الجهاز. يمكنك إعادة تنزيله لاحقًا.")
            }
        }
    }

    private var wifiBinding: Binding<Bool> {
        Binding(
            get: { downloads.wifiOnly },
            set: { downloads.wifiOnly = $0 }
        )
    }

    private var formattedUsage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: usageBytes)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "1.0"
    }

    private func refreshUsage() {
        usageBytes = downloads.storageUsage()
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(PreviewDownloads.makeStore())
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
