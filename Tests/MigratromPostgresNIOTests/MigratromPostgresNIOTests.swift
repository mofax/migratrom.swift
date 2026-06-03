import Migratrom
import MigratromPostgresNIO
import Testing

@Suite(.enabled(if: PostgresTestHarness.isAvailable))
struct ApplyIntegrationTests {
    @Test func applyLinkedMigrationsRecordsHistory() async throws {
        try await withPostgresTest { ctx in
            let table = uniqueTableName("users")
            let migrations = try linkedMigrations(schema: ctx.schema, table: table)

            let result = try await applyMigrations(migrations, on: ctx.client, options: ctx.applyOptions())
            #expect(result.applied == [1, 2])

            #expect(try await ctx.queryBool(try regclassExists(schema: ctx.schema, name: table)))
            #expect(try await ctx.queryBool(try constraintExists(schema: ctx.schema, table: table, name: "\(table)_email_key")))
            #expect(try await ctx.queryBool(try columnExists(schema: ctx.schema, table: table, column: "name")))
            #expect(try await ctx.historyRowCount() == 2)

            let records = try await ctx.appliedRecords()
            #expect(records[1]?.checksum.hasPrefix("sha256/") == true)
            #expect(records[2]?.checksum.hasPrefix("sha256/") == true)
            try verifyChecksum(records[1]!.checksum, against: migrations[0].operations, migrationId: 1)
        }
    }

    @Test func rerunIsIdempotent() async throws {
        try await withPostgresTest { ctx in
            let table = uniqueTableName("rerun")
            let migrations = try linkedMigrations(schema: ctx.schema, table: table)
            let options = ctx.applyOptions()

            let first = try await applyMigrations(migrations, on: ctx.client, options: options)
            #expect(first.applied == [1, 2])

            let second = try await applyMigrations(migrations, on: ctx.client, options: options)
            #expect(second.applied.isEmpty)
            #expect(try await ctx.historyRowCount() == 2)
        }
    }

    @Test func dryRunLeavesSchemaAndHistoryUnchanged() async throws {
        try await withPostgresTest { ctx in
            let table = uniqueTableName("dryrun")
            let migrations = try linkedMigrations(schema: ctx.schema, table: table)

            let result = try await applyMigrations(
                migrations,
                on: ctx.client,
                options: ctx.applyOptions(dryRun: true)
            )
            #expect(result.applied.isEmpty)

            #expect(try await ctx.queryBool(try regclassExists(schema: ctx.schema, name: table)) == false)
            #expect(try await ctx.historyRowCount() == 0)

            let real = try await applyMigrations(migrations, on: ctx.client, options: ctx.applyOptions())
            #expect(real.applied == [1, 2])
        }
    }

    @Test func editedMigrationRaisesChecksumMismatch() async throws {
        try await withPostgresTest { ctx in
            let table = uniqueTableName("checksum")
            var migrations = try linkedMigrations(schema: ctx.schema, table: table)
            let options = ctx.applyOptions()

            _ = try await applyMigrations(migrations, on: ctx.client, options: options)

            migrations[0].operations[0].execute[0].sql += " "

            await #expect(throws: MigratromError.self) {
                try await applyMigrations(migrations, on: ctx.client, options: options)
            }
        }
    }
}

@Suite(.enabled(if: PostgresTestHarness.isAvailable))
struct CreateIndexIntegrationTests {
    @Test func concurrentIndexRunsOutsideTransaction() async throws {
        try await withPostgresTest { ctx in
            let table = uniqueTableName("article")
            let index = "\(table)_slug_idx"
            let dialect = PostgresDialect()
            let migration = Migration(
                id: 1,
                parentId: nil,
                operations: [
                    try createTable(
                        ctx.schema,
                        table,
                        [
                            ColumnDef(name: "id", typeSql: "SERIAL"),
                            ColumnDef(name: "slug", typeSql: "text"),
                        ],
                        primaryKey: PrimaryKey(columns: ["id"]),
                        dialect: dialect
                    ),
                    try createIndex(
                        ctx.schema,
                        table,
                        index,
                        ["slug"],
                        options: CreateIndexOptions(concurrently: true),
                        dialect: dialect
                    ),
                ]
            )

            let result = try await applyMigrations([migration], on: ctx.client, options: ctx.applyOptions())
            #expect(result.applied == [1])
            #expect(try await ctx.queryBool(try regclassExists(schema: ctx.schema, name: index)))
        }
    }
}

@Suite(.enabled(if: PostgresTestHarness.isAvailable))
struct AdvisoryLockIntegrationTests {
    @Test func concurrentApplySerializes() async throws {
        try await withPostgresTest { ctx in
            let table = uniqueTableName("locked")
            let migration = try linkedMigrations(schema: ctx.schema, table: table)[0]
            let options = ctx.applyOptions(advisoryLock: true)

            async let first = applyMigrations([migration], on: ctx.client, options: options)
            async let second = applyMigrations([migration], on: ctx.client, options: options)

            let r1 = try await first
            let r2 = try await second
            let applied = (r1.applied + r2.applied).sorted()
            #expect(applied == [1])
            #expect(try await ctx.historyRowCount() == 1)
        }
    }
}
