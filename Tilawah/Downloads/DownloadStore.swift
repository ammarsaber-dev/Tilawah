//
//  DownloadStore.swift
//  Tilawah
//
//  Offline downloads (Phase 4, AGENTS.md §6 Downloads + §7 storage rules).
//  `@Observable @MainActor` front-end over a background `URLSession`:
//  max 3 concurrent, no duplicates, pause/resume with resume data,
//  HTTP+MIME+size validation before an atomic move into
//  `Application Support/Audio/<reciter>/<mushaf>/<surah>.mp3`, backup
//  exclusion, and relaunch reconciliation via stable `taskDescription`s.
//

import Foundation
import SwiftData

public enum DownloadStatus: Equatable, Sendable {
    case notDownloaded
    case queued
    /// `progress` nil = length unknown (indeterminate UI).
    case downloading(progress: Double?)
    case paused(progress: Double?)
    case completed
    case failed(message: String)
}

@Observable
@MainActor
public final class DownloadStore {
    public static let sessionIdentifier = "dev.ammarsaber.Tilawah.downloads"
    private static let wifiOnlyKey = "tilawah.downloads.wifiOnly"

    /// Set at init; `AppDelegate` routes background completion handlers here.
    static var backgroundInstance: DownloadStore?

    // MARK: - Observable state

    private(set) var states: [String: DownloadStatus] = [:]
    var wifiOnly: Bool {
        didSet {
            UserDefaults.standard.set(wifiOnly, forKey: Self.wifiOnlyKey)
            if oldValue != wifiOnly {
                recreateSession()
            }
        }
    }

    // MARK: - Collaborators / config

    @ObservationIgnored weak var playbackController: PlaybackController?
    let localRoot: URL
    private let context: ModelContext
    private let delegate = DownloadSessionDelegate()
    private var session: URLSession

    // MARK: - Bookkeeping (in-memory; records persist completions)

