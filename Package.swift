// swift-tools-version:5.10
//
// Global — an animated 3D globe desktop wallpaper for two people.
//
// SwiftPM builds a bare executable; `scripts/build-app.sh` wraps it in a
// signed `Global.app` bundle with Info.plist and resources.
//
// Resources are deliberately NOT declared as SwiftPM resources: the generated
// `Bundle.module` accessor expects a sibling bundle at the .app root, which
// breaks code signing. `ResourceLocator` finds them instead (app bundle when
// packaged, repo `Resources/` folder when run via `swift run`).

import PackageDescription

let package = Package(
    name: "Global",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Global",
            path: "Sources/Global",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("MetalKit"),
                .linkedFramework("SceneKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "GlobalTests",
            dependencies: ["Global"],
            path: "Tests/GlobalTests"
        ),
    ]
)
