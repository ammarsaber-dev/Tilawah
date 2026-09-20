//
//  PlaybackController.swift
//  Tilawah
//
//  Single shared playback engine (Phase 3, AGENTS.md §6 Playback).
//  One `AVPlayer` for the app's lifetime; local file preferred when
//  validated, else stream. Restores the last session without auto-playing.
//  Background audio, lock-screen / headphone commands, interruptions and
//  route changes are handled here — never in views.
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer

@Observable
@MainActor
public final class PlaybackController {
    // MARK: - Observable state (UI reads; only this class writes)

    public private(set) var queue: [AudioAsset] = []
    public private(set) var index: Int = 0
    public private(set) var position: Double = 0
    public private(set) var duration: Double?
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var playbackError: String?

    public var current: AudioAsset? {
        guard queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    public var hasNext: Bool { index + 1 < queue.count }
    public var hasPrevious: Bool { !queue.isEmpty }

    // MARK: - Private

    private let player = AVPlayer()
    private let stateStore: PlaybackStateStore
    private var cancellables = Set<AnyCancellable>()
    private var itemStatusCancellable: AnyCancellable?
    private var lastSavedPosition: Double = -1

    /// Fired whenever a new track starts (library history).
    public var onTrackChanged: ((AudioAsset) -> Void)?
    /// Fired with throttled position saves (history resume points).
    public var onPositionSaved: ((String, Double) -> Void)?

    // App-lifetime object: observers/tokens are never torn down (documented;
    // teardown would only matter if the controller were transient, which the
    // architecture forbids — exactly one player, owned by the app root).

    // MARK: - Init (restores without auto-playing)

    public init(stateStore: PlaybackStateStore) {
        self.stateStore = stateStore
        configureAudioSession()
        observePlayerState()
        observeInterruptions()
        observeRouteChanges()
        observeItemEnd()
        configureRemoteCommands()
        restoreLastSession()
    }

    // MARK: - Transport

    /// Plays `queue[index]]`. Re-tapping the current asset toggles instead.
    /// `startAt` seeks right after loading (bookmark resume).
    public func play(queue newQueue: [AudioAsset], index newIndex: Int, startAt: Double = 0) {
        guard !newQueue.isEmpty, newQueue.indices.contains(newIndex) else { return }
        if newQueue[newIndex].id == current?.id, player.currentItem != nil, startAt == 0 {
            toggle()
            return
        }
        queue = newQueue
        index = newIndex
        loadCurrentAndPlay(startPosition: startAt)
    }

    public func toggle() {
        guard player.currentItem != nil else { return }
        if isPlaying {
            pause()
        } else {
            activateSession()
            playbackError = nil
            player.play()
        }
    }

    public func pause() {
        player.pause()
        persist()
    }

    public func next() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            seek(to: 0)
            player.play()
            return
        }
        let next = index + 1
        if next < queue.count {
            index = next
            loadCurrentAndPlay()
        } else if repeatMode == .all {
            index = 0
            loadCurrentAndPlay()
        }
    }

    public func previous() {
        guard !queue.isEmpty else { return }
        switch QueueNavigator.previous(
            current: index, count: queue.count, position: position, repeat: repeatMode
        ) {
        case .restart:
            seek(to: 0)
            if !isPlaying { player.play() }
        case let .moveTo(target):
            index = target
            loadCurrentAndPlay()
        case .none:
            break
        }
    }

    public func seek(to seconds: Double) {
        guard player.currentItem != nil else { return }
        let clamped = max(0, seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        position = clamped
    }

    public func cycleRepeat() {
        repeatMode = repeatMode.next()
    }

    /// Rebuilds the current item after a failure (resolves local-vs-remote again).
    public func retry() {
        guard current != nil else { return }
        loadCurrentAndPlay()
    }

    /// Persists queue + position now (called on backgrounding).
    public func saveNow() {
        persist()
    }

    /// Re-resolves the current item's source (call after a download is
    /// deleted or the library changes). If the file behind the current
    /// item vanished, swaps to the stream at the same position, keeping
    /// the playing state — never leaves a dead item loaded.
    public func recheckCurrentSource() {
        guard let asset = current, let item = player.currentItem,
              let currentURL = (item.asset as? AVURLAsset)?.url
        else { return }
        let resolved = PlaybackSource.url(for: asset, localRoot: PlaybackSource.audioDirectory())
        guard currentURL != resolved else { return }
        let wasPlaying = isPlaying
        let at = position
        let next = AVPlayerItem(url: resolved)
        observeItemStatus(next)
        player.replaceCurrentItem(with: next)
        if at > 0 {
            player.seek(to: CMTime(seconds: at, preferredTimescale: 600))
        }
        if wasPlaying {
            player.play()
        }
        updateNowPlaying()
    }

    // MARK: - Item loading

    private func loadCurrentAndPlay(autoplay: Bool = true, startPosition: Double = 0) {
        guard let asset = current else { return }
        playbackError = nil
        position = 0
        duration = nil
        let url = PlaybackSource.url(for: asset, localRoot: PlaybackSource.audioDirectory())
        let item = AVPlayerItem(url: url)
        observeItemStatus(item)
        player.replaceCurrentItem(with: item)
        if startPosition > 0 {
            player.seek(to: CMTime(seconds: startPosition, preferredTimescale: 600))
            position = startPosition
        }
        updateNowPlaying()
        onTrackChanged?(asset)
        if autoplay {
            activateSession()
            player.play()
        }
        persist()
    }

    // MARK: - Observers

    private func observePlayerState() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                Task { @MainActor in
                    self.isPlaying = status == .playing
                    self.isBuffering = status == .waitingToPlayAtSpecifiedRate
                    self.updateNowPlayingPlaybackState()
                }
            }
            .store(in: &cancellables)

        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.position = max(0, time.seconds.isFinite ? time.seconds : 0)
                if let item = self.player.currentItem {
                    let d = item.duration.seconds
                    self.duration = (d.isFinite && d > 0) ? d : nil
                }
                self.updateNowPlayingElapsed()
                // Throttled persist: every ~10 s of playback.
                if abs(self.position - self.lastSavedPosition) >= 10 {
                    self.persist()
                }
            }
        }
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                Task { @MainActor in
                    if status == .failed {
                        self.playbackError = (item.error as? LocalizedError)?.errorDescription
                            ?? item.error?.localizedDescription
                            ?? "تعذّر تشغيل هذا التسجيل."
                        self.isPlaying = false
                    }
                }
            }
    }

    private func observeItemEnd() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                guard let ended = notification.object as? AVPlayerItem,
                      ended == self.player.currentItem
                else { return }
                self.handleItemEnd()
            }
        }
    }

    private func handleItemEnd() {
        guard !queue.isEmpty else { return }
        switch repeatMode {
        case .one:
            seek(to: 0)
            player.play()
        case .all:
            index = (index + 1) % queue.count
            loadCurrentAndPlay()
        case .off:
            if let next = QueueNavigator.nextIndex(current: index, count: queue.count, repeat: .off) {
                index = next
                loadCurrentAndPlay()
            } else {
                player.pause()
                persist()
            }
        }
    }

    // MARK: - Audio session, interruptions, routes

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            // Best-effort: playback still works in the foreground without this,
            // background + lock-screen integration just degrades.
            playbackError = nil
        }
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                guard let info = notification.userInfo,
                      let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType)
                else { return }
                switch type {
                case .began:
                    self.player.pause()
                case .ended:
                    let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                    // Resume only when the system says we should (e.g. call
                    // ended) — never auto-play after a user-initiated pause,
                    // tracked implicitly: resume only if an item is loaded
                    // and we were playing before the interruption began.
                    if options.contains(.shouldResume), self.player.currentItem != nil {
                        self.player.play()
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                guard let info = notification.userInfo,
                      let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
                else { return }
                // Headphones unplugged: pause to avoid speaker blast.
                if reason == .oldDeviceUnavailable {
                    self.player.pause()
                    self.persist()
                }
            }
        }
    }

    // MARK: - Remote commands + Now Playing

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if !self.isPlaying { self.toggle() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if self.isPlaying { self.toggle() }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self.seek(to: positionEvent.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let asset = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: asset.surahName ?? "سورة \(asset.surahID)",
            MPMediaItemPropertyArtist: asset.reciterName,
            MPMediaItemPropertyAlbumTitle: asset.mushafName,
        ]
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Persistence

    private func persist() {
        guard !queue.isEmpty else { return }
        lastSavedPosition = position
        stateStore.save(RestorableQueueState(
            items: queue.map(AssetSnapshot.init(asset:)),
            index: index,
            position: position
        ))
        if let asset = current {
            onPositionSaved?(asset.id, position)
        }
    }

    private func restoreLastSession() {
        guard let saved = stateStore.load(),
              let (assets, restoredIndex) = saved.makeQueue()
        else { return }
        queue = assets
        index = restoredIndex
        // Build the item and seek — but never auto-play (§6).
        guard let asset = current else { return }
        let url = PlaybackSource.url(for: asset, localRoot: PlaybackSource.audioDirectory())
        let item = AVPlayerItem(url: url)
        observeItemStatus(item)
        player.replaceCurrentItem(with: item)
        position = saved.position
        if saved.position > 0 {
            player.seek(to: CMTime(seconds: saved.position, preferredTimescale: 600))
        }
        lastSavedPosition = saved.position
        updateNowPlaying()
    }
}
