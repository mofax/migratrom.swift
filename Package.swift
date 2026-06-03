// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "migratrom",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "Migratrom", targets: ["Migratrom"]),
        .library(name: "MigratromPostgresNIO", targets: ["MigratromPostgresNIO"]),
        .library(name: "MigratromSQLite", targets: ["MigratromSQLite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/nike-inc/SQift", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "Migratrom",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "MigratromPostgresNIO",
            dependencies: [
                "Migratrom",
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
        .target(
            name: "MigratromSQLite",
            dependencies: [
                "Migratrom",
                .product(name: "SQift", package: "SQift"),
            ]
        ),
        .testTarget(
            name: "MigratromTests",
            dependencies: [
                "Migratrom",
                "MigratromSQLite",
                .product(name: "SQift", package: "SQift"),
            ]
        ),
        .testTarget(
            name: "MigratromPostgresNIOTests",
            dependencies: ["MigratromPostgresNIO"]
        ),
        .executableTarget(
            name: "BasicExample",
            dependencies: ["MigratromPostgresNIO"],
            path: "Examples/BasicExample"
        ),
    ],
    swiftLanguageModes: [.v6]
)
