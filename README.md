# GRDBSQLCipher Swift Package

Swift Package wrapper that exposes the `GRDB.swift/SQLCipher` CocoaPods build as a binary XCFramework.

## Repository layout
- `Package.swift` – declares a single binary target `GRDBSQLCipher` that points to `BinaryArtifacts/GRDBSQLCipher.xcframework`.
- `BinaryArtifacts/` – drop the prebuilt XCFramework here (a `.gitkeep` placeholder is committed to keep the folder tracked).
- `Scripts/update_grdb.sh` – one-stop script that fetches/builds the `GRDB.swift/SQLCipher` CocoaPod and emits a fresh XCFramework.

## Updating the binary artifact
1. Make sure CocoaPods, Ruby (with the `xcodeproj` gem – it ships with CocoaPods), and Xcode command-line tools are installed.
2. Run `./Scripts/update_grdb.sh "~> 6.24"` (or pass any other CocoaPods-style version requirement). Set `VERBOSE=1` if you want to see the raw `pod`/`xcodebuild` logs, and `KEEP_BUILD_ROOT=1` if you want to inspect the temporary CocoaPods workspace afterwards.
3. The script will:
   - Spin up a throwaway CocoaPods workspace under `.build/grdb-sqlcipher`.
   - Install `GRDB.swift/SQLCipher` for iOS.
   - Build device + simulator frameworks and merge them into `BinaryArtifacts/GRDBSQLCipher.xcframework`.
4. Commit the updated XCFramework alongside `Package.swift` when distributing a new version.

The script currently targets iOS 12+ (matching the `platforms` declaration in `Package.swift`). Extend it with more SDK builds if you need tvOS/macOS/etc.

## Why this exists
`GRDB.swift/SQLCipher` ships only as a CocoaPod. This repository keeps our app fully Swift Package-based by wrapping the Pod-generated binary and codifying the update process in a script.
