// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "itsyweb",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "itsyweb",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Info.plist"])
            ]
        )
    ]
)
