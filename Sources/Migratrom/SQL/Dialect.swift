import Foundation

/// The set of optional SQL features a dialect may or may not support.
///
/// Builders consult these flags to hard-error (via ``MigratromError/unsupported(feature:dialect:)``)
/// on features the active dialect cannot express, rather than emitting invalid SQL.
public struct DialectCapabilities: Sendable, Equatable {
    public var enumTypes: Bool
    public var sequences: Bool
    public var materializedViews: Bool
    public var extensions: Bool
    public var concurrentIndexes: Bool
    public var schemas: Bool
    public var advisoryLocks: Bool
    public var addCheckConstraints: Bool
    public var addPrimaryKeyConstraints: Bool
    public var addUniqueConstraints: Bool
    public var addForeignKeys: Bool
    public var alterColumnDefault: Bool
    public var alterColumnNotNull: Bool

    public init(
        enumTypes: Bool,
        sequences: Bool,
        materializedViews: Bool,
        extensions: Bool,
        concurrentIndexes: Bool,
        schemas: Bool,
        advisoryLocks: Bool,
        addCheckConstraints: Bool = true,
        addPrimaryKeyConstraints: Bool = true,
        addUniqueConstraints: Bool = true,
        addForeignKeys: Bool = true,
        alterColumnDefault: Bool = true,
        alterColumnNotNull: Bool = true
    ) {
        self.enumTypes = enumTypes
        self.sequences = sequences
        self.materializedViews = materializedViews
        self.extensions = extensions
        self.concurrentIndexes = concurrentIndexes
        self.schemas = schemas
        self.advisoryLocks = advisoryLocks
        self.addCheckConstraints = addCheckConstraints
        self.addPrimaryKeyConstraints = addPrimaryKeyConstraints
        self.addUniqueConstraints = addUniqueConstraints
        self.addForeignKeys = addForeignKeys
        self.alterColumnDefault = alterColumnDefault
        self.alterColumnNotNull = alterColumnNotNull
    }
}

/// The single seam that bundles every known database-specific ("dialect") behaviour:
/// identifier quoting, column rendering, catalog/existence probes, the history-table DDL,
/// and advisory locking.
///
/// Adding a new database is "implement this protocol". The core engine, the `Operation`
/// shape, and the builder call sites are all dialect-agnostic.
public protocol SQLDialect: Sendable {
    var name: String { get }
    var capabilities: DialectCapabilities { get }

    // identifiers & literals
    func quoteIdent(_ name: String) throws -> String
    func quoteLiteral(_ value: String) -> String
    func qualified(_ schema: String, _ name: String) throws -> String
    func quoteIdentList(_ names: [String]) throws -> String

    // column rendering
    func renderColumnDef(_ col: ColumnDef) throws -> String
    func renderColumnList(_ columns: [ColumnDef]) throws -> String

    // statement rendering that differs by dialect beyond identifier quoting
    func createIndexSql(
        schema: String,
        table: String,
        indexName: String,
        columns: [String],
        concurrently: Bool
    ) throws -> String

    // catalog existence probes — one per current Catalog.swift function.
    // Each returns a SQL string that yields a single boolean.
    func tableExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String
    func columnExistsSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String
    func constraintExistsSql(_ schema: String, _ table: String, _ name: String, negate: Bool) throws -> String
    func primaryKeyExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String
    func checkConstraintExistsSql(_ schema: String, _ table: String, _ name: String, negate: Bool) throws -> String
    func schemaExistsSql(_ schema: String, negate: Bool) -> String
    func extensionExistsSql(_ name: String, negate: Bool) -> String
    func enumTypeExistsSql(_ schema: String, _ name: String, negate: Bool) -> String
    func enumLabelExistsSql(_ schema: String, _ typeName: String, _ value: String, negate: Bool) -> String
    func viewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String
    func matviewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String
    func columnDefaultSetSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String
    func columnNotNullSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String

    // history + locking
    func createHistoryTableSql(name: String) throws -> String
    func acquireLock(_ db: any DB, key: Int64) async throws
    func releaseLock(_ db: any DB, key: Int64) async throws
}

/// The Postgres dialect: the sole concrete implementation today. Every method delegates to the
/// existing free functions in `Identifiers.swift`, `Columns.swift`, and `Catalog.swift`, so the
/// emitted SQL is byte-for-byte identical to the pre-refactor output.
public struct PostgresDialect: SQLDialect {
    public init() {}

    public let name = "postgres"

    public let capabilities = DialectCapabilities(
        enumTypes: true,
        sequences: true,
        materializedViews: true,
        extensions: true,
        concurrentIndexes: true,
        schemas: true,
        advisoryLocks: true
    )

    // identifiers & literals
    public func quoteIdent(_ name: String) throws -> String {
        try Migratrom.quoteIdent(name)
    }

