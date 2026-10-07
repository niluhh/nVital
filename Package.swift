// swift-tools-version:5.5
// Swift Package for NVitalCore, so other apps of the suite can depend on it
// without the Xcode project. The nVital app itself is built from project.yml.
import PackageDescription

let package = Package(
    name: "NVitalCore",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "NVitalCore", targets: ["NVitalCore"]),
    ],
    targets: [
        .target(
            name: "NVitalCore",
            path: "NVitalCore/Sources",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "NVitalCoreTests",
            dependencies: ["NVitalCore"],
            path: "NVitalCore/Tests"
        ),
    ]
)
