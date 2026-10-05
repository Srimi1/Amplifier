import Foundation

enum MediaFiles {
    struct Imported: Sendable {
        let url: URL
        let title: String
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedMedia", isDirectory: true)
    }

    // File-provider coordination and copying run off the main actor. The player
    // reads only this app-owned copy after the picker permission is released.
    static func copy(_ source: URL) throws -> Imported {
        guard source.isFileURL else { throw MediaError.localFilesOnly }
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readableURL in
            do { try FileManager.default.copyItem(at: readableURL, to: destination) }
            catch { copyError = error }
        }
        if let error = coordinationError ?? copyError as NSError? {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw MediaError.unreadable
        }
        return Imported(url: destination, title: source.deletingPathExtension().lastPathComponent)
    }

    static func remove(_ url: URL?) {
        guard let url, url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func cleanup(keeping filename: String?) {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent != filename { remove(url) }
    }
}

enum MediaError: LocalizedError {
    case localFilesOnly, unreadable, unplayable, protectedContent, noTracks, processingUnavailable

    var errorDescription: String? {
        switch self {
        case .localFilesOnly: "Choose an audio or video file from Files. Streaming links aren’t supported."
        case .unreadable: "This file couldn’t be opened. Download it in Files and try again."
        case .unplayable: "This file can’t be played. Try an MP3, AAC, WAV, M4A, MOV, or MP4 file."
        case .protectedContent: "Protected media can’t be amplified. Choose an unprotected local file."
        case .noTracks: "This file doesn’t contain playable audio or video."
        case .processingUnavailable: "Audio processing couldn’t be prepared for this file."
        }
    }
}
