// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GRDB.swift",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "GRDBSQLCipher",
            targets: ["GRDBSQLCipher", "SQLCipher"]
        ),
        .library(
            name: "SQLCipher",  // ← זה חסר אצלך!
            targets: ["SQLCipher"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "GRDBSQLCipher",
            path: "BinaryArtifacts/GRDBSQLCipher.xcframework"
        ),
        .binaryTarget(
            name: "SQLCipher",
            path: "BinaryArtifacts/SQLCipher.xcframework"
        )
    ]
)