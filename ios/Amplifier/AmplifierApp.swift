import SwiftUI

@main
@MainActor
struct AmplifierApp: App {
    @State private var playback: MediaPlayback

    init() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let suite = "Amplifier.ui-tests"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            _playback = State(initialValue: MediaPlayback(defaults: defaults))
        } else {
            _playback = State(initialValue: MediaPlayback())
        }
    }

    var body: some Scene {
        WindowGroup {
            AmplifierView(playback: playback)
                .preferredColorScheme(.dark)
                .task {
                    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                        await playback.restore()
                    }
                }
                .onOpenURL { url in Task { await playback.importFile(url) } }
        }
    }
}
