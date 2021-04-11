// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "opentelemetry-swift-jaeger",
    products: [
        .library(name: "OpenTelemetryJaeger", targets: ["OpenTelemetryJaeger"]),
    ],
    dependencies: [
        .package(url: "https://github.com/slashmo/opentelemetry-swift.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "OpenTelemetryJaeger", dependencies: [
            .product(name: "OpenTelemetry", package: "opentelemetry-swift"),
        ]),
        .testTarget(name: "OpenTelemetryJaegerTests", dependencies: [
            .target(name: "OpenTelemetryJaeger"),
        ]),
    ]
)
