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
    targets: [
        .target(
          name: "abseil",
          path: ".",
          exclude: [
            // main functions
            // tests
            "absl/random/benchmarks.cc",
            // .inc files
            "absl/debugging/internal/stacktrace_win32-inl.inc",
            "absl/debugging/internal/stacktrace_riscv-inl.inc",
            "absl/debugging/internal/stacktrace_generic-inl.inc",
            "absl/debugging/internal/stacktrace_unimplemented-inl.inc",
            "absl/debugging/internal/stacktrace_x86-inl.inc",
            "absl/debugging/internal/stacktrace_arm-inl.inc",
            "absl/debugging/internal/stacktrace_aarch64-inl.inc",
            "absl/debugging/internal/stacktrace_powerpc-inl.inc",
            "absl/debugging/internal/stacktrace_emscripten-inl.inc",
            "absl/debugging/symbolize_win32.inc",
            "absl/debugging/symbolize_emscripten.inc",
            "absl/debugging/symbolize_unimplemented.inc",
            "absl/debugging/symbolize_elf.inc",
            "absl/debugging/symbolize_darwin.inc",
            "absl/time/internal/get_current_time_chrono.inc",
            "absl/time/internal/get_current_time_posix.inc",
            "absl/numeric/int128_have_intrinsic.inc",
            "absl/numeric/int128_no_intrinsic.inc",
            "absl/base/internal/spinlock_akaros.inc",
            "absl/base/internal/spinlock_linux.inc",
            "absl/base/internal/spinlock_posix.inc",
            "absl/base/internal/spinlock_win32.inc",
            // other files
            "absl/flags/flag_benchmark.lds",
            "absl/abseil.podspec.gen.py",
          ],
          sources: [
            "absl/"
          ],
          publicHeadersPath: ".",
          cSettings: [
            .headerSearchPath("./"),
          ],
          linkerSettings: [
            .linkedFramework("CoreFoundation"),
          ]
        ),
        // C++ target built from the upstream sources via SwiftPM.
        // Tests and CMake scaffolding are intentionally excluded.
        .target(
            name: "InkStrokeModeler",
            dependencies: [
                "abseil"
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
