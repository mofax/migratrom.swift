import Migratrom
import PostgresNIO

public func applyMigrations(
    _ migrations: [Migration],
    on client: PostgresClient,
    options: ApplyOptions
) async throws -> ApplyResult {
    try await client.withConnection { connection in
        let db = PostgresNIODB(connection: connection)
        return try await applyMigrations(migrations, db: db, options: options)
    }
}

public func applyMigrations(
    _ migrations: [Migration],
    on connection: PostgresConnection,
    options: ApplyOptions
) async throws -> ApplyResult {
    let db = PostgresNIODB(connection: connection)
    return try await applyMigrations(migrations, db: db, options: options)
}
