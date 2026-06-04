import Testing
@testable import Migratrom

private func caps(
    enumTypes: Bool = true,
    sequences: Bool = true,
    materializedViews: Bool = true,
    extensions: Bool = true,
    concurrentIndexes: Bool = true,
    schemas: Bool = true,
    advisoryLocks: Bool = true
) -> DialectCapabilities {
    DialectCapabilities(
        enumTypes: enumTypes,
        sequences: sequences,
        materializedViews: materializedViews,
        extensions: extensions,
        concurrentIndexes: concurrentIndexes,
        schemas: schemas,
        advisoryLocks: advisoryLocks
    )
}

/// Wraps `PostgresDialect`, forwarding every method, but lets a test flip capability
/// flags off (to exercise gating) or swap `quoteIdent` for a sentinel (to prove the
/// dialect is actually threaded, not the free functions).
private struct StubDialect: SQLDialect {
    private let base = PostgresDialect()
    var capabilities: DialectCapabilities
    var quoteIdentSentinel = false

    var name: String { "stub" }

    func quoteIdent(_ name: String) throws -> String {
        quoteIdentSentinel ? "<<\(name)>>" : try base.quoteIdent(name)
    }
    func quoteLiteral(_ value: String) -> String { base.quoteLiteral(value) }
    func qualified(_ schema: String, _ name: String) throws -> String { try base.qualified(schema, name) }
    func quoteIdentList(_ names: [String]) throws -> String { try base.quoteIdentList(names) }

    func renderColumnDef(_ col: ColumnDef) throws -> String { try base.renderColumnDef(col) }
    func renderColumnList(_ columns: [ColumnDef]) throws -> String { try base.renderColumnList(columns) }

    func createIndexSql(
        schema: String,
        table: String,
        indexName: String,
        columns: [String],
        concurrently: Bool
    ) throws -> String {
        try base.createIndexSql(
            schema: schema,
            table: table,
            indexName: indexName,
            columns: columns,
            concurrently: concurrently
        )
    }

    func tableExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String {
        try base.tableExistsSql(schema, table, negate: negate)
    }
    func columnExistsSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        base.columnExistsSql(schema, table, column, negate: negate)
    }
    func constraintExistsSql(_ schema: String, _ table: String, _ name: String, negate: Bool) throws -> String {
        try base.constraintExistsSql(schema, table, name, negate: negate)
    }
    func primaryKeyExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String {
        try base.primaryKeyExistsSql(schema, table, negate: negate)
    }
    func checkConstraintExistsSql(_ schema: String, _ table: String, _ name: String, negate: Bool) throws -> String {
        try base.checkConstraintExistsSql(schema, table, name, negate: negate)
    }
    func schemaExistsSql(_ schema: String, negate: Bool) -> String {
        base.schemaExistsSql(schema, negate: negate)
    }
    func extensionExistsSql(_ name: String, negate: Bool) -> String {
        base.extensionExistsSql(name, negate: negate)
    }
    func enumTypeExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        base.enumTypeExistsSql(schema, name, negate: negate)
    }
    func enumLabelExistsSql(_ schema: String, _ typeName: String, _ value: String, negate: Bool) -> String {
        base.enumLabelExistsSql(schema, typeName, value, negate: negate)
    }
    func viewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        base.viewExistsSql(schema, name, negate: negate)
    }
    func matviewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        base.matviewExistsSql(schema, name, negate: negate)
    }
    func columnDefaultSetSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        base.columnDefaultSetSql(schema, table, column, negate: negate)
    }
    func columnNotNullSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        base.columnNotNullSql(schema, table, column, negate: negate)
    }

    func createHistoryTableSql(name: String) throws -> String { try base.createHistoryTableSql(name: name) }
    func acquireLock(_ db: any DB, key: Int64) async throws { try await base.acquireLock(db, key: key) }
    func releaseLock(_ db: any DB, key: Int64) async throws { try await base.releaseLock(db, key: key) }
}

@Suite struct DialectTests {
    // MARK: - History DDL parity

