#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/update_grdb.sh [COCOAPODS_VERSION_REQUIREMENT]
# Example: ./Scripts/update_grdb.sh "~> 6.27"
# If no argument is provided, script defaults to the latest release from CocoaPods trunk (when available).
# It skips building if the resolved version matches the bundled artifact version.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_DIR="$ROOT_DIR/BinaryArtifacts"
OUTPUT_PATH="$ARTIFACTS_DIR/GRDBSQLCipher.xcframework"
SQLCIPHER_OUTPUT_PATH="$ARTIFACTS_DIR/SQLCipher.xcframework"
ARTIFACT_VERSION_PATH="$ARTIFACTS_DIR/GRDBSQLCipher.version"

BUILD_ROOT="$ROOT_DIR/.build/grdb-sqlcipher"
BUILD_PRODUCTS_DIR="$BUILD_ROOT/BuildProducts"
OBJROOT="$BUILD_ROOT/obj"
SYMROOT="$BUILD_ROOT/sym"

DEFAULT_POD_REQUIREMENT="~> 6.24"
POD_REQUIREMENT="${1:-""}"
IOS_DEPLOYMENT_TARGET="12.0"
VERBOSE="${VERBOSE:-0}"
KEEP_BUILD_ROOT="${KEEP_BUILD_ROOT:-0}"

CURRENT_ARTIFACT_VERSION=""
LATEST_REMOTE_VERSION=""

log() { printf '[update_grdb] %s\n' "$*"; }

run_cmd() {
  if [[ "$VERBOSE" != "0" ]]; then
    "$@"
  else
    "$@" >/dev/null
  fi
}

need_cmd() { command -v "$1" >/dev/null || { echo "error: $1 is required" >&2; exit 1; }; }

need_cmd pod
need_cmd xcodebuild
need_cmd ruby
need_cmd sed
need_cmd awk
need_cmd head
need_cmd find
need_cmd sort
need_cmd tail
need_cmd nm

cleanup() {
  if [[ "$KEEP_BUILD_ROOT" == "0" ]]; then
    rm -rf "$BUILD_ROOT"
  else
    log "KEEP_BUILD_ROOT=1 -> preserving $BUILD_ROOT"
  fi
}
trap cleanup EXIT

mkdir -p "$BUILD_ROOT" "$ARTIFACTS_DIR"

read_current_artifact_version() {
  if [[ -f "$ARTIFACT_VERSION_PATH" ]]; then
    local recorded_version
    recorded_version="$(head -n 1 "$ARTIFACT_VERSION_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -n "$recorded_version" ]]; then
      echo "$recorded_version"
      return
    fi
  fi

  if [[ ! -d "$OUTPUT_PATH" ]]; then
    return
  fi

  local info_plist
  info_plist="$(find "$OUTPUT_PATH" -path "*.framework/Info.plist" -print -quit 2>/dev/null || true)"
  if [[ -z "$info_plist" ]]; then
    return
  fi

  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist" 2>/dev/null || true
}

print_current_artifact_version() {
  CURRENT_ARTIFACT_VERSION="$(read_current_artifact_version || true)"
  if [[ -n "$CURRENT_ARTIFACT_VERSION" ]]; then
    log "Current bundled GRDB.swift version: $CURRENT_ARTIFACT_VERSION"
  else
    log "No existing GRDBSQLCipher.xcframework version detected"
  fi
}

fetch_latest_remote_version() {
  pod trunk info "GRDB.swift" 2>/dev/null | \
    sed -n 's/^[[:space:]]*-[[:space:]]\([0-9][0-9.]*\).*/\1/p' | \
    LC_ALL=C sort -V | tail -n 1
}

print_latest_remote_version() {
  LATEST_REMOTE_VERSION="$(fetch_latest_remote_version || true)"
  if [[ -n "$LATEST_REMOTE_VERSION" ]]; then
    log "Latest GRDB.swift release per CocoaPods trunk: $LATEST_REMOTE_VERSION"
  else
    log "Unable to determine latest GRDB.swift release (pod trunk info failed?)"
  fi
}

write_artifact_version_file() {
  local version="$1"
  if [[ -z "$version" ]]; then
    version="$(read_current_artifact_version || true)"
  fi
  if [[ -z "$version" ]]; then
    rm -f "$ARTIFACT_VERSION_PATH"
    log "Artifact version file removed (no version detected)"
    return
  fi
  printf '%s\n' "$version" >"$ARTIFACT_VERSION_PATH"
  log "Recorded artifact version $version at $ARTIFACT_VERSION_PATH"
}

read_resolved_pod_version() {
  local lock_path="$BUILD_ROOT/Podfile.lock"
  if [[ ! -f "$lock_path" ]]; then
    return
  fi
  awk -F'[()]' '/GRDB\.swift\/SQLCipher/ {if (NF >= 2) {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}}' "$lock_path"
}

