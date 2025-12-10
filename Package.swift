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
            targets: ["GRDBSQLCipher"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "GRDBSQLCipher",
            path: "BinaryArtifacts/GRDBSQLCipher.xcframework"
        )
    ]
)
