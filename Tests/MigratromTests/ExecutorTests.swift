import Testing
@testable import Migratrom

private struct NoopLogger: MigrationLogger {
    func info(_ message: String, metadata: String?) {}
    func warn(_ message: String, metadata: String?) {}
    func error(_ message: String, metadata: String?) {}
}

@Suite struct ExecutorTests {
    private let sampleOp = Operation(
        id: "test.op",
        label: "Test op",
        precheck: [Check(description: "pre", sql: "SELECT pre")],
        execute: [ExecuteStep(description: "exec", sql: "DO THING")],
        postcheck: [Check(description: "post", sql: "SELECT post")]
    )

    @Test func skipsWhenPostcheckAlreadyTrue() async throws {
        let db = FakeDB()
        db.setBool("SELECT post", true)
        let result = try await runOperation(db, sampleOp, NoopLogger())
        #expect(result == .skipped)
        #expect(db.executed.isEmpty)
    }

    @Test func executesWhenPostcheckFalseThenTrue() async throws {
        let db = SequenceBoolDB(
            postSQL: "SELECT post",
            sequence: [false, true],
            preSQL: "SELECT pre",
            preValue: true
        )
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
        let db = PostcheckFailDB()
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

/// Returns scripted bool results for selected SQL while recording executes.
private final class SequenceBoolDB: DB, @unchecked Sendable {
    let postSQL: String
    var sequence: [Bool]
    let preSQL: String
    let preValue: Bool
    private(set) var executed: [String] = []
    private var postIndex = 0

    init(postSQL: String, sequence: [Bool], preSQL: String, preValue: Bool) {
        self.postSQL = postSQL
        self.sequence = sequence
        self.preSQL = preSQL
        self.preValue = preValue
    }

    func queryBool(_ sql: String) async throws -> Bool {
        if sql == postSQL {
            let value = sequence[postIndex]
            postIndex += 1
            return value
        }
        if sql == preSQL { return preValue }
        return false
    }

    func execute(_ sql: String) async throws {
        executed.append(sql)
    }

    func queryRows(_ sql: String) async throws -> [any DBRow] { [] }

    func withTransaction<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await body()
    }
}

/// Postcheck always false; precheck passes.
private final class PostcheckFailDB: DB, @unchecked Sendable {
    private(set) var executed: [String] = []

    func queryBool(_ sql: String) async throws -> Bool {
        if sql == "SELECT pre" { return true }
        return false
    }

    func execute(_ sql: String) async throws {
        executed.append(sql)
    }

    func queryRows(_ sql: String) async throws -> [any DBRow] { [] }

    func withTransaction<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await body()
    }
}
