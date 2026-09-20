//
//  ReciterDetailView.swift
//  Tilawah
//
//  A reciter's recording collections (mushafs): name, riwayah, and the
//  count of actually-available surahs. Tapping a mushaf opens its surah list.
//

import SwiftUI

struct ReciterDetailView: View {
    @Environment(CatalogStore.self) private var store
    let reciter: Reciter

    var body: some View {
        List {
            if reciter.moshaf.isEmpty {
                ContentUnavailableView(
                    "لا توجد تسجيلات",
                    systemImage: "opticaldisc",
                    description: Text("لا يتوفّر أي تسجيل لهذا القارئ حاليًا.")
                )
            } else {
                ForEach(reciter.moshaf) { mushaf in
                    NavigationLink {
                        SurahListView(reciter: reciter, mushaf: mushaf)
                    } label: {
                        MushafRow(mushaf: mushaf, riwayahName: store.riwayahName(id: mushaf.rewayaID))
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(reciter.name)
    }
}

private struct MushafRow: View {
    let mushaf: Mushaf
    let riwayahName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mushaf.name)
                .font(.headline)
            HStack(spacing: 8) {
                if let riwayahName {
                    Text(riwayahName)
                }
                Text("\(mushaf.availableSurahIDs.count, format: .number) سورة متاحة")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Reciter detail") {
    NavigationStack {
        ReciterDetailView(reciter: PreviewCatalogService.sampleReciters[0])
    }
    .environment(CatalogStore(service: PreviewCatalogService()))
    .environment(PreviewPlayback.makeController())
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
}
