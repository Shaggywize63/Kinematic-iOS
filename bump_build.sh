#!/usr/bin/env bash
# Bumps the iOS app's CFBundleVersion (build number) so each Xcode
# build / archive ships with a monotonically greater number than the
# last one. Run before `xcodebuild archive` or invoke from a Run
# Script Build Phase if you want it on every Xcode build:
#
#   "${PROJECT_DIR}/../bump_build.sh"
#
# Strategy: derive the build number from the current git commit
# count on HEAD. That guarantees monotonic increases without needing
# state on disk + works the same locally and in CI.
#
# Marketing version (CFBundleShortVersionString, e.g. "1.0.0") stays
# untouched — bump that manually in Xcode project settings when you
# cut a new release.

set -euo pipefail

# Use the script's own location so it works no matter where invoked.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PBXPROJ="Kinematic/Kinematic.xcodeproj/project.pbxproj"
if [[ ! -f "$PBXPROJ" ]]; then
  echo "bump_build.sh: pbxproj not found at $PBXPROJ" >&2
  exit 1
fi

# Build number = total commit count on the current branch. Falls back
# to 1 when git isn't available.
if command -v git >/dev/null 2>&1; then
  BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
else
  BUILD_NUMBER=1
fi

# Replace every CURRENT_PROJECT_VERSION line (debug + release configs).
# sed -i has different syntax on macOS vs GNU; this handles both.
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "$PBXPROJ"
else
  sed -i "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "$PBXPROJ"
fi

echo "bump_build.sh: CFBundleVersion set to ${BUILD_NUMBER}"
