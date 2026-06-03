import Testing
@testable import Migratrom

private struct NoopLogger: MigrationLogger {
    func info(_ message: String, metadata: String?) {}
    func warn(_ message: String, metadata: String?) {}
    func error(_ message: String, metadata: String?) {}
}

private let sampleOp = Operation(
    id: "test.op",
    label: "Test op",
    precheck: [Check(description: "pre", sql: "SELECT pre")],
    execute: [ExecuteStep(description: "exec", sql: "DO THING")],
    postcheck: [Check(description: "post", sql: "SELECT post")]
)

private let sampleMigration = Migration(id: 1, parentId: nil, operations: [sampleOp])

private func applyOptions() -> ApplyOptions {
    ApplyOptions(logger: NoopLogger(), advisoryLock: false, dialect: PostgresDialect())
}

@Suite struct ApplyTests {
    @Test func secondRunIsNoOp() async throws {
        let db = FakeDB()
        db.setBoolSequence("SELECT post", [false, true])
        db.setBool("SELECT pre", true)

        let first = try await applyMigrations([sampleMigration], db: db, options: applyOptions())
        #expect(first.applied == [1])
        #expect(db.historyRecords.count == 1)

        db.setBool("SELECT post", true)
        let second = try await applyMigrations([sampleMigration], db: db, options: applyOptions())
        #expect(second.applied.isEmpty)
        #expect(db.historyRecords.count == 1)
    }

    @Test func checksumMismatchRejectsEditedMigration() async throws {
        let db = FakeDB()
        db.seedHistory([
            1: AppliedMigrationRecord(checksum: "sha256/deadbeef", operations: "00"),
        ])
        await #expect(throws: MigratromError.self) {
            try await applyMigrations([sampleMigration], db: db, options: applyOptions())
        }
    }

    @Test func failedOpLeavesNoHistoryRow() async throws {
        let db = PostApplyFailDB()
        await #expect(throws: MigratromError.self) {
            try await applyMigrations([sampleMigration], db: db, options: applyOptions())
        }
        #expect(db.historyRecords.isEmpty)
        #expect(db.wasRolledBack())
    }
}

/// Executes successfully but postcheck never passes after execute.
private final class PostApplyFailDB: DB, @unchecked Sendable {
    private let inner = FakeDB()

    var historyRecords: [Int: AppliedMigrationRecord] { inner.historyRecords }
    func wasRolledBack() -> Bool { inner.wasRolledBack() }

    func queryBool(_ sql: String) async throws -> Bool {
        if sql == "SELECT post" { return false }
        if sql == "SELECT pre" { return true }
        return try await inner.queryBool(sql)
    }

    func execute(_ sql: String) async throws {
        try await inner.execute(sql)
    }

    func queryRows(_ sql: String) async throws -> [any DBRow] {
        try await inner.queryRows(sql)
    }

    func withTransaction<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await inner.withTransaction(body)
    }
}
