import AVFoundation
import XCTest
@testable import Amplifier

final class PlaybackTests: XCTestCase {
    private func settings() -> UserDefaults {
        UserDefaults(suiteName: "Amplifier.tests.\(UUID().uuidString)")!
    }

    @MainActor
    func testImportedAudioHasGainTapAndDoesNotAutoPlay() async throws {
        let source = try DemoTone.make()
        defer { try? FileManager.default.removeItem(at: source) }
        let playback = MediaPlayback(defaults: settings(), systemControls: false)
        defer { playback.clear() }
        await playback.importFile(source)
        XCTAssertNil(playback.errorMessage)
        XCTAssertTrue(playback.hasAudio)
        XCTAssertFalse(playback.hasVideo)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.gainDB, 6)
        XCTAssertEqual(playback.duration, 15, accuracy: 0.02)
        XCTAssertNotNil(playback.player.currentItem?.audioMix?.inputParameters.first?.audioTapProcessor)
    }

    @MainActor
    func testInvalidFileKeepsPreviouslyImportedMedia() async throws {
        let source = try DemoTone.make()
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID().uuidString).mp4")
        try Data("This is not a video".utf8).write(to: invalid)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: invalid)
        }
        let playback = MediaPlayback(defaults: settings(), systemControls: false)
        defer { playback.clear() }
        await playback.importFile(source)
        let item = playback.player.currentItem
        let title = playback.title
        await playback.importFile(invalid)
        XCTAssertNotNil(playback.errorMessage)
        XCTAssertTrue(item === playback.player.currentItem)
        XCTAssertEqual(playback.title, title)
    }

    @MainActor
    func testRestoreKeepsSettingsAndRemainsPaused() async throws {
        let source = try DemoTone.make()
        defer { try? FileManager.default.removeItem(at: source) }
        let defaults = settings()
        let first = MediaPlayback(defaults: defaults, systemControls: false)
        await first.importFile(source)
        first.gainDB = 11.5
        first.boostEnabled = false
        let restored = MediaPlayback(defaults: defaults, systemControls: false)
        defer { first.clear(); restored.clear() }
        await restored.restore()
        XCTAssertTrue(restored.hasMedia)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertFalse(restored.boostEnabled)
        XCTAssertEqual(restored.gainDB, 11.5)
    }

    @MainActor
    func testRemoteURLsAreRejectedAndClearRemovesSavedMedia() async throws {
        let defaults = settings()
        let playback = MediaPlayback(defaults: defaults, systemControls: false)
        await playback.importFile(URL(string: "https://example.com/video.mp4")!)
        XCTAssertFalse(playback.hasMedia)
        XCTAssertNotNil(playback.errorMessage)
        let source = try DemoTone.make()
        defer { try? FileManager.default.removeItem(at: source) }
        await playback.importFile(source)
        let filename = try XCTUnwrap(defaults.string(forKey: "lastMediaName"))
        playback.clear()
        XCTAssertNil(playback.player.currentItem)
        XCTAssertNil(defaults.string(forKey: "lastMediaName"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: MediaFiles.directory.appendingPathComponent(filename).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testLocalVideoKeepsVideoAndProcessesItsAudio() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "quiet-video", withExtension: "mp4"))
        let playback = MediaPlayback(defaults: settings(), systemControls: false)
        defer { playback.clear() }
        await playback.importFile(source)
        XCTAssertNil(playback.errorMessage)
        XCTAssertTrue(playback.hasVideo)
        XCTAssertTrue(playback.hasAudio)
        XCTAssertEqual(playback.duration, 3, accuracy: 0.05)
        XCTAssertNotNil(playback.player.currentItem?.audioMix?.inputParameters.first?.audioTapProcessor)
    }
}