    @Test func postgresHistoryDdlMatches() throws {
        let sql = try PostgresDialect().createHistoryTableSql(name: "__migratron_history__")
        #expect(sql.contains("timestamptz"))
        #expect(sql.contains("bigint"))
        #expect(sql.hasPrefix("CREATE TABLE IF NOT EXISTS \"__migratron_history__\""))
    }

    // MARK: - Capability gating

    @Test func enumTypeUnsupportedThrows() throws {
        let d = StubDialect(capabilities: caps(enumTypes: false))
        #expect(throws: MigratromError.self) {
            _ = try createType("public", "mood", ["happy"], dialect: d)
        }
    }

    @Test func enumValueUnsupportedThrows() throws {
        let d = StubDialect(capabilities: caps(enumTypes: false))
        #expect(throws: MigratromError.self) {
            _ = try addEnumValue("public", "mood", "sad", dialect: d)
        }
    }

    @Test func sequenceUnsupportedThrows() throws {
        let d = StubDialect(capabilities: caps(sequences: false))
        #expect(throws: MigratromError.self) {
            _ = try createSequence("public", "order_seq", dialect: d)
        }
    }

    @Test func materializedViewUnsupportedThrows() throws {
        let d = StubDialect(capabilities: caps(materializedViews: false))
        #expect(throws: MigratromError.self) {
            _ = try createMaterializedView("public", "mv", "SELECT 1", dialect: d)
        }
    }

    @Test func extensionUnsupportedThrows() throws {
        let d = StubDialect(capabilities: caps(extensions: false))
        #expect(throws: MigratromError.self) {
            _ = try createExtension("plpgsql", dialect: d)
        }
    }

    @Test func schemaUnsupportedThrows() throws {
        let d = StubDialect(capabilities: caps(schemas: false))
        #expect(throws: MigratromError.self) {
            _ = try createSchema("app", dialect: d)
        }
    }

    @Test func concurrentIndexUnsupportedThrows() throws {
        let d = StubDialect(capabilities: caps(concurrentIndexes: false))
        #expect(throws: MigratromError.self) {
            _ = try createIndex(
                "public", "user", "user_email_idx", ["email"],
                options: CreateIndexOptions(concurrently: true),
                dialect: d
            )
        }
    }

    @Test func nonConcurrentIndexAllowedWithoutCapability() throws {
        let d = StubDialect(capabilities: caps(concurrentIndexes: false))
        // A plain (non-concurrent) index must NOT be gated.
        let op = try createIndex("public", "user", "user_email_idx", ["email"], dialect: d)
        #expect(op.execute.first?.sql.contains("CONCURRENTLY") == false)
    }

    // MARK: - Seam threading

    @Test func builderUsesDialectQuotingNotFreeFunctions() throws {
        var d = StubDialect(capabilities: caps())
        d.quoteIdentSentinel = true
        let op = try createSchema("app", dialect: d)
        #expect(op.execute.first?.sql == "CREATE SCHEMA <<app>>")
    }

    // MARK: - No-lock path

    @Test func noAdvisoryLockWhenCapabilityOff() async throws {
        let db = FakeDB()
        db.setBool("SELECT pre", true)
        db.setBoolSequence("SELECT post", [false, true])

        let options = ApplyOptions(
            logger: NoopLogger(),
            advisoryLock: true, // requested, but the dialect lacks the capability
            dialect: StubDialect(capabilities: caps(advisoryLocks: false))
        )
        let result = try await applyMigrations([sampleMigration], db: db, options: options)

        #expect(result.applied == [1])
        #expect(!db.executed.contains { $0.contains("pg_advisory_lock") })
        #expect(!db.executed.contains { $0.contains("pg_advisory_unlock") })
    }

    @Test func advisoryLockEmittedWhenCapabilityOn() async throws {
        let db = FakeDB()
        db.setBool("SELECT pre", true)
        db.setBoolSequence("SELECT post", [false, true])

        let options = ApplyOptions(logger: NoopLogger(), advisoryLock: true, dialect: PostgresDialect())
        _ = try await applyMigrations([sampleMigration], db: db, options: options)

        #expect(db.executed.contains { $0.contains("pg_advisory_lock") })
        #expect(db.executed.contains { $0.contains("pg_advisory_unlock") })
    }
}
