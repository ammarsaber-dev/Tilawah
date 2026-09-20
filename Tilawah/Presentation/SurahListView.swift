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
    let reciter: Reciter
    let mushaf: Mushaf

    private var availableIDs: [Int] {
        mushaf.availableSurahIDs
    }

    var body: some View {
        List {
            if availableIDs.isEmpty {
                ContentUnavailableView(
                    "لا توجد سور متاحة",
                    systemImage: "book.closed",
                    description: Text("لا يتوفّر أي تسجيل في هذه المجموعة حاليًا.")
                )
            } else {
                Section {
                    ForEach(availableIDs, id: \.self) { surahID in
                        SurahRow(
                            surahID: surahID,
                            surah: store.surah(id: surahID)
                        )
                    }
                } header: {
                    Text("\(availableIDs.count, format: .number) سورة متاحة")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(mushaf.name)
    }
}

private struct SurahRow: View {
    let surahID: Int
    let surah: Surah?

    var body: some View {
        HStack(spacing: 12) {
            Text(surahID, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let name = surah?.name {
                    Text(name)
                        .font(.headline)
                } else {
                    Text("سورة \(surahID, format: .number)")
                        .font(.headline)
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
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
}
