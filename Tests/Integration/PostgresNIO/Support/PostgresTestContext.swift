import Foundation
import Logging
import Migratrom
import MigratromPostgresNIO
import PostgresNIO

enum PostgresTestHarness {
    static var isAvailable: Bool {
        ProcessInfo.processInfo.environment["MIGRATROM_TEST_DATABASE_URL"] != nil
    }
}

private struct NoopLogger: MigrationLogger {
    func info(_ message: String, metadata: String?) {}
    func warn(_ message: String, metadata: String?) {}
    func error(_ message: String, metadata: String?) {}
}

final class PostgresTestContext: @unchecked Sendable {
    let client: PostgresClient
    let schema: String
    let historyTable: String

    private let runTask: Task<Void, Never>

    init() throws {
        guard let urlString = ProcessInfo.processInfo.environment["MIGRATROM_TEST_DATABASE_URL"],
              let url = URL(string: urlString)
        else {
            throw PostgresTestError.missingDatabaseURL
        }
        let config = try Self.makeConfiguration(from: url)
        let client = PostgresClient(configuration: config)
        self.client = client
        self.schema = "migratrom_it_\(Self.randomSuffix())"
        self.historyTable = "__migratrom_history_\(Self.randomSuffix())__"
        self.runTask = Task { await client.run() }
    }

    func setup() async throws {
        try await withDB { db in
            try await db.execute("CREATE SCHEMA \(try quoteIdent(schema))")
        }
    }

    func teardown() async throws {
        defer { runTask.cancel() }
        try await withDB { db in
            try await db.execute("DROP SCHEMA IF EXISTS \(try quoteIdent(schema)) CASCADE")
            try await db.execute("DROP TABLE IF EXISTS \(try quoteIdent(historyTable))")
        }
    }

    func applyOptions(dryRun: Bool = false, advisoryLock: Bool = true) -> ApplyOptions {
        ApplyOptions(
            historyTable: historyTable,
            dryRun: dryRun,
            logger: NoopLogger(),
            advisoryLock: advisoryLock,
            dialect: PostgresDialect()
        )
    }

    func queryBool(_ sql: String) async throws -> Bool {
        try await withDB { try await $0.queryBool(sql) }
    }

    func historyRowCount() async throws -> Int {
        try await withDB { db in
            let rows = try await db.queryRows("SELECT id FROM \(try quoteIdent(historyTable))")
            return rows.count
        }
    }

    func appliedRecords() async throws -> [Int: AppliedMigrationRecord] {
        try await withDB { try await readAppliedRecords($0, name: historyTable, dialect: PostgresDialect()) }
    }

    func withDB<T: Sendable>(_ body: @Sendable (PostgresNIODB) async throws -> T) async throws -> T {
        try await client.withConnection { connection in
            let db = PostgresNIODB(connection: connection)
            return try await body(db)
        }
    }

    static func makeConfiguration(from url: URL) throws -> PostgresClient.Configuration {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "postgres" || scheme == "postgresql"
        else {
            throw PostgresTestError.invalidDatabaseURL(url.absoluteString)
        }
        guard let host = url.host, !host.isEmpty else {
            throw PostgresTestError.invalidDatabaseURL(url.absoluteString)
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

    private static func randomSuffix() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

enum PostgresTestError: Error, CustomStringConvertible {
    case missingDatabaseURL
    case invalidDatabaseURL(String)

    var description: String {
        switch self {
        case .missingDatabaseURL:
            "MIGRATROM_TEST_DATABASE_URL is not set"
        case .invalidDatabaseURL(let url):
            "invalid postgres URL: \(url)"
        }
    }
}

func linkedMigrations(schema: String, table: String) throws -> [Migration] {
    let uniqueKey = "\(table)_email_key"
    let dialect = PostgresDialect()
    let m1 = Migration(
        id: 1,
        parentId: nil,
        operations: [
            try createTable(
                schema,
                table,
                [
                    ColumnDef(name: "id", typeSql: "SERIAL"),
                    ColumnDef(name: "email", typeSql: "text"),
                        ],
                        primaryKey: PrimaryKey(columns: ["id"]),
                        dialect: dialect
                    ),
            try addUnique(schema, table, uniqueKey, ["email"], dialect: dialect),
        ]
    )
    let m2 = Migration(
        id: 2,
        parentId: 1,
        operations: [
            try addColumn(schema, table, ColumnDef(name: "name", typeSql: "text", nullable: true), dialect: dialect),
        ]
    )
    return [m1, m2]
}

func regclassExists(schema: String, name: String) throws -> String {
    "SELECT to_regclass(\(try regclassLiteral(schema, name))) IS NOT NULL"
}

func constraintExists(schema: String, table: String, name: String) throws -> String {
    """
    SELECT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = '\(name.replacingOccurrences(of: "'", with: "''"))'
      AND conrelid = \(try regclassLiteral(schema, table))::regclass
    )
    """
}

func withPostgresTest(
    _ body: (PostgresTestContext) async throws -> Void
) async throws {
    let ctx = try PostgresTestContext()
    try await ctx.setup()
    do {
        try await body(ctx)
    } catch {
        try? await ctx.teardown()
        throw error
    }
    try await ctx.teardown()
}

func uniqueTableName(_ prefix: String) -> String {
    "\(prefix)_\(UUID().uuidString.prefix(8))"
}

func columnExists(schema: String, table: String, column: String) throws -> String {
    """
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = '\(schema.replacingOccurrences(of: "'", with: "''"))'
      AND table_name = '\(table.replacingOccurrences(of: "'", with: "''"))'
      AND column_name = '\(column.replacingOccurrences(of: "'", with: "''"))'
    )
    """
}
