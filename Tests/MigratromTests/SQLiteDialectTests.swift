import Foundation
import MigratromSQLite
import SQift
import Testing
@testable import Migratrom

private struct SQLiteTempDatabase {
    var url: URL

    init() {
        let fileName = "migratrom-\(UUID().uuidString).sqlite"
        self.url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite struct SQLiteDialectTests {
    @Test func historyDdlUsesSQLiteTypes() throws {
        let sql = try SQLiteDialect().createHistoryTableSql(name: "__migratrom_history__")
        #expect(sql.contains("INTEGER PRIMARY KEY"))
        #expect(sql.contains("DEFAULT CURRENT_TIMESTAMP"))
        #expect(!sql.contains("timestamptz"))
    }

    @Test func supportedBuildersEmitSQLiteSql() throws {
        let dialect = SQLiteDialect()
        let table = try createTable(
            "main",
            "users",
            [
                ColumnDef(name: "id", typeSql: "INTEGER"),
                ColumnDef(name: "email", typeSql: "TEXT"),
            ],
            primaryKey: PrimaryKey(columns: ["id"]),
            dialect: dialect
        )
        #expect(table.execute[0].sql == """
        CREATE TABLE "main"."users" (
          "id" INTEGER NOT NULL,
          "email" TEXT NOT NULL,
          PRIMARY KEY ("id")
        )
        """)
        #expect(table.precheck[0].sql.contains("\"main\".sqlite_master"))

        let column = try addColumn("main", "users", ColumnDef(name: "name", typeSql: "TEXT", nullable: true), dialect: dialect)
        #expect(column.execute[0].sql == #"ALTER TABLE "main"."users" ADD COLUMN "name" TEXT"#)

        let index = try createIndex("main", "users", "users_email_idx", ["email"], dialect: dialect)
        #expect(index.execute[0].sql == #"CREATE INDEX "main"."users_email_idx" ON "users" ("email")"#)
    }

    @Test func unsupportedSQLiteBuildersThrow() throws {
        let dialect = SQLiteDialect()
        #expect(throws: MigratromError.self) {
            _ = try createSchema("app", dialect: dialect)
        }
        #expect(throws: MigratromError.self) {
            _ = try addUnique("main", "users", "users_email_key", ["email"], dialect: dialect)
        }
        #expect(throws: MigratromError.self) {
            _ = try setColumnDefault("main", "users", "email", "DEFAULT ''", dialect: dialect)
        }
        #expect(throws: MigratromError.self) {
            _ = try createIndex(
                "main",
                "users",
                "users_email_idx",
                ["email"],
                options: CreateIndexOptions(concurrently: true),
                dialect: dialect
            )
        }
    }

    @Test func applyMigrationsAgainstOnDiskSQLiteFile() async throws {
        let temp = SQLiteTempDatabase()
        defer { temp.remove() }

        let dialect = SQLiteDialect()
        let connection = try Connection(storageLocation: .onDisk(temp.url.path))
        try connection.execute("PRAGMA foreign_keys = ON")
        let db = SQiftDB(connection: connection)
        let historyTable = "__migratrom_sqlite_history__"
        let migration = Migration(
            id: 1,
            parentId: nil,
            operations: [
                try createTable(
                    "main",
                    "users",
                    [
                        ColumnDef(name: "id", typeSql: "INTEGER"),
                        ColumnDef(name: "email", typeSql: "TEXT"),
                    ],
                    primaryKey: PrimaryKey(columns: ["id"]),
                    dialect: dialect
                ),
                try addColumn("main", "users", ColumnDef(name: "name", typeSql: "TEXT", nullable: true), dialect: dialect),
                try createIndex("main", "users", "users_email_idx", ["email"], dialect: dialect),
                try createView("main", "user_emails", #"SELECT "email" FROM "main"."users""#, dialect: dialect),
                try renameColumn("main", "users", "name", "display_name", dialect: dialect),
                try renameTable("main", "users", "accounts", dialect: dialect),
            ]
        )
        let options = ApplyOptions(historyTable: historyTable, advisoryLock: true, dialect: dialect)

        let first = try await applyMigrations([migration], on: connection, options: options)
        #expect(first.applied == [1])

        let second = try await applyMigrations([migration], on: connection, options: options)
        #expect(second.applied.isEmpty)

        #expect(try await db.queryBool("SELECT EXISTS (SELECT 1 FROM main.sqlite_master WHERE type = 'table' AND name = 'accounts')"))
        #expect(try await db.queryBool("SELECT EXISTS (SELECT 1 FROM pragma_table_info('accounts') WHERE name = 'display_name')"))
        #expect(try await db.queryBool("SELECT EXISTS (SELECT 1 FROM main.sqlite_master WHERE type = 'index' AND name = 'users_email_idx')"))
        #expect(try await db.queryBool("SELECT EXISTS (SELECT 1 FROM main.sqlite_master WHERE type = 'view' AND name = 'user_emails')"))

        let historyRows = try await db.queryRows("SELECT id FROM \(try dialect.quoteIdent(historyTable))")
        #expect(historyRows.count == 1)
    }
}
