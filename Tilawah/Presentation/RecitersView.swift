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
    @Environment(PlaybackController.self) private var controller
    @State private var query = ""
    @State private var isPlayerExpanded = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("القرّاء")
                .searchable(text: $query, prompt: "ابحث عن قارئ")
                .task {
                    await store.load()
                }
                .refreshable {
                    await store.reload()
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
    RecitersView()
        .environment(CatalogStore(service: PreviewCatalogService()))
        .environment(PreviewPlayback.makeController())
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}

#Preview("Reciters — offline") {
    RecitersView()
        .environment(CatalogStore(service: PreviewFailingCatalogService()))
        .environment(PreviewPlayback.makeController())
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
