#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"
mkdir -p build/ios-artifacts build/ios-logs
xcodebuild -version

run_xcode() {
  local log_file="$1"
  shift
  if ! xcodebuild "$@" >"$log_file" 2>&1; then
    tail -160 "$log_file"
    return 1
  fi
  tail -8 "$log_file"
}

phase="${1:-all}"
if [[ "$phase" == compile || "$phase" == all ]]; then
  git archive --format=zip --prefix=Amplifier-iOS/ --output=build/ios-artifacts/amplifier-ios-source.zip HEAD ios docs/brand
  run_xcode build/ios-logs/compile.log \
    -project ios/Amplifier.xcodeproj -scheme Amplifier -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios \
    build-for-testing CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO
fi

if [[ "$phase" == test || "$phase" == all ]]; then
  ios_runtime_id="$(xcrun simctl list runtimes --json | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-26-")]
if not runtimes:
    raise SystemExit("An iOS 26 simulator runtime is required")
print(max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))["identifier"])
')"
  ios_simulator_id="$(xcrun simctl create 'Amplifier iPhone 17 CI' com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$ios_runtime_id")"
  trap 'xcrun simctl shutdown "$ios_simulator_id" >/dev/null 2>&1 || true; xcrun simctl delete "$ios_simulator_id" >/dev/null 2>&1 || true' EXIT
  run_xcode build/ios-logs/tests.log \
    -project ios/Amplifier.xcodeproj -scheme Amplifier -configuration Debug \
    -destination "platform=iOS Simulator,id=$ios_simulator_id" -destination-timeout 120 \
    -derivedDataPath build/ios -resultBundlePath build/ios-tests.xcresult \
    -parallel-testing-enabled NO test-without-building CODE_SIGNING_ALLOWED=NO
  xcrun xcresulttool get test-results summary --path build/ios-tests.xcresult > build/ios-artifacts/test-summary.json
  xcrun simctl launch --terminate-running-process "$ios_simulator_id" com.srimi1.amplifier
  xcrun simctl io "$ios_simulator_id" screenshot build/ios-artifacts/iPhone-17.png
fi

# A simulator app and an unsigned archive are development artifacts. A device
# install or TestFlight release must be signed with the owner's Apple team.
if [[ "$phase" == archive || "$phase" == all ]]; then
  run_xcode build/ios-logs/simulator.log \
  -project ios/Amplifier.xcodeproj -scheme Amplifier -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios \
  build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO
  ditto -c -k --keepParent build/ios/Build/Products/Debug-iphonesimulator/Amplifier.app build/ios-artifacts/amplifier-ios-simulator.zip
  run_xcode build/ios-logs/device.log \
  -project ios/Amplifier.xcodeproj -scheme Amplifier -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Amplifier-unsigned.xcarchive \
  archive CODE_SIGNING_ALLOWED=NO
  ditto -c -k --keepParent build/Amplifier-unsigned.xcarchive build/ios-artifacts/amplifier-ios-device-unsigned.zip
  python3 - <<'PY'
import json
import subprocess
from pathlib import Path
summary = json.loads(Path('build/ios-artifacts/test-summary.json').read_text())
if summary.get('failedTests', 0) or summary.get('testFailures') or summary.get('passedTests', 0) < 13:
    raise SystemExit('All 13 Xcode tests must pass')
info = {
    'version': '1.0.0',
    'bundle_id': 'com.srimi1.amplifier',
    'minimum_ios': '26.0',
    'simulator': 'iPhone 17',
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'device_archive_signed': False,
    'playback_scope': 'Imported local audio and video inside Amplifier only',
    'physical_device_testing': 'Pending',
}
Path('build/ios-artifacts/BUILDINFO.json').write_text(json.dumps(info, indent=2) + '\n')
PY
fi
