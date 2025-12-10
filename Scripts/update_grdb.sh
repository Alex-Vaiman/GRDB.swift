#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/update_grdb.sh [COCOAPODS_VERSION_REQUIREMENT]
# Example: ./Scripts/update_grdb.sh "~> 6.27"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_DIR="$ROOT_DIR/BinaryArtifacts"
OUTPUT_PATH="$ARTIFACTS_DIR/GRDBSQLCipher.xcframework"
BUILD_ROOT="$ROOT_DIR/.build/grdb-sqlcipher"
BUILD_PRODUCTS_DIR="$BUILD_ROOT/BuildProducts"
OBJROOT="$BUILD_ROOT/obj"
SYMROOT="$BUILD_ROOT/sym"
POD_REQUIREMENT="${1:-"~> 6.24"}"
IOS_DEPLOYMENT_TARGET="12.0"
VERBOSE="${VERBOSE:-0}"

log() {
  printf '[update_grdb] %s\n' "$*"
}

run_cmd() {
  if [[ "$VERBOSE" != "0" ]]; then
    "$@"
  else
    "$@" >/dev/null
  fi
}

command -v pod >/dev/null || {
  echo "error: CocoaPods (pod) is not installed" >&2
  exit 1
}
command -v xcodebuild >/dev/null || {
  echo "error: xcodebuild is not available (install Xcode command line tools)" >&2
  exit 1
}
command -v ruby >/dev/null || {
  echo "error: ruby is required to bootstrap a throwaway host project" >&2
  exit 1
}

KEEP_BUILD_ROOT="${KEEP_BUILD_ROOT:-0}"

cleanup() {
  if [[ "$KEEP_BUILD_ROOT" == "0" ]]; then
    rm -rf "$BUILD_ROOT"
  else
    log "KEEP_BUILD_ROOT=1 -> preserving $BUILD_ROOT"
  fi
}
trap cleanup EXIT

mkdir -p "$BUILD_ROOT"

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

pods_project="$BUILD_ROOT/Pods/Pods.xcodeproj"
if [[ ! -d "$pods_project" ]]; then
  echo "error: Failed to generate Pods project" >&2
  exit 1
fi

available_target=$(xcodebuild -list -project "$pods_project" 2>/dev/null | awk '/Targets:/ {flag=1; next} /Build Configurations:/ {flag=0} flag {gsub(/^ +| +$/,"", $0); if ($0 ~ /GRDB/) {print $0; exit}}')
if [[ -z "$available_target" ]]; then
  echo "error: Could not find a target that looks like GRDB inside Pods project" >&2
  exit 1
fi

echo "Using CocoaPods target: $available_target"

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

get_product_name() {
  xcodebuild -project "$pods_project" -target "$available_target" \
    -configuration Release -sdk "$1" -showBuildSettings 2>/dev/null | \
    trimmed_build_setting "PRODUCT_NAME"
}

PRODUCT_NAME=$(get_product_name iphoneos)
if [[ -z "$PRODUCT_NAME" ]]; then
  echo "error: Unable to determine PRODUCT_NAME from xcodebuild" >&2
  exit 1
fi

echo "Detected product: $PRODUCT_NAME"

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

DEVICE_BUILD_DIR=$(get_target_build_dir iphoneos)
SIMULATOR_BUILD_DIR=$(get_target_build_dir iphonesimulator)

FRAMEWORK_DEVICE="$DEVICE_BUILD_DIR/$PRODUCT_NAME.framework"
FRAMEWORK_SIMULATOR="$SIMULATOR_BUILD_DIR/$PRODUCT_NAME.framework"

if [[ ! -d "$FRAMEWORK_DEVICE" || ! -d "$FRAMEWORK_SIMULATOR" ]]; then
  echo "error: Expected framework products were not found" >&2
  exit 1
fi

log "Device framework: $FRAMEWORK_DEVICE"
log "Simulator framework: $FRAMEWORK_SIMULATOR"

rm -rf "$OUTPUT_PATH"
mkdir -p "$ARTIFACTS_DIR"

log "Assembling XCFramework ..."
run_cmd xcodebuild -create-xcframework \
  -framework "$FRAMEWORK_DEVICE" \
  -framework "$FRAMEWORK_SIMULATOR" \
  -output "$OUTPUT_PATH"

log "Done. XCFramework available at $OUTPUT_PATH"
