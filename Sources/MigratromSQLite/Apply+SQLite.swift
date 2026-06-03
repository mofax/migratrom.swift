import Migratrom
import SQift

/// Apply migrations against a SQift `Connection`.
///
/// `options` is required and must carry a SQLite-aware dialect, e.g.
/// `ApplyOptions(dialect: SQLiteDialect())`. The dialect is never defaulted — pick it explicitly.
public func applyMigrations(
    _ migrations: [Migration],
    on connection: Connection,
    options: ApplyOptions
) async throws -> ApplyResult {
    let db = SQiftDB(connection: connection)
    return try await applyMigrations(migrations, db: db, options: options)
}
