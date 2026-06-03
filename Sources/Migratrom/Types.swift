/// A boolean-returning SQL probe. Must yield one row / one column / boolean.
public struct Check: Sendable, Equatable {
    /// Human-readable intent, e.g. `ensure table "user" does not exist`.
    public var description: String
    public var sql: String

    public init(description: String, sql: String) {
        self.description = description
        self.sql = sql
    }
}

/// A side-effecting DDL/DML statement.
public struct ExecuteStep: Sendable, Equatable {
    public var description: String
    public var sql: String

    public init(description: String, sql: String) {
        self.description = description
        self.sql = sql
    }
}

/// A single, named, self-verifying unit of change.
public struct Operation: Sendable, Equatable {
    /// Stable logical id, e.g. `"table.user"`, `"fk.post.post_authorId_fkey"`.
    public var id: String
    /// Human-readable label, e.g. `Create table "user"`.
    public var label: String
    public var precheck: [Check]
    public var execute: [ExecuteStep]
    public var postcheck: [Check]
    /// When true, run outside the per-migration transaction (e.g. `CREATE INDEX CONCURRENTLY`).
    public var outsideTransaction: Bool

    public init(
        id: String,
        label: String,
        precheck: [Check] = [],
        execute: [ExecuteStep] = [],
        postcheck: [Check] = [],
        outsideTransaction: Bool = false
    ) {
        self.id = id
        self.label = label
        self.precheck = precheck
        self.execute = execute
        self.postcheck = postcheck
        self.outsideTransaction = outsideTransaction
    }
}

public struct ColumnDef: Sendable, Equatable {
    public var name: String
    /// Raw SQL type, emitted verbatim (e.g. `"text"`).
    public var typeSql: String
    /// Defaults to `false` (column rendered `NOT NULL`).
    public var nullable: Bool
    /// Full default clause including `DEFAULT`, e.g. `"DEFAULT (now())"`.
    public var defaultSql: String?

    public init(
        name: String,
        typeSql: String,
        nullable: Bool = false,
        defaultSql: String? = nil
    ) {
        self.name = name
        self.typeSql = typeSql
        self.nullable = nullable
        self.defaultSql = defaultSql
    }
}

public struct PrimaryKey: Sendable, Equatable {
    public var columns: [String]

    public init(columns: [String]) {
        self.columns = columns
    }
}

public enum ReferentialAction: String, Sendable, Equatable {
    case cascade
    case restrict
    case setNull
    case noAction
    case setDefault

    public var sql: String {
        switch self {
        case .cascade: "CASCADE"
        case .restrict: "RESTRICT"
        case .setNull: "SET NULL"
        case .noAction: "NO ACTION"
        case .setDefault: "SET DEFAULT"
        }
    }
}

public struct ForeignKeyReference: Sendable, Equatable {
    public var table: String
    public var columns: [String]

    public init(table: String, columns: [String]) {
        self.table = table
        self.columns = columns
    }
}

public struct ForeignKeySpec: Sendable, Equatable {
    public var name: String
    public var columns: [String]
    public var references: ForeignKeyReference
    public var onDelete: ReferentialAction?
    public var onUpdate: ReferentialAction?

    public init(
        name: String,
        columns: [String],
        references: ForeignKeyReference,
        onDelete: ReferentialAction? = nil,
        onUpdate: ReferentialAction? = nil
    ) {
        self.name = name
        self.columns = columns
        self.references = references
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
}

public struct Migration: Sendable, Equatable {
    public var id: Int
    public var parentId: Int?
    public var operations: [Operation]

    public init(id: Int, parentId: Int?, operations: [Operation]) {
        self.id = id
        self.parentId = parentId
        self.operations = operations
    }
}

public struct ApplyResult: Sendable, Equatable {
    public var applied: [Int]
    public var skippedOps: [String]

    public init(applied: [Int] = [], skippedOps: [String] = []) {
        self.applied = applied
        self.skippedOps = skippedOps
    }
}

public struct ApplyOptions: Sendable {
    public static let defaultHistoryTable = "__migratron_history__"

    public var historyTable: String
    public var dryRun: Bool
    public var logger: any MigrationLogger
    public var advisoryLock: Bool
    public var dialect: any SQLDialect

    public init(
        historyTable: String = Self.defaultHistoryTable,
        dryRun: Bool = false,
        logger: any MigrationLogger = ConsoleLogger(),
        advisoryLock: Bool = true,
        dialect: any SQLDialect
    ) {
        self.historyTable = historyTable
        self.dryRun = dryRun
        self.logger = logger
        self.advisoryLock = advisoryLock
        self.dialect = dialect
    }
}

/// Options for `createIndex` builders (mirrors TS `CreateIndexOptions`).
public struct CreateIndexOptions: Sendable, Equatable {
    /// Emit `CREATE INDEX CONCURRENTLY` and run outside the migration transaction.
    public var concurrently: Bool

    public init(concurrently: Bool = false) {
        self.concurrently = concurrently
    }
}

/// Options for `createExtension` builders (mirrors TS `CreateExtensionOptions`).
public struct CreateExtensionOptions: Sendable, Equatable {
    /// Install the extension into this schema (`CREATE EXTENSION ... WITH SCHEMA`).
    public var schema: String?

    public init(schema: String? = nil) {
        self.schema = schema
    }
}

/// Options for `addEnumValue` builders (mirrors TS `AddEnumValueOptions`).
public struct AddEnumValueOptions: Sendable, Equatable {
    /// Insert the new label before this existing enum value (`ADD VALUE ... BEFORE`).
    public var before: String?

    public init(before: String? = nil) {
        self.before = before
    }
}
