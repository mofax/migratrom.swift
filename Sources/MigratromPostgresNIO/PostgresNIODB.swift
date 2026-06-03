import Logging
import Migratrom
import PostgresNIO

public final class PostgresNIODB: DB, @unchecked Sendable {
    @TaskLocal private static var inTransaction = false

    private let connection: PostgresConnection

    public init(connection: PostgresConnection) {
        self.connection = connection
    }

    public func queryBool(_ sql: String) async throws -> Bool {
        let rows = try await runQuery(sql)
        guard rows.count == 1 else {
            throw MigratromError.checkShape(
                message: "check must return exactly one row, got \(rows.count)",
                rowPreview: previewRows(rows)
            )
        }
        let access = rows[0].makeRandomAccess()
        guard access.count == 1 else {
            throw MigratromError.checkShape(
                message: "must return exactly one column, got \(access.count)",
                rowPreview: previewRows(rows)
            )
        }
        do {
            return try access[0].decode(Bool.self)
        } catch {
            throw MigratromError.checkShape(
                message: "check must return a boolean, got decode error",
                rowPreview: previewRows(rows)
            )
        }
    }

    public func execute(_ sql: String) async throws {
        _ = try await runQuery(sql)
    }

    public func queryRows(_ sql: String) async throws -> [any DBRow] {
        let rows = try await runQuery(sql)
        return rows.map { PostgresNIORow(row: $0.makeRandomAccess()) }
    }

    public func withTransaction<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        if Self.inTransaction {
            return try await body()
        }
        try await execute("BEGIN")
        do {
            let value = try await Self.$inTransaction.withValue(true) {
                try await body()
            }
            try await execute("COMMIT")
            return value
        } catch {
            try? await execute("ROLLBACK")
            throw error
        }
    }

    private func runQuery(_ sql: String) async throws -> [PostgresRow] {
        let sequence = try await connection.query(
            PostgresQuery(unsafeSQL: sql),
            logger: connection.logger
        )
        return try await sequence.collect()
    }

    private func previewRows(_ rows: [PostgresRow]) -> String? {
        guard let first = rows.first else { return nil }
        let text = String(describing: first)
        if text.count > 200 {
            return String(text.prefix(200)) + "…"
        }
        return text
    }
}

struct PostgresNIORow: DBRow, Sendable {
    let row: PostgresRandomAccessRow

    func int(at index: Int) throws -> Int? {
        guard index < row.count else { return nil }
        if let value: Int64 = try? row[index].decode(Int64.self) {
            return Int(value)
        }
        return try row[index].decode(Int.self)
    }

    func string(at index: Int) throws -> String? {
        guard index < row.count else { return nil }
        return try row[index].decode(String?.self)
    }
}
