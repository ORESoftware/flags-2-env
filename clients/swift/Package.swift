// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Flags2Env",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "Flags2Env", targets: ["Flags2Env"])
    ],
    targets: [
        .target(
            name: "Flags2Env",
            path: ".",
            exclude: ["Dockerfile", "test.swift", "publish.sh"],
            sources: ["lib.swift"]
        )
    ]
)