    public func quoteLiteral(_ value: String) -> String {
        Migratrom.quoteLiteral(value)
    }

    public func qualified(_ schema: String, _ name: String) throws -> String {
        try Migratrom.qualified(schema, name)
    }

    public func quoteIdentList(_ names: [String]) throws -> String {
        try Migratrom.quoteIdentList(names)
    }

    // column rendering
    public func renderColumnDef(_ col: ColumnDef) throws -> String {
        try Migratrom.renderColumnDef(col)
    }

    public func renderColumnList(_ columns: [ColumnDef]) throws -> String {
        try Migratrom.renderColumnList(columns)
    }

    // Postgres places the index in the table's schema automatically, so the index name is
    // unqualified and the table is schema-qualified.
    public func createIndexSql(
        schema: String,
        table: String,
        indexName: String,
        columns: [String],
        concurrently: Bool
    ) throws -> String {
        let concurrentlySql = concurrently ? " CONCURRENTLY" : ""
        return "CREATE INDEX\(concurrentlySql) \(try quoteIdent(indexName)) ON \(try qualified(schema, table)) (\(try quoteIdentList(columns)))"
    }

    // catalog existence probes
    public func tableExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String {
        try regclassExistsSql(schema, table, negate: negate)
    }

    public func columnExistsSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        Migratrom.columnExistsSql(schema, table, column, negate: negate)
    }

    public func constraintExistsSql(_ schema: String, _ table: String, _ name: String, negate: Bool) throws -> String {
        try Migratrom.constraintExistsSql(schema, table, name, negate: negate)
    }

    public func primaryKeyExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String {
        try Migratrom.primaryKeyExistsSql(schema, table, negate: negate)
    }

    public func checkConstraintExistsSql(_ schema: String, _ table: String, _ name: String, negate: Bool) throws -> String {
        try Migratrom.checkConstraintExistsSql(schema, table, name, negate: negate)
    }

    public func schemaExistsSql(_ schema: String, negate: Bool) -> String {
        Migratrom.schemaExistsSql(schema, negate: negate)
    }

    public func extensionExistsSql(_ name: String, negate: Bool) -> String {
        Migratrom.extensionExistsSql(name, negate: negate)
    }

    public func enumTypeExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        Migratrom.enumTypeExistsSql(schema, name, negate: negate)
    }

    public func enumLabelExistsSql(_ schema: String, _ typeName: String, _ value: String, negate: Bool) -> String {
        Migratrom.enumLabelExistsSql(schema, typeName, value, negate: negate)
    }

    public func viewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        Migratrom.viewExistsSql(schema, name, negate: negate)
    }

    public func matviewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        Migratrom.matviewExistsSql(schema, name, negate: negate)
    }

    public func columnDefaultSetSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        Migratrom.columnDefaultSetSql(schema, table, column, negate: negate)
    }

    public func columnNotNullSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        Migratrom.columnNotNullSql(schema, table, column, negate: negate)
    }

    // history + locking
    public func createHistoryTableSql(name: String) throws -> String {
        let table = try quoteIdent(name)
        return """
        CREATE TABLE IF NOT EXISTS \(table) (
          id          bigint PRIMARY KEY,
          parent_id   bigint,
          applied_at  timestamptz NOT NULL DEFAULT now(),
          operations  text NOT NULL,
          checksum    text NOT NULL
        )
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func acquireLock(_ db: any DB, key: Int64) async throws {
        try await db.execute("SELECT pg_advisory_lock(\(key))")
    }

    public func releaseLock(_ db: any DB, key: Int64) async throws {
        try await db.execute("SELECT pg_advisory_unlock(\(key))")
    }
}

public struct SQLiteDialect: SQLDialect {
    public init() {}

    public let name = "sqlite"

    public let capabilities = DialectCapabilities(
        enumTypes: false,
        sequences: false,
        materializedViews: false,
        extensions: false,
        concurrentIndexes: false,
        schemas: false,
        advisoryLocks: false,
        addCheckConstraints: false,
        addPrimaryKeyConstraints: false,
        addUniqueConstraints: false,
        addForeignKeys: false,
        alterColumnDefault: false,
        alterColumnNotNull: false
    )

    public func quoteIdent(_ name: String) throws -> String {
        try Migratrom.quoteIdent(name)
    }

    public func quoteLiteral(_ value: String) -> String {
        Migratrom.quoteLiteral(value)
    }

    public func qualified(_ schema: String, _ name: String) throws -> String {
        try "\(quoteIdent(schema)).\(quoteIdent(name))"
    }

    public func quoteIdentList(_ names: [String]) throws -> String {
        try names.map(quoteIdent).joined(separator: ", ")
    }

    public func renderColumnDef(_ col: ColumnDef) throws -> String {
        var parts = [try quoteIdent(col.name), col.typeSql]
        if let defaultSql = col.defaultSql {
            parts.append(defaultSql)
        }
        if !col.nullable {
            parts.append("NOT NULL")
        }
        return parts.joined(separator: " ")
    }

    public func renderColumnList(_ columns: [ColumnDef]) throws -> String {
        try columns.map(renderColumnDef).joined(separator: ",\n  ")
    }

    // SQLite forbids a schema-qualified table in CREATE INDEX; the schema is carried on the index
    // name instead and the table is referenced unqualified.
    public func createIndexSql(
        schema: String,
        table: String,
        indexName: String,
        columns: [String],
        concurrently: Bool
    ) throws -> String {
        "CREATE INDEX \(try qualified(schema, indexName)) ON \(try quoteIdent(table)) (\(try quoteIdentList(columns)))"
    }

    public func tableExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String {
        let exists = """
        EXISTS (
            SELECT 1 FROM \(try quoteIdent(schema)).sqlite_master
            WHERE name = \(quoteLiteral(table))
              AND type IN ('table', 'index', 'view')
          )
        """
        return existsSelect(exists, negate: negate)
    }

    public func columnExistsSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        let exists = """
        EXISTS (
            SELECT 1 FROM pragma_table_info(\(quoteLiteral(table)))
            WHERE name = \(quoteLiteral(column))
          )
        """
        return existsSelect(exists, negate: negate)
    }

    public func constraintExistsSql(_ schema: String, _ table: String, _ name: String, negate: Bool) throws -> String {
        unsupportedProbe("constraints", negate: negate)
    }

    public func primaryKeyExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String {
        let exists = """
        EXISTS (
            SELECT 1 FROM pragma_table_info(\(quoteLiteral(table)))
            WHERE pk > 0
          )
        """
        return existsSelect(exists, negate: negate)
    }

    public func checkConstraintExistsSql(_ schema: String, _ table: String, _ name: String, negate: Bool) throws -> String {
        unsupportedProbe("check constraints", negate: negate)
    }

    public func schemaExistsSql(_ schema: String, negate: Bool) -> String {
        let exists = """
        EXISTS (
            SELECT 1 FROM pragma_database_list
            WHERE name = \(quoteLiteral(schema))
          )
        """
        return existsSelect(exists, negate: negate)
    }

    public func extensionExistsSql(_ name: String, negate: Bool) -> String {
        unsupportedProbe("extensions", negate: negate)
    }

    public func enumTypeExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        unsupportedProbe("enum types", negate: negate)
    }

    public func enumLabelExistsSql(_ schema: String, _ typeName: String, _ value: String, negate: Bool) -> String {
        unsupportedProbe("enum values", negate: negate)
    }

    public func viewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        let exists = """
        EXISTS (
            SELECT 1 FROM \(quoteIdentUnchecked(schema)).sqlite_master
            WHERE name = \(quoteLiteral(name))
              AND type = 'view'
          )
        """
        return existsSelect(exists, negate: negate)
    }

    public func matviewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
        unsupportedProbe("materialized views", negate: negate)
    }

    public func columnDefaultSetSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        let exists = """
        EXISTS (
            SELECT 1 FROM pragma_table_info(\(quoteLiteral(table)))
            WHERE name = \(quoteLiteral(column))
              AND dflt_value IS NOT NULL
          )
        """
        return existsSelect(exists, negate: negate)
    }

    public func columnNotNullSql(_ schema: String, _ table: String, _ column: String, negate: Bool) -> String {
        let exists = """
        EXISTS (
            SELECT 1 FROM pragma_table_info(\(quoteLiteral(table)))
            WHERE name = \(quoteLiteral(column))
              AND "notnull" = 1
          )
        """
        return existsSelect(exists, negate: negate)
    }

    public func createHistoryTableSql(name: String) throws -> String {
        let table = try quoteIdent(name)
        return """
        CREATE TABLE IF NOT EXISTS \(table) (
          id          INTEGER PRIMARY KEY,
          parent_id   INTEGER,
          applied_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          operations  TEXT NOT NULL,
          checksum    TEXT NOT NULL
        )
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func acquireLock(_ db: any DB, key: Int64) async throws {}

    public func releaseLock(_ db: any DB, key: Int64) async throws {}

    private func existsSelect(_ exists: String, negate: Bool) -> String {
        negate ? "SELECT NOT \(exists)" : "SELECT \(exists)"
    }

    private func unsupportedProbe(_ feature: String, negate: Bool) -> String {
        negate ? "SELECT 1" : "SELECT 0"
    }

    private func quoteIdentUnchecked(_ name: String) -> String {
        "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
