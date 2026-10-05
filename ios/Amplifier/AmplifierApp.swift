import SwiftUI

@main
@MainActor
struct AmplifierApp: App {
    @State private var playback: MediaPlayback
    @State private var restoration: Task<Void, Never>?

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
                .task { await restoreBeforeOpeningFiles() }
                .onOpenURL { url in
                    Task {
                        await restoreBeforeOpeningFiles()
                        await playback.importFile(url)
                    }
                }
        }
    }

    private func restoreBeforeOpeningFiles() async {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if let restoration {
            await restoration.value
            return
        }
        let model = playback
        let task = Task { await model.restore() }
        restoration = task
        await task.value
    }
}