    private var meta: [String: AudioAsset] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]
    private var suppressedErrorTaskIDs = Set<Int>()
    private var queue = PendingDownloadQueue()
    private var backgroundHandlers: [String: () -> Void] = [:]

    // MARK: - Init

    /// - Parameter makeSession: injects the session (tests pass an ephemeral
    ///   one; the provided delegate MUST be used or callbacks never arrive).
    init(
        container: ModelContainer,
        localRoot: URL = PlaybackSource.audioDirectory(),
        makeSession: ((DownloadSessionDelegate) -> URLSession)? = nil
    ) {
        context = ModelContext(container)
        self.localRoot = localRoot
        let wifi = UserDefaults.standard.object(forKey: Self.wifiOnlyKey) as? Bool ?? true
        wifiOnly = wifi
        session = makeSession?(delegate) ?? URLSession(
            configuration: Self.backgroundConfiguration(wifiOnly: wifi),
            delegate: delegate, delegateQueue: nil
        )
        delegate.store = self
        Self.backgroundInstance = self
        Task { [weak self] in await self?.reconcile() }
    }

    // MARK: - Reads

    public func status(for asset: AudioAsset) -> DownloadStatus {
        states[asset.id] ?? .notDownloaded
    }

    public func storageUsage() -> Int64 {
        DownloadFilesystem.librarySize(localRoot: localRoot)
    }

    public func completedRecords() -> [PersistedDownload] {
        (try? context.fetch(FetchDescriptor<PersistedDownload>()))?.filter(\.isComplete) ?? []
    }

    // MARK: - Actions

    /// Starts (or retries) a download. Duplicates and already-completed
    /// assets are ignored. Self-heals: an on-disk file without a record is
    /// adopted instead of re-downloaded.
    public func download(_ asset: AudioAsset) {
        let id = asset.id
        if states[id] == .completed { return }
        if queue.contains(id) { return }
        let file = DownloadFilesystem.destination(for: asset, localRoot: localRoot)
        if PlaybackSource.isPlayableFile(at: file) {
            adoptCompleted(asset)
            return
        }
        meta[id] = asset
        upsertRecord(PersistedDownload(asset: asset))
        states[id] = .queued
        queue.request(id)
        pumpQueue()
    }

    /// Enqueues every asset in `assets` that is missing locally.
    /// Already-completed, queued, or actively-downloading assets are skipped,
    /// so tapping "download all" twice never duplicates work. The existing
    /// 3-concurrent FIFO pump handles the backlog.
    /// - Returns: the number of assets newly enqueued.
    @discardableResult
    public func downloadAll(_ assets: [AudioAsset]) -> Int {
        var enqueued = 0
        for asset in assets {
            let id = asset.id
            switch states[id] {
            case .completed, .queued, .downloading, .paused:
                continue
            case .failed, .notDownloaded, nil:
                break
            }
            let file = DownloadFilesystem.destination(for: asset, localRoot: localRoot)
            if PlaybackSource.isPlayableFile(at: file) {
                adoptCompleted(asset)
                continue
            }
            meta[id] = asset
            upsertRecord(PersistedDownload(asset: asset))
            states[id] = .queued
            queue.request(id)
            enqueued += 1
        }
        pumpQueue()
        return enqueued
    }

    /// Assets in `assets` still missing locally (for "download all" counts).
    public func remainingDownloads(in assets: [AudioAsset]) -> Int {
        assets.filter { asset in
            if states[asset.id] == .completed { return false }
            let file = DownloadFilesystem.destination(for: asset, localRoot: localRoot)
            return !PlaybackSource.isPlayableFile(at: file)
        }.count
    }

    public func pause(assetID: String) {
        guard let task = tasks[assetID], states[assetID]?.isDownloading == true else { return }
        suppressedErrorTaskIDs.insert(task.taskIdentifier)
        let lastProgress = states[assetID]?.progress
        task.cancel { [weak self] data in
            Task { @MainActor [weak self] in
                self?.finishPause(assetID: assetID, resumeData: data, lastProgress: lastProgress)
            }
        }
    }

    public func resume(assetID: String) {
        guard case .paused = states[assetID] else { return }
        states[assetID] = .queued
        queue.request(assetID)
        pumpQueue()
    }

    /// Abandons a queued/active/paused download (no file exists yet).
    public func cancel(assetID: String) {
        if let task = tasks[assetID] {
            suppressedErrorTaskIDs.insert(task.taskIdentifier)
            task.cancel()
            tasks.removeValue(forKey: assetID)
        }
        queue.remove(assetID)
        resumeData.removeValue(forKey: assetID)
        removeRecord(assetID: assetID)
        states[assetID] = .notDownloaded
    }

    /// Deletes a completed download (file + record). Also used for
    /// delete-all via records. Never touches favorites/playlists.
    public func delete(assetID: String, relativePath: String? = nil) {
        if let task = tasks[assetID] {
            suppressedErrorTaskIDs.insert(task.taskIdentifier)
            task.cancel()
            tasks.removeValue(forKey: assetID)
        }
        queue.remove(assetID)
        resumeData.removeValue(forKey: assetID)
        let path = relativePath
            ?? meta[assetID].map { DownloadFilesystem.destination(for: $0, localRoot: localRoot).path }
            ?? record(for: assetID).map { localRoot.appendingPathComponent($0.relativePath).path }
        if let path {
            try? FileManager.default.removeItem(atPath: path)
        }
        removeRecord(assetID: assetID)
        states[assetID] = .notDownloaded
        playbackController?.recheckCurrentSource()
    }

    public func deleteAllDownloads() {
        for (assetID, task) in tasks {
            suppressedErrorTaskIDs.insert(task.taskIdentifier)
            task.cancel()
        }
        tasks.removeAll()
        queue = PendingDownloadQueue()
        resumeData.removeAll()
        for record in completedRecords() {
            let file = localRoot.appendingPathComponent(record.relativePath)
            try? FileManager.default.removeItem(at: file)
            context.delete(record)
        }
        try? context.save()
        for key in states.keys where states[key] == .completed {
            states[key] = .notDownloaded
        }
        playbackController?.recheckCurrentSource()
    }

    // MARK: - Delegate callbacks (called via MainActor hops)

    func reportProgress(assetID: String?, taskIdentifier: Int, progress: Double?) {
        guard let assetID, case .downloading = states[assetID] else { return }
        states[assetID] = .downloading(progress: progress)
    }

    func reportFinished(assetID: String, taskIdentifier: Int) {
        tasks.removeValue(forKey: assetID)
        queue.markFinished(assetID)
        suppressedErrorTaskIDs.remove(taskIdentifier)
        completeDownload(assetID: assetID)
        pumpQueue()
    }

    func reportFailed(assetID: String, taskIdentifier: Int, message: String) {
        tasks.removeValue(forKey: assetID)
        queue.markFinished(assetID)
        suppressedErrorTaskIDs.remove(taskIdentifier)
        resumeData.removeValue(forKey: assetID)
        states[assetID] = .failed(message: message)
        pumpQueue()
    }

    func reportTaskError(
        assetID: String?, taskIdentifier: Int, resumeData data: Data?, isCancellation: Bool
    ) {
        if suppressedErrorTaskIDs.remove(taskIdentifier) != nil { return }
        guard let assetID else { return }
        tasks.removeValue(forKey: assetID)
        queue.markFinished(assetID)
        if let data, !data.isEmpty {
            resumeData[assetID] = data
        }
        // Cancellations outside our own pause/cancel paths (e.g. session
        // invalidation we didn't initiate) requeue instead of failing.
        if isCancellation {
            states[assetID] = .queued
            queue.request(assetID)
        } else {
            states[assetID] = .failed(message: "تعذّر التنزيل. تحقق من الشبكة وحاول مجددًا.")
        }
        pumpQueue()
    }

    func finalizeStagedFile(
        _ staged: URL?, assetID: String?, statusCode: Int,
        mimeType: String?, fileSize: Int, expectedLength: Int64
    ) {
        guard let staged, let assetID else {
            if let staged { try? FileManager.default.removeItem(at: staged) }
            return
        }
        let relativePath: String
        if let asset = meta[assetID] {
            relativePath = asset.relativeStoragePath
        } else if let parts = AssetIDComponents.parse(assetID) {
            relativePath = parts.relativeStoragePath
        } else {
            try? FileManager.default.removeItem(at: staged)
            reportFailed(assetID: assetID, taskIdentifier: -1, message: "تعذّر حفظ الملف")
            return
        }
        if case .failure(let error) = DownloadValidator.validate(
            statusCode: statusCode, mimeType: mimeType, fileSize: fileSize,
            expectedLength: expectedLength >= 0 ? expectedLength : nil
        ) {
            try? FileManager.default.removeItem(at: staged)
            reportFailed(
                assetID: assetID, taskIdentifier: -1,
                message: DownloadValidator.arabicMessage(for: error)
            )
            return
        }
        do {
            try DownloadFilesystem.prepareLibrary(localRoot: localRoot)
            let destination = localRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staged, to: destination)
            try DownloadFilesystem.setExcludedFromBackup(destination)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            reportFailed(assetID: assetID, taskIdentifier: -1, message: "تعذّر حفظ الملف")
            return
        }
        reportFinished(assetID: assetID, taskIdentifier: -1)
    }

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void, for identifier: String?) {
        guard let identifier else {
            handler()
            return
        }
        backgroundHandlers[identifier] = handler
    }

    func finishBackgroundEvents(for identifier: String?) {
        guard let identifier, let handler = backgroundHandlers.removeValue(forKey: identifier) else {
            return
        }
        handler()
    }

    // MARK: - Private

    private func finishPause(assetID: String, resumeData data: Data?, lastProgress: Double?) {
        tasks.removeValue(forKey: assetID)
        queue.markFinished(assetID)
        if let data, !data.isEmpty {
            resumeData[assetID] = data
        }
        // Only pause what is still downloading (it may have finished first).
        if states[assetID]?.isDownloading == true {
            states[assetID] = .paused(progress: lastProgress)
        }
    }

    private func pumpQueue() {
        while let id = queue.takeNext() {
            guard meta[id] != nil, tasks[id] == nil else {
                if meta[id] == nil { queue.markFinished(id) }
                continue
            }
            startTask(assetID: id)
        }
    }

    private func startTask(assetID: String) {
        guard let asset = meta[assetID] else { return }
        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: assetID), !data.isEmpty {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: asset.streamURL)
        }
        task.taskDescription = DownloadTaskIdentity.encode(assetID)
        delegate.seedContext(
            DownloadContext(assetID: assetID, relativePath: asset.relativeStoragePath),
            taskIdentifier: task.taskIdentifier
        )
        tasks[assetID] = task
        if case .paused(let progress) = states[assetID] {
            states[assetID] = .downloading(progress: progress)
        } else {
            states[assetID] = .downloading(progress: states[assetID]?.progress)
        }
        task.resume()
    }

    private func completeDownload(assetID: String) {
        if let asset = meta[assetID] {
            let record = record(for: assetID) ?? PersistedDownload(asset: asset)
            if record.modelContext == nil {
                context.insert(record)
            }
            record.isComplete = true
            let file = DownloadFilesystem.destination(for: asset, localRoot: localRoot)
            record.totalBytes = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            record.updatedAt = Date()
            try? context.save()
        }
        states[assetID] = .completed
    }

    private func adoptCompleted(_ asset: AudioAsset) {
        meta[asset.id] = asset
        let record = record(for: asset.id) ?? PersistedDownload(asset: asset)
        if record.modelContext == nil {
            context.insert(record)
        }
        record.isComplete = true
        record.updatedAt = Date()
        try? context.save()
        states[asset.id] = .completed
    }

    private func recreateSession() {
        let activeIDs = Array(tasks.keys)
        for (_, task) in tasks {
            suppressedErrorTaskIDs.insert(task.taskIdentifier)
        }
        session.invalidateAndCancel()
        tasks.removeAll()
        for id in activeIDs {
            queue.remove(id)
            queue.request(id)
            if states[id]?.isDownloading == true || states[id]?.isPaused == true {
                states[id] = .queued
            }
        }
        session = URLSession(
            configuration: Self.backgroundConfiguration(wifiOnly: wifiOnly),
            delegate: delegate, delegateQueue: nil
        )
        pumpQueue()
    }

    private static func backgroundConfiguration(wifiOnly: Bool) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = !wifiOnly
        return config
    }

    // MARK: - Records

    private func record(for assetID: String) -> PersistedDownload? {
        let id = assetID
        let descriptor = FetchDescriptor<PersistedDownload>(predicate: #Predicate { $0.assetID == id })
        return try? context.fetch(descriptor).first
    }

    private func upsertRecord(_ record: PersistedDownload) {
        if record.modelContext == nil {
            if let existing = self.record(for: record.assetID) {
                existing.updatedAt = Date()
                try? context.save()
            } else {
                context.insert(record)
                try? context.save()
            }
        } else {
            try? context.save()
        }
    }

    private func removeRecord(assetID: String) {
        if let existing = record(for: assetID) {
            context.delete(existing)
            try? context.save()
        }
    }

    // MARK: - Relaunch reconciliation

    private func reconcile() async {
        let records = (try? context.fetch(FetchDescriptor<PersistedDownload>())) ?? []
        var dirty = false
        for record in records where record.isComplete {
            let file = localRoot.appendingPathComponent(record.relativePath)
            if PlaybackSource.isPlayableFile(at: file) {
                states[record.assetID] = .completed
            } else {
                // Missing-file reconciliation: download gone, entry stays.
                context.delete(record)
                states[record.assetID] = .notDownloaded
                dirty = true
            }
        }
        let liveTasks = await liveDownloadTasks()
        for task in liveTasks {
            guard let assetID = DownloadTaskIdentity.decode(task.taskDescription) else {
                task.cancel()
                continue
            }
            if let record = record(for: assetID), !record.isComplete,
               let asset = record.makeAsset()
            {
                meta[assetID] = asset
                tasks[assetID] = task
                queue.markActive(assetID)
                states[assetID] = .downloading(progress: nil)
                delegate.seedContext(
                    DownloadContext(assetID: assetID, relativePath: record.relativePath),
                    taskIdentifier: task.taskIdentifier
                )
            } else {
                task.cancel()
            }
        }
        for record in records where !record.isComplete && tasks[record.assetID] == nil {
            context.delete(record)
            states[record.assetID] = .notDownloaded
            dirty = true
        }
        if dirty {
            try? context.save()
        }
    }

    private func liveDownloadTasks() async -> [URLSessionDownloadTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks.compactMap { $0 as? URLSessionDownloadTask })
            }
        }
    }
}

// MARK: - Status conveniences

extension DownloadStatus {
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var progress: Double? {
        switch self {
        case let .downloading(progress): progress
        case let .paused(progress): progress
        default: nil
        }
    }
}

extension PersistedDownload {
    /// Rebuilds the asset for resume/retry; nil when the persisted URL
    /// is unusable or paths drifted.
    func makeAsset() -> AudioAsset? {
        guard let url = URL(string: streamURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        let asset = AudioAsset(
            reciterID: reciterID, mushafID: mushafID, surahID: surahID,
            reciterName: reciterName, mushafName: mushafName,
            surahName: surahName, streamURL: url
        )
        guard asset.relativeStoragePath == relativePath else { return nil }
        return asset
    }
}
