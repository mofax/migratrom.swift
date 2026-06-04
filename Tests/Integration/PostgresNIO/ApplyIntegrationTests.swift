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
