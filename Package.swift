// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ImageLensStudio",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ImageLensStudio", targets: ["ImageLensMac"]),
        .library(name: "ImageLensCore", targets: ["ImageLensCore"]),
        .library(name: "ImageLensCanvas", targets: ["ImageLensCanvas"]),
        .library(name: "ImageLensProviders", targets: ["ImageLensProviders"]),
        .library(name: "ImageLensPersistence", targets: ["ImageLensPersistence"])
    ],
    targets: [
        .target(name: "ImageLensCore"),
        .target(
            name: "ImageLensCanvas",
            dependencies: ["ImageLensCore"]
        ),
        .target(
            name: "ImageLensProviders",
            dependencies: ["ImageLensCore"]
        ),
        .target(
            name: "ImageLensPersistence",
            dependencies: ["ImageLensCore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "ImageLensMac",
            dependencies: [
                "ImageLensCore",
                "ImageLensCanvas",
                "ImageLensProviders",
                "ImageLensPersistence"
            ]
        ),
        .testTarget(
            name: "ImageLensCoreTests",
            dependencies: ["ImageLensCore"]
        ),
        .testTarget(
            name: "ImageLensCanvasTests",
            dependencies: ["ImageLensCanvas"]
        ),
        .testTarget(
            name: "ImageLensProvidersTests",
            dependencies: ["ImageLensProviders", "ImageLensCore"]
        ),
        .testTarget(
            name: "ImageLensPersistenceTests",
            dependencies: ["ImageLensPersistence", "ImageLensCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ImageLensMacTests",
            dependencies: ["ImageLensMac"]
        )
    ]
)
