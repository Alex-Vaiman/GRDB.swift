# GRDB + SQLCipher Swift Package (XCFramework)

Swift Package wrapper that exposes the **CocoaPods-built** `GRDB.swift/SQLCipher` integration as **SPM-ready binary XCFrameworks**.

Upstream project: https://github.com/groue/GRDB.swift  
This repository is a fork, focused on packaging and automation for Swift Package Manager consumption.

## What you get
- Two binary products:
  - `GRDBSQLCipher` → `BinaryArtifacts/GRDBSQLCipher.xcframework`
  - `SQLCipher` → `BinaryArtifacts/SQLCipher.xcframework`
- A one-stop update script that builds fresh artifacts from the `GRDB.swift/SQLCipher` CocoaPod.

## Repository layout
- `Package.swift` – declares the binary products/targets.
- `BinaryArtifacts/` – contains the prebuilt XCFrameworks (a `.gitkeep` placeholder can be committed to keep the folder tracked).
- `Scripts/update_grdb.sh` – fetches/builds the `GRDB.swift/SQLCipher` CocoaPod and emits fresh XCFrameworks.

## Updating the binary artifacts
1. Make sure CocoaPods, Ruby, and Xcode command-line tools are installed.
2. Run:
   - `./Scripts/update_grdb.sh` (defaults to the latest GRDB.swift release from CocoaPods trunk when available), or
   - `./Scripts/update_grdb.sh "~> 6.24"` (or any CocoaPods-style version requirement)

   Optional:
   - `VERBOSE=1` to see raw `pod` / `xcodebuild` logs
   - `KEEP_BUILD_ROOT=1` to keep the temporary CocoaPods workspace under `.build/grdb-sqlcipher`

3. The script will:
   - Spin up a throwaway CocoaPods workspace under `.build/grdb-sqlcipher`
   - Install `GRDB.swift/SQLCipher` for iOS
   - Build device + simulator frameworks
   - Emit:
     - `BinaryArtifacts/GRDBSQLCipher.xcframework`
     - `BinaryArtifacts/SQLCipher.xcframework`
   - Write `BinaryArtifacts/GRDBSQLCipher.version` with the resolved pod version
4. Commit the updated XCFrameworks alongside `Package.swift` and tag a new version.

## Platform support
The script currently targets iOS 12+ (matching the `platforms` declaration in `Package.swift`). Extend it with more SDK builds if you need tvOS/macOS/etc.

## Why this exists
`GRDB.swift/SQLCipher` ships as a CocoaPod. This repository keeps apps fully Swift Package–based by wrapping the pod-built binaries and codifying the update process in a single script.

---

If you find this useful, feel free to use it — and if you spot improvements, PRs and issues are welcome.
