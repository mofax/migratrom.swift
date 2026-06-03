/// The driver-agnostic database contract. Adapters implement this; the core imports no driver.
public protocol DB: Sendable {
    /// Run a boolean check query.
    ///
    /// Implementations must return exactly **one row, one column, boolean**; otherwise throw
    /// ``MigratromError/checkShape(message:rowPreview:)`` (see `queryResult.ts` in the reference impl).
    func queryBool(_ sql: String) async throws -> Bool

    func execute(_ sql: String) async throws

    func queryRows(_ sql: String) async throws -> [any DBRow]

    func withTransaction<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T
}

/// Positional row decode for fixed-order `SELECT`s (e.g. history table reads).
public protocol DBRow: Sendable {
    func int(at index: Int) throws -> Int?
    func string(at index: Int) throws -> String?
}
