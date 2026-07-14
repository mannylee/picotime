// swift-tools-version:5.9
import PackageDescription

// This package exists to unit-test and measure coverage of Picotime's pure,
// non-UI logic. The menu bar .app itself is built by build.sh (swiftc + lipo,
// Command Line Tools only) — its entry point is App/main.swift, outside Sources/
// so SwiftPM ignores it; build.sh compiles the PicotimeCore sources into that
// same module.
//
//   PicotimeCore      — Foundation-only date/calendar logic (no AppKit). Tested.
//   PicotimeCoreTests — a plain executable that exercises PicotimeCore.
//
// Tests are an *executable*, not an XCTest bundle: `swift test`'s runner needs
// Xcode's `xctest` tool, and Picotime is deliberately no-Xcode. Run them with
// ./run-tests.sh (`swift run PicotimeCoreTests`); ./coverage.sh builds them
// instrumented and reports via llvm-cov (both shipped with the CLT).
let package = Package(
    name: "Picotime",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PicotimeCore"),
        .executableTarget(
            name: "PicotimeCoreTests",
            dependencies: ["PicotimeCore"]
        ),
    ]
)
