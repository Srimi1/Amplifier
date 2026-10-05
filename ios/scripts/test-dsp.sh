#!/usr/bin/env bash
set -euo pipefail
ios_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
cc -std=c11 -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I "$ios_root/Amplifier/Audio" \
  "$ios_root/Amplifier/Audio/GainDSP.c" "$ios_root/Tests/GainDSPPortableTests.c" \
  -lm -pthread -o "$test_dir/gain-dsp-tests"
"$test_dir/gain-dsp-tests"
