//
//  DownloadSessionDelegate.swift
//  Tilawah
//
//  URLSessionDownloadDelegate for the downloads session (Phase 4).
//  Callbacks arrive off-main on the session's serial delegate queue.
//
//  Iron rule: `didFinishDownloadingTo` MUST consume the temp file before
//  returning (the system deletes it afterwards). Validation + atomic move
//  therefore happen synchronously here from a cached context — never after
//  an async hop. The store is then told what happened for state + records.
//

import Foundation

/// Everything the delegate needs synchronously at completion time.
struct DownloadContext: Sendable {
    var assetID: String
    var relativePath: String
}

final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    weak var store: DownloadStore?
    private let lock = NSLock()
    private var contexts: [Int: DownloadContext] = [:]

    func seedContext(_ context: DownloadContext, taskIdentifier: Int) {
        lock.withLock { contexts[taskIdentifier] = context }
    }

    func dropContext(taskIdentifier: Int) {
        _ = lock.withLock { contexts.removeValue(forKey: taskIdentifier) }
    }

    private func context(taskIdentifier: Int) -> DownloadContext? {
        lock.withLock { contexts[taskIdentifier] }
    }

    // MARK: - Progress

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let store else { return }
        let assetID = DownloadTaskIdentity.decode(downloadTask.taskDescription)
        let progress: Double? = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : nil
        Task { @MainActor [weak store] in
            store?.reportProgress(assetID: assetID, taskIdentifier: downloadTask.taskIdentifier, progress: progress)
        }
    }

    // MARK: - Completion (synchronous hot path)

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskID = downloadTask.taskIdentifier
        let context = context(taskIdentifier: taskID)
        dropContext(taskIdentifier: taskID)

        let http = downloadTask.response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        let mime = http?.mimeType
        let expected = downloadTask.countOfBytesExpectedToReceive
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0

        guard let context else {
            // Relaunch race: context not yet re-seeded. Stage the file
            // synchronously so it survives, finalize after the hop.
            let staged = stageOrphanedFile(location)
            Task { @MainActor [weak store] in
                store?.finalizeStagedFile(
                    staged, assetID: DownloadTaskIdentity.decode(downloadTask.taskDescription),
                    statusCode: status, mimeType: mime, fileSize: size, expectedLength: expected
                )
            }
            return
        }

        let localRoot = store?.localRoot
        let outcome: Result<URL, DownloadValidationError>
        if let localRoot {
            outcome = moveValidatedFile(
                location, relativePath: context.relativePath, localRoot: localRoot,
                statusCode: status, mimeType: mime, fileSize: size, expectedLength: expected
            )
        } else {
            outcome = .failure(.missingTempFile)
        }

        Task { @MainActor [weak store] in
            switch outcome {
            case .success:
                store?.reportFinished(assetID: context.assetID, taskIdentifier: taskID)
            case let .failure(error):
                try? FileManager.default.removeItem(at: location)
                store?.reportFailed(
                    assetID: context.assetID, taskIdentifier: taskID,
                    message: DownloadValidator.arabicMessage(for: error)
                )
            }
        }
    }

    // MARK: - Errors

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Nil error also fires after successful downloads — ignore it.
        guard let error else { return }
        let nsError = error as NSError
        let taskID = task.taskIdentifier
        dropContext(taskIdentifier: taskID)

        var resumeData: Data?
        if nsError.domain == NSURLErrorDomain {
            resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        }
        Task { @MainActor [weak store] in
            store?.reportTaskError(
                assetID: DownloadTaskIdentity.decode(task.taskDescription),
                taskIdentifier: taskID, resumeData: resumeData,
                isCancellation: (error as NSError).code == NSURLErrorCancelled
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak store] in
            store?.finishBackgroundEvents(for: session.configuration.identifier)
        }
    }

    // MARK: - Private

    private func moveValidatedFile(
        _ location: URL, relativePath: String, localRoot: URL,
        statusCode: Int, mimeType: String?, fileSize: Int, expectedLength: Int64
    ) -> Result<URL, DownloadValidationError> {
        if case let .failure(error) = DownloadValidator.validate(
            statusCode: statusCode, mimeType: mimeType, fileSize: fileSize,
            expectedLength: expectedLength >= 0 ? expectedLength : nil
        ) {
            return .failure(error)
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
            try FileManager.default.moveItem(at: location, to: destination)
            try DownloadFilesystem.setExcludedFromBackup(destination)
            return .success(destination)
        } catch {
            return .failure(.missingTempFile)
        }
    }

    private func stageOrphanedFile(_ location: URL) -> URL? {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("TilawahStaging", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let staged = staging.appendingPathComponent(UUID().uuidString + ".mp3")
            try FileManager.default.moveItem(at: location, to: staged)
            return staged
        } catch {
            return nil
        }
    }
}
