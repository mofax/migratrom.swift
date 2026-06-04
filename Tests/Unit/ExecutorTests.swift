import Testing
@testable import Migratrom

@Suite struct ExecutorTests {
    @Test func skipsWhenPostcheckAlreadyTrue() async throws {
        let db = FakeDB()
        db.setBool("SELECT post", true)
        let result = try await runOperation(db, sampleOp, NoopLogger())
        #expect(result == .skipped)
        #expect(db.executed.isEmpty)
    }

    @Test func executesWhenPostcheckFalseThenTrue() async throws {
        let db = FakeDB()
        db.setBoolSequence("SELECT post", [false, true])
        db.setBool("SELECT pre", true)
        let result = try await runOperation(db, sampleOp, NoopLogger())
        #expect(result == .executed)
        #expect(db.executed == ["DO THING"])
    }

    @Test func precheckFailure() async throws {
        let db = FakeDB()
        db.setBool("SELECT post", false)
        db.setBool("SELECT pre", false)
        await #expect(throws: MigratromError.self) {
            try await runOperation(db, sampleOp, NoopLogger())
        }
    }

    @Test func postcheckFailureAfterExecute() async throws {
        // Precheck passes so the op executes, but the postcheck stays false.
        let db = FakeDB()
        db.setBool("SELECT pre", true)
        await #expect(throws: MigratromError.self) {
            try await runOperation(db, sampleOp, NoopLogger())
        }
        #expect(db.executed == ["DO THING"])
    }

    @Test func emptyPostcheckThrows() async throws {
        let db = FakeDB()
        let bad = Operation(
            id: sampleOp.id,
            label: sampleOp.label,
            precheck: sampleOp.precheck,
            execute: sampleOp.execute,
            postcheck: []
        )
        await #expect(throws: MigratromError.self) {
            try await runOperation(db, bad, NoopLogger())
        }
    }

    @Test func withTransactionRollsBackOnFailure() async throws {
        let db = FakeDB()
        db.setBool("SELECT post", false)
        db.setBool("SELECT pre", false)
        await #expect(throws: MigratromError.self) {
            try await db.withTransaction {
                _ = try await runOperation(db, sampleOp, NoopLogger())
            }
        }
        #expect(db.wasRolledBack())
        #expect(db.executed.isEmpty)
    }
}
