import MigratromSQLite
import Testing
@testable import Migratrom

@Suite struct SQLiteSqlTests {
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
}
