//
//  TilawahApp.swift
//  Tilawah
//
//  Composition root (Phase 2): builds the service graph once and injects
//  shared stores via the environment (AGENTS.md §6). Arabic-first UI:
//  forced RTL + `ar` locale for v1.
//

import SwiftUI

@main
struct TilawahApp: App {
    @State private var catalogStore = CatalogStore(service: MP3QuranService())

    var body: some Scene {
        WindowGroup {
            RecitersView()
                .environment(catalogStore)
                .environment(\.locale, Locale(identifier: "ar"))
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
