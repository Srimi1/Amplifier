# Amplifier

<img src="docs/brand/logo.svg" width="96" height="96" alt="Amplifier logo: three ascending audio bars" />

A small native Kotlin background volume booster for Android 8.0+ (API 26), targeting Android 16 (API 36). Designed for trying the standard AOSP audio effect framework on LegionOS. No root, audio recording, Internet permission, account, or analytics.

The default boost is **+6 dB**, approximately **2× signal amplitude**, with a slider from 0 to +15 dB in 0.5 dB steps. This does not mean twice the perceived loudness. Android’s `LoudnessEnhancer` compresses signals that would exceed the supported sample range, so the actual increase depends on the content.

## Install without Android Studio

For the published app, open [GitHub Releases](https://github.com/Srimi1/Amplifier/releases/latest), download `amplifier-1.0.0.apk` from **Assets**, and open it on your phone. Allow installation from that browser/file manager when Android asks. Release APKs are signed with the app’s private release key and have debugging disabled.

For a development build:

1. Open this repository’s **Actions** tab and select a successful **Build APK** run for your branch.
2. Under **Artifacts**, download **amplifier-debug-apk**. GitHub may require you to sign in.
3. Extract the ZIP. Transfer `app-debug.apk` to your phone, or download and extract it there.
4. Open the APK and allow installation from that browser/file manager when Android asks.
5. Open **Amplifier**, enable boost, allow notifications, and optionally allow unrestricted background use. Start at +6 dB.

The notification shows the current gain. **Pause boost / Resume boost** provides a quick comparison while keeping the service ready; **Stop** turns it off and removes the notification. The main switch also stops the service. Gain, global-mode choice, enabled state, and pause state survive restarts. If enabled, Amplifier attempts to restart after reboot (once the phone is unlocked) and after an app update. The launcher, notification, app header, and interface use a minimal black-and-white design; [logo sources](docs/brand/) are included.

Debug builds use the app ID `dev.legion.amplifier.debug`, separate from the release app ID `dev.legion.amplifier`. Enable only one of them to avoid competing audio effects. All debug builds use the same **public development signing key** in `gradle/debug.keystore`, allowing later debug APKs to install as updates. Its alias is `androiddebugkey` and both passwords are `android`. This is a test key, not a secret or a production signing identity.

If you installed the initial development APK that used `dev.legion.amplifier` with the debug key, uninstall it before installing the signed release; Android will reject an update with a different signature. Later releases must keep the original private release key to update existing installs.

## Why YouTube can sound quieter than Reels

Different videos are mastered at different loudness levels. Reels often use heavily compressed, loud audio. YouTube also applies loudness normalization, and its **Stable volume** feature smooths loud and quiet portions. Chrome and streaming services may play quieter source material. This difference alone does not indicate a broken phone.

In YouTube’s video settings, try turning off **Stable volume**, when available. Loudness normalization may still apply; this switch does not disable every form of normalization. Compare the same passage at the same system volume.

## How attachment works

- **Global mix (session 0):** a `LoudnessEnhancer` attempts to attach to the output mix. This is deprecated by Android and ROM dependent. When usable, it can cover Chrome and other players that do not announce sessions. It may also affect other audio routed through the same mix.
- **Announced app sessions:** exported runtime and manifest receivers handle `AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION` and `ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION`. The manifest receiver lets players discover Amplifier before sending targeted broadcasts. It forwards only to an already running service; broadcasts never enable or start the service. Voice sessions are excluded from this path.
- **One gain stage:** both attachment strategies are maintained, but per-session processing stays disabled while the global effect is controllable and enabled. If the global effect is unavailable or loses control, announced sessions become the fallback. Gain is never intentionally stacked twice. Turn off **Use global mix** to test session mode directly.
- **Foreground service:** Android 14+ uses the declared `specialUse` type with a description of continuous, user-enabled audio processing. A low-importance notification supplies pause/resume and stop controls. No polling or wake lock is needed.

Using **ExoPlayer/Media3 does not by itself guarantee session broadcasts**. The player app must opt in. YouTube and Crunchyroll coverage depends on their version and playback path; Amplifier cannot force them to announce IDs or enumerate arbitrary existing sessions. Enable Amplifier before starting playback, or fully stop and reopen a player to obtain a new session announcement.

The status screen shows whether the global effect is attached and enabled, and how many announced sessions are actively boosted. With global mode active, **0 per-app sessions boosted is normal**: those effects remain fallback attachments. These counts describe Android effect state, not measured loudness or proof that the audio route actually processes the effect.

## Limitations and troubleshooting

- **ROM and route support must be tested on the phone.** Session 0 may be rejected or have no audible effect on LegionOS or a particular speaker/Bluetooth/headphone route. Successful construction and enabling cannot prove audible gain. If global mode is ineffective, disable it and test whether your player announces a session.
- If global mode is blocked, an app that does not broadcast its session ID cannot be boosted with this approach. **Chrome commonly needs global mode.** There is no universal, no-root guarantee for all apps.
- High boosts can distort already loud content. The built-in limiter helps, but does not make +15 dB distortion free. Reduce the gain when audio sounds rough.
- Other audio effects, including Wavelet, Dolby, and ROM equalizers, can compete for control or combine their processing. Turn them off when comparing. Amplifier reports control conflicts and responds when Android reports control changes.
- Hardware-offloaded, direct, tunneled, protected, and remote/cast playback may bypass local effects. No boost is promised for those paths. The app cannot exceed physical speaker limits.
- Starting after playback has begun cannot recover a session announcement that already happened. Restart the player. Stale sessions from players that omit a close event are bounded to 32; toggle Amplifier off and on to clear them.
- Battery restrictions and ROM task management can stop background processing. Allow unrestricted battery use if needed. If notifications are denied, Android can still run the foreground service, but its ordinary notification controls may be hidden; enable them in **Notification settings**. A muted notification channel can also hide controls.
- Reboot recovery is best effort. Android’s force-stop/task-manager Stop and restricted battery settings can prevent restart. Open Amplifier to resume; a sticky service restart remains subject to Android scheduling. Pausing is remembered, so a paused service stays paused after reboot.

## Build locally

Use JDK 17 or 21, Android SDK platform 36, and build tools 36.0.0. The checked-in Gradle 8.13 wrapper verifies its distribution checksum; Android Gradle Plugin is 8.13.2 and Kotlin is 2.2.21.

```sh
sdkmanager 'platforms;android-36' 'build-tools;36.0.0'
sdkmanager --licenses
# Set ANDROID_HOME to the SDK directory, or create local.properties with sdk.dir=...
./gradlew assembleDebug
./gradlew testDebugUnitTest lint lintRelease
```

Debug APK: `app/build/outputs/apk/debug/app-debug.apk`. Code and resource lint warnings fail the build; upgrade notices for pinned tools and the intentional Android 16 target are excluded. Every push and pull request builds the debug APK, runs the routing/lifetime unit tests and debug/release lint, and uploads the APK and validation reports. APK artifacts expire after 30 days; rerun the workflow to regenerate one. Published release assets remain available on GitHub Releases.

### Signed release build

Copy `release-signing.properties.example` to `release-signing.properties` and supply the path, alias, and passwords for your private release keystore. The real signing properties and private keystores are excluded from Git. Preserve the original release key and credentials in a secure backup for future app updates.

```sh
./gradlew assembleRelease
apksigner verify --verbose app/build/outputs/apk/release/app-release.apk
```

With signing configured, the release APK is `app/build/outputs/apk/release/app-release.apk` and has debugging disabled. Without signing properties, Gradle produces an unsigned release APK that cannot be installed. CI publishes development APKs without access to the private release key; signed GitHub releases are built and verified separately.

## Verify on LegionOS / Android 16

Build and lint validate the app, but audible gain and background survival require device checks. No LegionOS phone is attached to this build environment.

1. Disable other equalizers. Install the APK, allow notifications, and enable Amplifier **before** opening a player. Use a moderate system volume and +6 dB.
2. In YouTube, turn off Stable volume if available. Replay the same passage and compare **Pause boost / Resume boost**. Confirm both notification actions and the main switch work.
3. Repeat with a Chrome video and Crunchyroll. Note the global status and announced/boosted session counts. With global mode off, restart each player and repeat to check session support independently.
4. Move between speaker, wired/USB headphones, and Bluetooth if relevant. If a route stops responding, toggle boost off/on, restart playback, and record the route and status.
5. Set 0 dB, +6 dB, and a higher gain. Confirm 0 dB adds no amplification and reduce gain if the limiter or distortion becomes noticeable.
6. Leave the app, lock/unlock the phone, and verify the notification and audible boost remain. Pause and resume from the notification.
7. Reboot while enabled, unlock the phone, check that the notification returns, then start playback and compare again. Reboot while disabled and confirm it stays off. A paused enabled service should return paused.
8. Stop Amplifier and verify the effect is removed. Closing a player should remove its announced session when it broadcasts a close event.

Relevant platform APIs: [LoudnessEnhancer](https://developer.android.com/reference/android/media/audiofx/LoudnessEnhancer), [AudioEffect session broadcasts](https://developer.android.com/reference/android/media/audiofx/AudioEffect#ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION), and [special-use foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use).
