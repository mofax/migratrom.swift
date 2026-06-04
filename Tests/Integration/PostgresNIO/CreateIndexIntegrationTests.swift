import Migratrom
import MigratromPostgresNIO
import Testing

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
