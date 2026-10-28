#!/usr/bin/env bash
set -euo pipefail

# Official release assets, pinned to the compiler used by this source tree.
version='0.10.14%2B7d59c7ec9'
sdk_sha='9226694de9ff978db1ecf820b7710c4224e84ec7a76b19a222d96f0cd4e31b6a'
core_sha='6f18b8fdea18f85e628a75e4a1bd3977c5a5c9c6a836fd8824192b0e6bd91b14'
: "${RUNNER_TEMP:?GitHub runner temporary directory is required}"
: "${GITHUB_ENV:?GitHub environment file is required}"
: "${GITHUB_PATH:?GitHub path file is required}"
export MOON_HOME="$RUNNER_TEMP/cif-moon-sdk"
test ! -e "$MOON_HOME/bin/moon"
mkdir -p "$MOON_HOME/lib"
sdk_archive="$RUNNER_TEMP/cif-moonbit-linux-x86_64.tar.gz"
core_archive="$RUNNER_TEMP/cif-core.tar.gz"
curl --fail --location --retry 3 --retry-all-errors \
  "https://cli.moonbitlang.com/binaries/$version/moonbit-linux-x86_64.tar.gz" -o "$sdk_archive"
curl --fail --location --retry 3 --retry-all-errors \
  "https://cli.moonbitlang.com/cores/core-$version.tar.gz" -o "$core_archive"
printf '%s  %s\n' "$sdk_sha" "$sdk_archive" | sha256sum --check --status
printf '%s  %s\n' "$core_sha" "$core_archive" | sha256sum --check --status
tar -xzf "$sdk_archive" -C "$MOON_HOME"
tar -xzf "$core_archive" -C "$MOON_HOME/lib"
export PATH="$MOON_HOME/bin:$PATH"
(
  cd "$MOON_HOME/lib/core"
  moon bundle --warn-list -a --target js
  moon bundle --warn-list -a --target wasm-gc
)
printf 'MOON_HOME=%s\n' "$MOON_HOME" >> "$GITHUB_ENV"
printf '%s\n' "$MOON_HOME/bin" >> "$GITHUB_PATH"
moon version --all
