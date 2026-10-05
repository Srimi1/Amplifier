import Foundation

enum DemoTone {
    // Quiet 15-second PCM fixture, also available through the app's sample button.
    // Generating it locally avoids a bundled download or microphone permission.
    static func make(directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let sampleRate: UInt32 = 44_100
        let frames = Int(sampleRate) * 15
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + frames * 2)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        text("data"); u32(UInt32(frames * 2))
        for frame in 0..<frames {
            let fadeIn = min(1.0, Double(frame) / (Double(sampleRate) * 0.03))
            let fadeOut = min(1.0, Double(frames - frame - 1) / (Double(sampleRate) * 0.03))
            let sample = 0.08 * fadeIn * fadeOut * sin(2.0 * .pi * 440.0 * Double(frame) / Double(sampleRate))
            u16(UInt16(bitPattern: Int16((sample * 32_767.0).rounded())))
        }
        let url = directory.appendingPathComponent("Amplifier sample-\(UUID().uuidString).wav")
        try data.write(to: url, options: .atomic)
        return url
    }
}
