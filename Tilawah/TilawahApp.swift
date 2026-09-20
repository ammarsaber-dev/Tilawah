//
//  TilawahApp.swift
//  Tilawah
//
//  Composition root: builds the service graph once (catalog service,
//  persistence, playback engine, downloads, library) and injects shared
//  stores via the environment (AGENTS.md §6). Arabic-first UI: forced RTL
//  + `ar` locale.
//

import SwiftUI
import SwiftData
import UIKit

/// Forwards background URLSession events (download completion while the app
/// was suspended/terminated) to the `DownloadStore`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if let store = DownloadStore.backgroundInstance {
                store.setBackgroundCompletionHandler(completionHandler, for: identifier)
            } else {
                completionHandler()
            }
        }
    }
}

@main
struct TilawahApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    @State private var catalogStore: CatalogStore
    @State private var playbackController: PlaybackController
    @State private var downloadStore: DownloadStore
    @State private var libraryStore: LibraryStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = PersistenceFactory.makeContainer()
        self.container = container
        let stateStore = PlaybackStateStore(container: container)
        let playback = PlaybackController(stateStore: stateStore)
        let downloads = DownloadStore(container: container)
        downloads.playbackController = playback
        let library = LibraryStore(container: container)
        playback.onTrackChanged = { asset in library.recordPlay(asset) }
        playback.onPositionSaved = { assetID, position in
            library.updateHistoryPosition(assetID: assetID, position: position)
        }
        _catalogStore = State(initialValue: CatalogStore(service: MP3QuranService()))
        // Restores the last session inside; never auto-plays.
        _playbackController = State(initialValue: playback)
        _downloadStore = State(initialValue: downloads)
        _libraryStore = State(initialValue: library)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(catalogStore)
                .environment(playbackController)
                .environment(downloadStore)
                .environment(libraryStore)
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
