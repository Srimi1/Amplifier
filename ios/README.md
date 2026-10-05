# Amplifier for iPhone

Native SwiftUI player for **iOS 26+**, including iPhone 17, built with **Xcode 26**. It uses the same minimal black-and-white icon as the Android app.

**This version amplifies imported audio and video played inside Amplifier. It cannot boost YouTube, Chrome, Crunchyroll, or any other app.** iOS has no public equivalent of Android's global output-mix effects. Xcode builds an iOS app; it does not remove that platform restriction.

## Playback

- Import an unprotected local audio or video file from Files; MP3, AAC, M4A, WAV, MOV, and MP4 are typical supported formats. Codec support depends on AVFoundation.
- Gain defaults to +6 dB (approximately 2× amplitude), with 0–15 dB in 0.5 dB steps. A soft limiter bounds boosted samples; high gain can still introduce distortion.
- **Boost off and 0 dB bypass processing exactly.** The gain switch changes the current file's sound without restarting playback.
- Play, pause, seek, and restart; video retains its picture while its audio is processed. Lock-screen playback controls and background audio are enabled for the app's own playback.
- Headphone disconnection pauses playback. Calls interrupt it; automatic resumption follows the system's resume indication. Saved gain, boost choice, and the last imported file are restored paused when the app opens.
- **Try sample** prepares a quiet, locally generated tone. Press Play and compare the boost switch at a moderate system volume.

Files are copied into the app's private storage. **Remove** deletes only that imported copy. Failed imports preserve the previous file. No microphone, account, analytics, or streaming download is used by the app. The system Files provider may download a file from iCloud when you select it.

## Open and run in Xcode

1. On a Mac with Xcode 26, clone this repository and switch to `codex/ios-iphone-17`, or download the iOS source artifact from a successful **Build iPhone app** Actions run.
2. Open `ios/Amplifier.xcodeproj` and choose the shared **Amplifier** scheme.
3. Select the **iPhone 17** simulator and press Run. No Apple developer membership is needed for simulator use.
4. To run on a real iPhone 17, connect it to the Mac, enable Developer Mode when asked, select the phone in Xcode, and choose your Apple team under **Signing & Capabilities**. Xcode manages the development signing. You may need a unique bundle identifier for your team.

A free Apple ID can support personal device testing subject to Apple's provisioning limits. A **TestFlight or App Store release requires an Apple Developer Program account and signing/provisioning for that team**. No Apple credentials or signing files are committed to this repository.

## CI artifacts and signing

The macOS workflow selects Xcode 26.3, runs sanitizer checks and XCTest on an iPhone 17 simulator, builds a simulator app, and archives the device build without signing.

- **amplifier-ios-simulator** contains an `.app` for an iOS simulator on a Mac. It cannot be installed on an iPhone.
- **amplifier-ios-device-unsigned** contains an unsigned `.xcarchive`. It must be signed/exported by your Apple team before it can be installed or distributed.
- **amplifier-ios-validation** contains the Xcode source ZIP, logs, test result bundle, summary, screenshot, and build metadata when produced. Source and reports use the exact workflow commit.

There is **no installable iPhone IPA or TestFlight release** until Apple signing is configured. Android's APK and release key cannot install or sign this iOS app.

```sh
./ios/scripts/test-dsp.sh
xcodebuild -project ios/Amplifier.xcodeproj -scheme Amplifier \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Limits and device checks

The custom `MTAudioProcessingTap` processes this player's decoded 32-bit float, 16-bit integer, or 32-bit integer PCM. Gain controls use atomic state; the render callback allocates no memory and acquires no locks. Each tap retains its state independently of the UI object. An unsupported decoded format passes through and is reported in the app. This path is for local files; HLS, DRM, web embeds, cast playback, and other applications are not supported amplification sources.

Signal gain does not bypass the phone's hardware limits, system volume, or headphone safety settings. +6 dB is approximately twice the signal amplitude, not twice the perceived loudness. A simulator cannot prove speaker loudness or every real-device route.

On your iPhone 17, compare the sample and a quiet file with boost off/on, check video synchronization and seeking, test the lock screen and headphone/Bluetooth routes, verify call interruptions and unplugging headphones, and reopen the app to confirm paused restoration. Confirm that other apps' audio remains outside Amplifier's processing.

Apple references: [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession), [audio processing taps](https://developer.apple.com/documentation/mediatoolbox/mtaudioprocessingtap), and [AVAudioMix](https://developer.apple.com/documentation/avfoundation/avaudiomix).