is_valid_xcframework() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  find "$path" -maxdepth 3 -type d -name "*.framework" -print -quit 2>/dev/null | grep -q "."
}

print_current_artifact_version
print_latest_remote_version

if [[ -z "$POD_REQUIREMENT" ]]; then
  if [[ -n "$LATEST_REMOTE_VERSION" ]]; then
    POD_REQUIREMENT="$LATEST_REMOTE_VERSION"
    log "No version requirement provided -> defaulting to latest release $POD_REQUIREMENT"
  else
    POD_REQUIREMENT="$DEFAULT_POD_REQUIREMENT"
    log "No version requirement provided and latest release unavailable -> falling back to $POD_REQUIREMENT"
  fi
else
  log "Using user-supplied version requirement: $POD_REQUIREMENT"
fi

log "Generating Podfile for GRDB.swift/SQLCipher ($POD_REQUIREMENT)"
cat >"$BUILD_ROOT/Podfile" <<PODFILE
platform :ios, '$IOS_DEPLOYMENT_TARGET'
use_frameworks!
inhibit_all_warnings!

install! 'cocoapods', :generate_multiple_pod_projects => false

target 'GRDBSQLCipherHost' do
  project 'GRDBSQLCipherHost.xcodeproj'
  pod 'GRDB.swift/SQLCipher', '$POD_REQUIREMENT'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '$IOS_DEPLOYMENT_TARGET'
    end
  end
end
PODFILE

BUILD_DIR="$BUILD_ROOT" DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" ruby <<'RUBY'
require 'fileutils'
require 'xcodeproj'

build_dir = ENV.fetch('BUILD_DIR')
project_path = File.join(build_dir, 'GRDBSQLCipherHost.xcodeproj')
FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)
project.new_target(:application, 'GRDBSQLCipherHost', :ios, ENV.fetch('DEPLOYMENT_TARGET'))
project.save
RUBY

log "Running pod install"
pushd "$BUILD_ROOT" >/dev/null
run_cmd pod install
popd >/dev/null

resolved_version="$(read_resolved_pod_version || true)"
if [[ -n "$resolved_version" ]]; then
  log "Resolved GRDB.swift/SQLCipher version: $resolved_version"
else
  log "Could not determine resolved GRDB.swift/SQLCipher version from Podfile.lock"
fi

if [[ -n "$CURRENT_ARTIFACT_VERSION" && -n "$resolved_version" ]] && is_valid_xcframework "$OUTPUT_PATH"; then
  if [[ "$CURRENT_ARTIFACT_VERSION" == "$resolved_version" ]]; then
    log "Resolved version matches existing artifact ($resolved_version); skipping build."
    exit 0
  fi
fi

pods_project="$BUILD_ROOT/Pods/Pods.xcodeproj"
if [[ ! -d "$pods_project" ]]; then
  echo "error: Failed to generate Pods project" >&2
  exit 1
fi

available_target="$(xcodebuild -list -project "$pods_project" 2>/dev/null | awk '
  /Targets:/ {flag=1; next}
  /Build Configurations:/ {flag=0}
  flag {
    gsub(/^ +| +$/,"", $0)
    if ($0 == "GRDB.swift") { print $0; exit }
    if ($0 ~ /GRDB/) { cand=$0 }
  }
  END { if (cand) print cand }
')"

if [[ -z "$available_target" ]]; then
  echo "error: Could not find a target that looks like GRDB inside Pods project" >&2
  exit 1
fi

log "Using CocoaPods GRDB target: $available_target"

get_product_name() {
  xcodebuild -project "$pods_project" -target "$available_target" \
    -configuration Release -sdk "$1" -showBuildSettings 2>/dev/null | \
    awk -F'= ' '
      {
        k=$1
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
        if (k == "PRODUCT_NAME") {
          v=$2
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          print v
          exit
        }
      }'
}

PRODUCT_NAME="$(get_product_name iphoneos)"
if [[ -z "$PRODUCT_NAME" ]]; then
  echo "error: Unable to determine PRODUCT_NAME from xcodebuild" >&2
  exit 1
fi

log "Detected GRDB product: $PRODUCT_NAME"

XCODEBUILD_COMMON_ARGS=(
  -project "$pods_project"
  -target "$available_target"
  -configuration Release
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES
  SKIP_INSTALL=NO
  ONLY_ACTIVE_ARCH=NO
  BUILD_DIR="$BUILD_PRODUCTS_DIR"
  OBJROOT="$OBJROOT"
  SYMROOT="$SYMROOT"
)

build_for_sdk() {
  local sdk="$1"
  log "Building GRDB.swift for $sdk ..."
  run_cmd xcodebuild "${XCODEBUILD_COMMON_ARGS[@]}" -sdk "$sdk"
}

