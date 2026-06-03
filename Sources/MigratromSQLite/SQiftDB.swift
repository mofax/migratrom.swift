import Migratrom
import SQift

/// A ``DB`` adapter backed by [SQift](https://github.com/nike-inc/SQift)'s `Connection`.
///
/// This is the batteries-included SQLite adapter. Pair it with ``SQLiteDialect`` via
/// `ApplyOptions(dialect: SQLiteDialect())`. If you use a different SQLite driver, implement ``DB``
/// yourself and reuse ``SQLiteDialect`` for SQL generation.
public final class SQiftDB: DB, @unchecked Sendable {
    @TaskLocal private static var inTransaction = false

    private let connection: Connection

    public init(connection: Connection) {
        self.connection = connection
    }

    public func queryBool(_ sql: String) async throws -> Bool {
        let rows = try queryValues(sql)
        guard rows.count == 1, let value = rows[0].first else {
            throw MigratromError.checkShape(
                message: "check must return exactly one boolean row/column",
                rowPreview: previewRows(rows)
            )
        }
        if let bool = value as? Bool {
            return bool
        }
        if let int = value as? Int64 {
            return int != 0
        }
        if let int = value as? Int {
            return int != 0
        }
        throw MigratromError.checkShape(
            message: "check must return a boolean-compatible value",
            rowPreview: previewRows(rows)
        )
    }

    public func execute(_ sql: String) async throws {
        try connection.execute(sql)
    }

    public func queryRows(_ sql: String) async throws -> [any DBRow] {
        try queryValues(sql).map { SQiftRow(values: $0) }
    }

    public func withTransaction<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        if Self.inTransaction {
            return try await body()
        }
        try connection.execute("BEGIN")
        do {
            let value = try await Self.$inTransaction.withValue(true) {
                try await body()
            }
            try connection.execute("COMMIT")
            return value
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    private func queryValues(_ sql: String) throws -> [[Any?]] {
        try connection.prepare(sql).query { row in
            row.values
        }
    }

    private func previewRows(_ rows: [[Any?]]) -> String? {
        guard !rows.isEmpty else { return nil }
        let text = String(describing: rows[0])
        if text.count > 200 {
            return String(text.prefix(200)) + "…"
        }
        return text
    }
}

/// Positional row decode for SQift result rows.
struct SQiftRow: DBRow, @unchecked Sendable {
    let values: [Any?]

    func int(at index: Int) throws -> Int? {
        guard index < values.count else { return nil }
        if let value = values[index] as? Int {
            return value
        }
        if let value = values[index] as? Int64 {
            return Int(value)
        }
        return nil
    }

    func string(at index: Int) throws -> String? {
        guard index < values.count else { return nil }
        return values[index] as? String
    }
}
