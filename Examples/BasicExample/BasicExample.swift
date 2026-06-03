import Foundation
import Migratrom
import MigratromPostgresNIO
import PostgresNIO

@main
struct BasicExample {
    static func main() async throws {
        guard let urlString = ProcessInfo.processInfo.environment["DATABASE_URL"]
            ?? ProcessInfo.processInfo.environment["MIGRATROM_TEST_DATABASE_URL"],
            let url = URL(string: urlString)
        else {
            fputs(
                "Set DATABASE_URL or MIGRATROM_TEST_DATABASE_URL, e.g.\n"
                    + "  postgres://postgres:pw@localhost:5432/postgres\n",
                stderr
            )
            exit(1)
        }

        let config = try PostgresURL.makeClientConfiguration(from: url)
        let client = PostgresClient(configuration: config)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await client.run() }
            defer { group.cancelAll() }

            let schema = "public"
            let dialect = PostgresDialect()
            let m1 = Migration(
                id: 1,
                parentId: nil,
                operations: [
                    try createTable(
                        schema,
                        "users",
                        [
                            ColumnDef(name: "id", typeSql: "SERIAL"),
                            ColumnDef(name: "email", typeSql: "text"),
                        ],
                        primaryKey: PrimaryKey(columns: ["id"]),
                        dialect: dialect
                    ),
                    try addUnique(schema, "users", "users_email_key", ["email"], dialect: dialect),
                ]
            )
            let m2 = Migration(
                id: 2,
                parentId: 1,
                operations: [
                    try addColumn(
                        schema,
                        "users",
                        ColumnDef(name: "name", typeSql: "text", nullable: true),
                        dialect: dialect
                    ),
                ]
            )

            let options = ApplyOptions(dialect: dialect)
            let result = try await applyMigrations([m1, m2], on: client, options: options)
            print("Applied migration ids: \(result.applied)")
            if !result.skippedOps.isEmpty {
                print("Skipped operations: \(result.skippedOps)")
            }
        }
    }
}

enum PostgresURL {
    static func makeClientConfiguration(from url: URL) throws -> PostgresClient.Configuration {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "postgres" || scheme == "postgresql"
        else {
            throw URLError(.unsupportedURL)
        }
        guard let host = url.host, !host.isEmpty else {
            throw URLError(.badURL)
        }
        let port = url.port ?? 5432
        let username = url.user ?? "postgres"
        let password = url.password ?? ""
        let database = url.path.split(separator: "/").first.map(String.init) ?? "postgres"
        var config = PostgresClient.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
        config.options.minimumConnections = 1
        config.options.maximumConnections = 4
        return config
    }
}
