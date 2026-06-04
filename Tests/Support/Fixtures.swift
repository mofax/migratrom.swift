import Testing
@testable import Migratrom

/// A `MigrationLogger` that discards everything, for tests that don't assert on logs.
struct NoopLogger: MigrationLogger {
    func info(_ message: String, metadata: String?) {}
    func warn(_ message: String, metadata: String?) {}
    func error(_ message: String, metadata: String?) {}
}

/// A minimal operation with `pre`/`exec`/`post` SQL, used across runner/executor tests.
let sampleOp = Operation(
    id: "test.op",
    label: "Test op",
    precheck: [Check(description: "pre", sql: "SELECT pre")],
    execute: [ExecuteStep(description: "exec", sql: "DO THING")],
    postcheck: [Check(description: "post", sql: "SELECT post")]
)

/// `sampleOp` wrapped in a root migration.
let sampleMigration = Migration(id: 1, parentId: nil, operations: [sampleOp])

/// Default apply options: no advisory lock, Postgres dialect, silent logger.
func sampleApplyOptions() -> ApplyOptions {
    ApplyOptions(logger: NoopLogger(), advisoryLock: false, dialect: PostgresDialect())
}
