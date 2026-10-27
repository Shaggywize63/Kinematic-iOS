#!/usr/bin/env bash
# bump_version.sh — bump or check the iOS app's MARKETING_VERSION
# (CFBundleShortVersionString, e.g. "1.3.0") across the app target AND the
# KinematicWidget extension IN LOCKSTEP.
#
# Why this exists: the marketing version used to be edited by hand in Xcode,
# which kept going wrong —
#   * App Store "pre-release train '<v>' is closed" / "must contain a higher
#     version than the previously approved version" rejections, because the
#     archived version wasn't bumped past the last upload; and
#   * "the embedded extension must contain the same CFBundleShortVersionString
#     as the host app" upload failures, because the app and widget versions
#     drifted apart.
# This makes the bump one safe command, and gives CI a guard (`check`) against
# the app/widget drift.
#
# Usage:
#   ./bump_version.sh current      # print the current app marketing version
#   ./bump_version.sh check        # verify app + widget are in lockstep; exit 1 on drift (for CI)
#   ./bump_version.sh patch        # 1.3.0 -> 1.3.1
#   ./bump_version.sh minor        # 1.3.0 -> 1.4.0
#   ./bump_version.sh major        # 1.3.0 -> 2.0.0
#   ./bump_version.sh set 1.3.4    # set an explicit version (warns if not higher)
#
# The unit-test target (MARKETING_VERSION = 1.0) is left untouched. The build
# number (CFBundleVersion / CURRENT_PROJECT_VERSION) is bump_build.sh's job.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
PBXPROJ="Kinematic/Kinematic.xcodeproj/project.pbxproj"
[[ -f "$PBXPROJ" ]] || { echo "bump_version.sh: pbxproj not found at $PBXPROJ" >&2; exit 1; }

mv_values()  { grep -oE "MARKETING_VERSION = [^;]+;" "$PBXPROJ" | sed -E 's/MARKETING_VERSION = (.*);/\1/'; }
cpv_values() { grep -oE "CURRENT_PROJECT_VERSION = [^;]+;" "$PBXPROJ" | sed -E 's/CURRENT_PROJECT_VERSION = (.*);/\1/'; }

# The shippable (app + widget) marketing version is the most common value: the
# four app/widget configs outnumber the two unit-test configs. `check` proves
# the shippable configs actually agree.
app_version() { mv_values | sort | uniq -c | sort -rn | head -1 | awk '{print $2}'; }

is_semver() { [[ "$1" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; }

# Compare two dotted versions. Echoes -1 / 0 / 1 for a<b / a==b / a>b.
vercmp() {
  local IFS=.; local -a A=($1) B=($2); local i x y
  for i in 0 1 2; do
    x=${A[i]:-0}; y=${B[i]:-0}
    if (( x < y )); then echo -1; return; fi
    if (( x > y )); then echo 1;  return; fi
  done
  echo 0
}

# check: app + widget must share ONE marketing version and ONE build number.
# A drift (app != widget) surfaces as >2 distinct values (the shippable value
# plus the test target's) — exactly the state that breaks a TestFlight upload.
do_check() {
  local mv_distinct cpv_distinct appver ok=1
  mv_distinct=$(mv_values  | sort -u | wc -l | tr -d ' ')
  cpv_distinct=$(cpv_values | sort -u | wc -l | tr -d ' ')
  appver=$(app_version)
  if (( mv_distinct > 2 )); then
    echo "bump_version.sh: FAIL — MARKETING_VERSION has drifted across targets:" >&2
    mv_values | sort | uniq -c | sed 's/^/    /' >&2
    ok=0
  fi
  if (( cpv_distinct > 2 )); then
    echo "bump_version.sh: FAIL — CURRENT_PROJECT_VERSION has drifted across targets:" >&2
    cpv_values | sort | uniq -c | sed 's/^/    /' >&2
    ok=0
  fi
  if ! is_semver "$appver"; then
    echo "bump_version.sh: FAIL — app marketing version '$appver' is not X.Y or X.Y.Z" >&2
    ok=0
  fi
  if (( ok )); then
    echo "bump_version.sh: OK — app + widget in lockstep at $appver"
  else
    exit 1
  fi
}

sed_inplace() { if [[ "$(uname)" == "Darwin" ]]; then sed -i '' "$@"; else sed -i "$@"; fi; }

set_version() {
  local new="$1" cur; cur=$(app_version)
  is_semver "$new" || { echo "bump_version.sh: '$new' is not a valid version (X.Y or X.Y.Z)" >&2; exit 1; }
  if [[ "$(vercmp "$new" "$cur")" != "1" ]]; then
    echo "bump_version.sh: WARNING — $new is not greater than the current $cur; App Store requires a higher version than the last upload." >&2
  fi
  # Replace only the shippable value; the test target has a different value and
  # is left as-is.
  sed_inplace "s/MARKETING_VERSION = ${cur};/MARKETING_VERSION = ${new};/g" "$PBXPROJ"
  echo "bump_version.sh: MARKETING_VERSION ${cur} -> ${new} (app + widget)"
  echo "bump_version.sh: remember to bump the build number too (bump_build.sh / CI)."
}

bump_part() {
  local part="$1" cur; cur=$(app_version)
  is_semver "$cur" || { echo "bump_version.sh: current version '$cur' is not semver; set one explicitly with 'set X.Y.Z'" >&2; exit 1; }
  local IFS=.; local -a V=($cur); local maj=${V[0]:-0} min=${V[1]:-0} pat=${V[2]:-0}
  case "$part" in
    major) maj=$((maj+1)); min=0; pat=0;;
    minor) min=$((min+1)); pat=0;;
    patch) pat=$((pat+1));;
  esac
  set_version "${maj}.${min}.${pat}"
}

case "${1:-}" in
  current)           app_version;;
  check)             do_check;;
  patch|minor|major) bump_part "$1";;
  set)               [[ -n "${2:-}" ]] || { echo "usage: bump_version.sh set X.Y.Z" >&2; exit 1; }; set_version "$2";;
  *) echo "usage: bump_version.sh {current|check|patch|minor|major|set X.Y.Z}" >&2; exit 1;;
esac
