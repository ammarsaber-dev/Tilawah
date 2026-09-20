//
//  TilawahApp.swift
//  Tilawah
//
//  Composition root: builds the service graph once (catalog service,
//  persistence, playback engine) and injects shared stores via the
//  environment (AGENTS.md §6). Arabic-first UI: forced RTL + `ar` locale.
//

import SwiftUI
import SwiftData

@main
struct TilawahApp: App {
    private let container: ModelContainer
    @State private var catalogStore: CatalogStore
    @State private var playbackController: PlaybackController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = PersistenceFactory.makeContainer()
        self.container = container
        let stateStore = PlaybackStateStore(container: container)
        _catalogStore = State(initialValue: CatalogStore(service: MP3QuranService()))
        // Restores the last session inside; never auto-plays.
        _playbackController = State(initialValue: PlaybackController(stateStore: stateStore))
    }

    var body: some Scene {
        WindowGroup {
            RecitersView()
                .environment(catalogStore)
                .environment(playbackController)
                .environment(\.locale, Locale(identifier: "ar"))
                .environment(\.layoutDirection, .rightToLeft)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        playbackController.saveNow()
                    }
                }
        }
        .modelContainer(container)
    }
}
