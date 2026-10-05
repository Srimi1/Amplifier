import AVKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AmplifierView: View {
    @Bindable var playback: MediaPlayback
    @State private var showingImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Text("Amplify the files you play here.")
                    .font(.headline)
                Text("iPhone boost applies inside Amplifier. Audio from YouTube, Chrome, and other apps isn’t changed.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                mediaPanel
                GainPanel(playback: playback)
                VStack(alignment: .leading, spacing: 8) {
                    Text(playback.status)
                        .accessibilityIdentifier("boostStatus")
                    if playback.isBuffering { ProgressView("Preparing playback…") }
                    if let message = playback.errorMessage {
                        Text(message)
                            .accessibilityIdentifier("playbackError")
                    }
                    Text("Start at +6 dB. Lower the gain if loud passages sound distorted.")
                        .font(.footnote)
                }
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .tint(.white)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio, .movie]) { result in
            switch result {
            case .success(let url): Task { await playback.importFile(url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    playback.errorMessage = "The file picker couldn’t open this file. Try again from Files."
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image("BrandMark").resizable().frame(width: 64, height: 64).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Amplifier").font(.largeTitle.weight(.semibold))
                Text("A little more volume.").font(.subheadline)
            }
        }
    }

    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            if playback.isImporting { ProgressView("Opening media…").accessibilityIdentifier("importProgress") }
            if playback.hasMedia {
                Text(playback.title).font(.headline).lineLimit(2).accessibilityIdentifier("mediaTitle")
                if playback.hasVideo {
                    VideoPlayer(player: playback.player)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("videoPlayer")
                } else {
                    Image("BrandMark").resizable().scaledToFit().frame(height: 140)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                }
                PlaybackControls(playback: playback)
            } else {
                Text("Bring a quiet track or video.").font(.headline)
                Text("Import an unprotected file from Files, or try a quiet sample first.").font(.subheadline)
            }
            HStack(spacing: 16) {
                Button { showingImporter = true } label: { Label("Import file", systemImage: "plus") }
                    .accessibilityIdentifier("importMedia")
                    .disabled(playback.isImporting)
                Spacer()
                if playback.hasMedia {
                    Button("Remove", role: .destructive) { playback.clear() }
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("removeMedia")
                        .disabled(playback.isImporting)
                } else {
                    Button("Try sample") { Task { await playback.loadSample() } }
                        .accessibilityIdentifier("loadSample")
                        .disabled(playback.isImporting)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white, lineWidth: 1) }
    }
}

private struct GainPanel: View {
    @Bindable var playback: MediaPlayback

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Boost", isOn: $playback.boostEnabled)
                .font(.headline)
                .accessibilityIdentifier("boostToggle")
            HStack(alignment: .firstTextBaseline) {
                Text("Gain").font(.headline)
                Spacer()
                Text(String(format: "+%.1f dB", playback.gainDB))
                    .font(.title2.monospacedDigit())
                    .accessibilityIdentifier("gainValue")
            }
            Slider(value: $playback.gainDB, in: 0...15, step: 0.5) { Text("Gain") }
                .accessibilityValue(String(format: "%.1f decibels", playback.gainDB))
                .accessibilityIdentifier("gainSlider")
            VStack(spacing: 6) {
                HStack { Text("0 dB"); Spacer(); Text("+15 dB") }
                GeometryReader { geometry in
                    Text("+6 dB ≈ 2× amplitude")
                        .position(x: 16 + max(0, geometry.size.width - 32) * 0.4, y: 10)
                }
                .frame(height: 24)
            }
            .font(.caption)
        }
        .padding(20)
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white, lineWidth: 1) }
    }
}

private struct PlaybackControls: View {
    @Bindable var playback: MediaPlayback
    @State private var seekPosition = 0.0
    @State private var isSeeking = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(time(isSeeking ? seekPosition : playback.currentTime))
                Spacer()
                Text(time(playback.duration))
            }
            .font(.caption.monospacedDigit())
            Slider(value: Binding(get: { isSeeking ? seekPosition : playback.currentTime }, set: { seekPosition = $0 }), in: 0...max(1, playback.duration)) { Text("Playback position") } onEditingChanged: { editing in
                if editing { seekPosition = playback.currentTime }
                isSeeking = editing
                if !editing { playback.seek(to: seekPosition) }
            }
            .disabled(!playback.isReady || playback.duration <= 0)
            .accessibilityIdentifier("playbackPosition")
            HStack(spacing: 28) {
                Button { playback.seek(to: 0) } label: { Label("Restart", systemImage: "backward.end.fill") }
                    .accessibilityIdentifier("restartPlayback")
                Button { playback.togglePlayback() } label: {
                    Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                        .frame(minWidth: 66)
                }
                .accessibilityIdentifier("playPause")
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            }
            .buttonStyle(.bordered)
            .disabled(!playback.isReady)
        }
    }

    private func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

#Preview("Empty") { AmplifierView(playback: .preview()).preferredColorScheme(.dark) }
#Preview("Error") { AmplifierView(playback: .preview(error: true)).preferredColorScheme(.dark) }