trimmed_build_setting() {
  local setting="$1"
  awk -F'= ' -v key="$setting" '
    {
      k=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k == key) {
        v=$2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }'
}

get_target_build_dir() {
  local sdk="$1"
  xcodebuild "${XCODEBUILD_COMMON_ARGS[@]}" -sdk "$sdk" -showBuildSettings 2>/dev/null | \
    trimmed_build_setting "TARGET_BUILD_DIR"
}

log "Cleaning previous build artifacts"
rm -rf "$BUILD_PRODUCTS_DIR" "$OBJROOT" "$SYMROOT"
mkdir -p "$BUILD_PRODUCTS_DIR"

build_for_sdk iphoneos
build_for_sdk iphonesimulator

DEVICE_BUILD_DIR="$(get_target_build_dir iphoneos)"
SIMULATOR_BUILD_DIR="$(get_target_build_dir iphonesimulator)"

FRAMEWORK_DEVICE="$DEVICE_BUILD_DIR/$PRODUCT_NAME.framework"
FRAMEWORK_SIMULATOR="$SIMULATOR_BUILD_DIR/$PRODUCT_NAME.framework"

# Keep the known-working CocoaPods output paths for SQLCipher (as in the original script)
SQLCIPHER_FRAMEWORK_DEVICE="$BUILD_PRODUCTS_DIR/Release-iphoneos/SQLCipher/SQLCipher.framework"
SQLCIPHER_FRAMEWORK_SIMULATOR="$BUILD_PRODUCTS_DIR/Release-iphonesimulator/SQLCipher/SQLCipher.framework"

if [[ "$VERBOSE" != "0" ]]; then
  log "Debug: listing SQLCipher build folders"
  ls -la "$BUILD_PRODUCTS_DIR/Release-iphoneos/SQLCipher" || true
  ls -la "$BUILD_PRODUCTS_DIR/Release-iphonesimulator/SQLCipher" || true
fi

if [[ ! -d "$FRAMEWORK_DEVICE" || ! -d "$FRAMEWORK_SIMULATOR" ]]; then
  echo "error: Expected GRDB framework products were not found" >&2
  exit 1
fi

if [[ ! -d "$SQLCIPHER_FRAMEWORK_DEVICE" || ! -d "$SQLCIPHER_FRAMEWORK_SIMULATOR" ]]; then
  echo "error: Expected SQLCipher framework products were not found" >&2
  exit 1
fi

log "Device framework: $FRAMEWORK_DEVICE"
log "Simulator framework: $FRAMEWORK_SIMULATOR"
log "Device SQLCipher framework: $SQLCIPHER_FRAMEWORK_DEVICE"
log "Simulator SQLCipher framework: $SQLCIPHER_FRAMEWORK_SIMULATOR"

rm -rf "$OUTPUT_PATH" "$SQLCIPHER_OUTPUT_PATH"
mkdir -p "$ARTIFACTS_DIR"

log "Assembling GRDB XCFramework ..."
run_cmd xcodebuild -create-xcframework \
  -framework "$FRAMEWORK_DEVICE" \
  -framework "$FRAMEWORK_SIMULATOR" \
  -output "$OUTPUT_PATH"

log "Assembling SQLCipher XCFramework ..."
run_cmd xcodebuild -create-xcframework \
  -framework "$SQLCIPHER_FRAMEWORK_DEVICE" \
  -framework "$SQLCIPHER_FRAMEWORK_SIMULATOR" \
  -output "$SQLCIPHER_OUTPUT_PATH"

[[ -d "$OUTPUT_PATH" ]] || { echo "error: GRDBSQLCipher.xcframework not created at $OUTPUT_PATH" >&2; exit 1; }
[[ -d "$SQLCIPHER_OUTPUT_PATH" ]] || { echo "error: SQLCipher.xcframework not created at $SQLCIPHER_OUTPUT_PATH" >&2; exit 1; }

# Minimal verification: sqlcipher should export sqlite3_key
SQL_BIN="$SQLCIPHER_OUTPUT_PATH/ios-arm64/SQLCipher.framework/SQLCipher"
if [[ -f "$SQL_BIN" ]]; then
  if ! nm -gU "$SQL_BIN" | grep -q "sqlite3_key"; then
    echo "error: SQLCipher binary does not export sqlite3_key (codec likely missing / wrong binary)" >&2
    exit 1
  fi
else
  log "Warning: SQLCipher binary not found at expected path; skipping nm verification"
fi

write_artifact_version_file "$resolved_version"

log "Done. XCFrameworks available at:"
log "  $OUTPUT_PATH"
log "  $SQLCIPHER_OUTPUT_PATH"
