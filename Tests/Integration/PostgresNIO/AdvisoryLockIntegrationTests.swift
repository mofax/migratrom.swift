import Migratrom
import MigratromPostgresNIO
import Testing

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
