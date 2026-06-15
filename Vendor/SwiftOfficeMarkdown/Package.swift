// swift-tools-version: 5.9
import PackageDescription

// Vendored, library-only manifest. The upstream package also has a CLI,
// codegen tool, tests, and an ISO-schema test oracle — none of which are
// vendored here (see UPMARKET_VENDOR.md). The app consumes only the library.
let package = Package(
    name: "SwiftOfficeMarkdown",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftOfficeMarkdown", targets: ["SwiftOfficeMarkdown"]),
    ],
    targets: [
        .target(name: "SwiftOfficeMarkdown"),
    ]
)
