//
//  RecitersView.swift
//  Tilawah
//
//  Root browse screen (Phase 2): reciters from the live catalog with
//  search and fully-handled async states (loading / empty / error /
//  offline / retry). Arabic-first, RTL.
//

import SwiftUI

struct RecitersView: View {
    @Environment(CatalogStore.self) private var store
    @State private var query = ""
    @State private var isSettingsPresented = false

    var body: some View {
        content
            .navigationTitle("القرّاء")
            .searchable(text: $query, prompt: "ابحث عن قارئ")
            .task {
                await store.load()
            }
            .refreshable {
                await store.reload()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("الإعدادات")
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.phase == .loading && store.reciters.isEmpty {
            ProgressView("جارٍ تحميل القرّاء…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.failure, store.reciters.isEmpty {
            catalogErrorView(error)
        } else {
            let results = store.filteredReciters(query: query)
            if results.isEmpty, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search
            } else if results.isEmpty {
                ContentUnavailableView(
                    "لا يوجد قرّاء",
                    systemImage: "mic.slash",
                    description: Text("لم تصل أي بيانات من المزوّد. اسحب للتحديث وحاول مجددًا.")
                )
            } else {
                List(results) { reciter in
                    NavigationLink {
                        ReciterDetailView(reciter: reciter)
                    } label: {
                        ReciterRow(reciter: reciter)
                    }
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .top) {
                    if store.isStale {
                        HStack(spacing: 8) {
                            Image(systemName: store.refreshError?.isOffline == true
                                ? "wifi.slash" : "exclamationmark.triangle")
                            Text("عرض نسخة محفوظة — لا يوجد اتصال حديث")
                                .font(.footnote)
                            Spacer()
                            Button("إعادة المحاولة") {
                                Task { await store.reload() }
                            }
                            .font(.footnote)
                            .fontWeight(.semibold)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("عرض نسخة محفوظة من الفهرس")
                    }
                }
            }
        }
    }

    private func catalogErrorView(_ error: CatalogError) -> some View {
        ContentUnavailableView {
            Label(
                error.isOffline ? "لا يوجد اتصال" : "تعذّر التحميل",
                systemImage: error.isOffline ? "wifi.slash" : "exclamationmark.triangle"
            )
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("إعادة المحاولة") {
                Task { await store.reload() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct ReciterRow: View {
    let reciter: Reciter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reciter.name)
                .font(.headline)
            Text("\(reciter.moshaf.count, format: .number) من التسجيلات")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Reciters") {
    NavigationStack {
        RecitersView()
    }
        .environment(CatalogStore(service: PreviewCatalogService()))
        .environment(PreviewPlayback.makeController())
        .environment(PreviewDownloads.makeStore())
        .environment(PreviewLibrary.makeStore())
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}

#Preview("Reciters — offline") {
    NavigationStack {
        RecitersView()
    }
        .environment(CatalogStore(service: PreviewFailingCatalogService()))
        .environment(PreviewPlayback.makeController())
        .environment(PreviewDownloads.makeStore())
        .environment(PreviewLibrary.makeStore())
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
