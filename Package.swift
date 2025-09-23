// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-ink-stroke-modeler",
    platforms: [
        .macOS(.v12),
        .iOS(.v14)
    ],
    products: [
        // Low-level C++ product. This compiles the upstream sources.
        .library(name: "InkStrokeModeler", targets: ["InkStrokeModeler"]) ,
        // Swift-friendly wrapper product
        .library(name: "InkStrokeModelerSwift", targets: ["InkStrokeModelerSwift"]) 
        // Swift wrapper target will be added after C++ compiles successfully.
    ],
    dependencies: [
        // Use Firebase's SwiftPM distribution of Abseil for iOS/macOS.
        .package(url: "https://github.com/firebase/abseil-cpp-SwiftPM.git", branch: "main")
    ],
    targets: [
        // C++ target built from the upstream sources via SwiftPM.
        // Tests and CMake scaffolding are intentionally excluded.
        .target(
            name: "InkStrokeModeler",
            dependencies: [
                // The abseil-cpp-SwiftPM package exports products for Abseil headers/libs.
                // The exact product name can differ; "abseil" is commonly used. If build
                // fails due to product name, we will adjust after fetching the package.
                .product(name: "abseil", package: "abseil-cpp-swiftpm")
            ],
            path: "ink-stroke-modeler/ink_stroke_modeler",
            sources: [
                // Top-level
                "params.cc",
                "types.cc",
                "stroke_modeler.cc",
                // internal
                "internal/internal_types.cc",
                "internal/loop_contraction_mitigation_modeler.cc",
                "internal/position_modeler.cc",
                "internal/stylus_state_modeler.cc",
                "internal/utils.cc",
                "internal/wobble_smoother.cc",
                // prediction
                "internal/prediction/kalman_filter/axis_predictor.cc",
                "internal/prediction/kalman_filter/kalman_filter.cc",
                "internal/prediction/kalman_predictor.cc",
                "internal/prediction/stroke_end_predictor.cc",
            ],
            publicHeadersPath: ".", // Treat headers under target path as public for C++ interop
            cxxSettings: [
                // Make upstream headers resolvable (e.g. "ink_stroke_modeler/types.h").
                .headerSearchPath(".."),
                .headerSearchPath("."),
                .unsafeFlags(["-std=c++20"])
            ],
            linkerSettings: []
        ),
        // C FFI target bridging Swift <-> C++
        .target(
            name: "InkStrokeModelerFFI",
            dependencies: ["InkStrokeModeler"],
            path: "Sources/InkStrokeModelerFFI",
            publicHeadersPath: "include",
            cSettings: [
                .define("SWIFT_PACKAGE"),
                .unsafeFlags(["-std=c++20"]), // for Objective-C++ compilation of .mm
                .headerSearchPath("../../ink-stroke-modeler")
            ]
        ),
        // Swift wrapper target using the FFI
        .target(
            name: "InkStrokeModelerSwift",
            dependencies: ["InkStrokeModelerFFI"],
            path: "Sources/InkStrokeModelerSwift",
            swiftSettings: [
                // C++ interop is available by default on modern toolchains; keep target Swift-only for now.
            ]
        )
    ],
    cxxLanguageStandard: .cxx20
)
