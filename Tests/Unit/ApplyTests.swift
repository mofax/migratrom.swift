import Testing
@testable import Migratrom

@Suite struct ApplyTests {
    @Test func secondRunIsNoOp() async throws {
        let db = FakeDB()
        db.setBoolSequence("SELECT post", [false, true])
        db.setBool("SELECT pre", true)

        let first = try await applyMigrations([sampleMigration], db: db, options: sampleApplyOptions())
        #expect(first.applied == [1])
        #expect(db.historyRecords.count == 1)

        db.setBool("SELECT post", true)
        let second = try await applyMigrations([sampleMigration], db: db, options: sampleApplyOptions())
        #expect(second.applied.isEmpty)
        #expect(db.historyRecords.count == 1)
    }

    @Test func checksumMismatchRejectsEditedMigration() async throws {
        let db = FakeDB()
        db.seedHistory([
            1: AppliedMigrationRecord(checksum: "sha256/deadbeef", operations: "00"),
        ])
        await #expect(throws: MigratromError.self) {
            try await applyMigrations([sampleMigration], db: db, options: sampleApplyOptions())
        }
    }

    @Test func failedOpLeavesNoHistoryRow() async throws {
        // Precheck passes and the op executes, but the postcheck never becomes true,
        // so the transaction must roll back and leave no history row.
        let db = FakeDB()
        db.setBool("SELECT pre", true)

        await #expect(throws: MigratromError.self) {
            try await applyMigrations([sampleMigration], db: db, options: sampleApplyOptions())
        }
        #expect(db.historyRecords.isEmpty)
        #expect(db.wasRolledBack())
    }
}
