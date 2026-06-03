public func defaultHistoryTable() -> String {
    ApplyOptions.defaultHistoryTable
}

public struct AppliedMigrationRecord: Sendable, Equatable {
    public var checksum: String
    /// Canonical-encoding hex at apply time; `nil` for rows written before this column existed.
    public var operations: String?

    public init(checksum: String, operations: String?) {
        self.checksum = checksum
        self.operations = operations
    }
}

public func ensureHistoryTable(
    _ db: any DB,
    name: String,
    dialect: any SQLDialect
) async throws {
    try await db.execute(dialect.createHistoryTableSql(name: name))
}

public func readAppliedIds(
    _ db: any DB,
    name: String,
    dialect: any SQLDialect
) async throws -> Set<Int> {
    let table = try dialect.quoteIdent(name)
    let rows = try await db.queryRows("SELECT id FROM \(table)")
    var ids = Set<Int>()
    ids.reserveCapacity(rows.count)
    for row in rows {
        guard let id = try row.int(at: 0) else { continue }
        ids.insert(id)
    }
    return ids
}

public func readAppliedRecords(
    _ db: any DB,
    name: String,
    dialect: any SQLDialect
) async throws -> [Int: AppliedMigrationRecord] {
    let table = try dialect.quoteIdent(name)
    let rows = try await db.queryRows("SELECT id, checksum, operations FROM \(table)")
    var records: [Int: AppliedMigrationRecord] = [:]
    records.reserveCapacity(rows.count)
    for row in rows {
        guard let id = try row.int(at: 0),
              let checksum = try row.string(at: 1)
        else { continue }
        let operations = try row.string(at: 2)
        records[id] = AppliedMigrationRecord(checksum: checksum, operations: operations)
    }
    return records
}

public func recordMigration(
    _ db: any DB,
    name: String,
    migration: Migration,
    dialect: any SQLDialect
) async throws {
    let digest = checksum(migration.operations)
    let operationsHex = hexLower(canonicalEncode(migration.operations))
    let table = try dialect.quoteIdent(name)
    let parent = migration.parentId.map(String.init) ?? "NULL"
    try await db.execute(
        """
        INSERT INTO \(table) (id, parent_id, checksum, operations) \
        VALUES (\(migration.id), \(parent), \(dialect.quoteLiteral(digest)), \(dialect.quoteLiteral(operationsHex)))
        """
    )
}
