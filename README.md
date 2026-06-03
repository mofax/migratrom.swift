# migratrom.swift

Declarative, self-verifying, idempotent SQL migrations for Swift — PostgreSQL and SQLite out of the box.

Migrations are plain Swift values, not SQL files with hand-written `up`/`down` scripts. Each schema change is an `Operation` that runs **precheck → execute → postcheck**. Operations are idempotent: if the postcheck already passes, the operation is skipped. Applied migrations are recorded in a history table with a **checksum**, so editing an already-applied migration is rejected rather than silently diverging.

The core engine is **dialect-agnostic**: SQL generation, catalog probes, and locking live behind an `SQLDialect`. Two dialects ship built in — `PostgresDialect` and `SQLiteDialect` — and you always pass the dialect explicitly (there is no default).

## Table of contents

- [migratrom.swift](#migratromswift)
  - [Table of contents](#table-of-contents)
  - [Why](#why)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Quick start](#quick-start)
  - [Core concepts](#core-concepts)
    - [Migration](#migration)
    - [Operation](#operation)
    - [precheck → execute → postcheck](#precheck--execute--postcheck)
    - [Idempotency and checksums](#idempotency-and-checksums)
    - [History table](#history-table)
    - [ApplyResult](#applyresult)
  - [Operation builders](#operation-builders)
    - [Supporting types](#supporting-types)
    - [Capability checks](#capability-checks)
  - [Custom operations](#custom-operations)
  - [Applying migrations](#applying-migrations)
  - [Apply options](#apply-options)
  - [Transactions and `outsideTransaction`](#transactions-and-outsidetransaction)
  - [Dry runs](#dry-runs)
  - [Error handling](#error-handling)
  - [Logging](#logging)
  - [Extending: dialects and adapters](#extending-dialects-and-adapters)
    - [Using SQLite](#using-sqlite)
    - [Custom database adapter](#custom-database-adapter)
    - [Custom dialect](#custom-dialect)
  - [Development](#development)

## Why

- **No string-template migration files.** Schema changes are typed Swift values, refactored and reviewed like any other code.
- **Idempotent by construction.** Re-running an already-applied operation is a no-op. Each operation carries the checks that prove whether it still needs to run.
- **Tamper-evident history.** A SHA-256 checksum of each migration's operations is stored on apply. Editing the body of an applied migration produces a `checksumMismatch` instead of drifting.
- **DAG ordering.** Migrations form a parent/child graph; the engine validates the graph (single root, no cycles, no missing parents) and applies pending migrations in dependency order.
- **Driver-agnostic core.** The `Migratrom` module imports no database driver. `MigratromPostgresNIO` wires it to PostgresNIO and `MigratromSQLite` wires it to SQift; you can write your own adapter against the `DB` protocol.
- **Multi-dialect.** SQL generation, catalog probes, history DDL, and locking live behind the `SQLDialect` protocol. `PostgresDialect` and `SQLiteDialect` ship built in; targeting another database is "implement `SQLDialect`". Builders consult per-dialect capability flags and refuse (rather than emit invalid SQL) anything the active dialect cannot express.

## Requirements

- Swift 6.2+ (the package builds in Swift 6 language mode)
- macOS 26+ / iOS 26+
- One of:
  - PostgreSQL (any version supported by PostgresNIO 1.21+), via `MigratromPostgresNIO`
  - SQLite, via `MigratromSQLite` (built on [SQift](https://github.com/nike-inc/SQift) 5.1+)
  - any other database, by implementing the `DB` and `SQLDialect` protocols yourself

## Installation

Add the package to your `Package.swift` and depend on `Migratrom` plus the adapter for your database:

```swift
dependencies: [
    .package(url: "https://github.com/mofax/migratrom.swift", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "Migratrom", package: "migratrom.swift"),
            // Postgres:
            .product(name: "MigratromPostgresNIO", package: "migratrom.swift"),
            // …or SQLite:
            .product(name: "MigratromSQLite", package: "migratrom.swift"),
        ]
    ),
]
```

| Product | Contents |
|---------|----------|
| `Migratrom` | Core types, operation builders, the runner, DAG planner, checksums, the built-in `PostgresDialect`/`SQLiteDialect`, and the `DB`/`SQLDialect` protocols. No driver dependency. |
| `MigratromPostgresNIO` | `applyMigrations(_:on:options:)` overloads for `PostgresClient` / `PostgresConnection`, plus the PostgresNIO `DB` adapter. |
| `MigratromSQLite` | `applyMigrations(_:on:options:)` overload for a SQift `Connection`, plus the `SQiftDB` adapter. |

## Quick start

```swift
import Migratrom
import MigratromPostgresNIO
import PostgresNIO

let config = PostgresClient.Configuration(
    host: "localhost",
    port: 5432,
    username: "postgres",
    password: "pw",
    database: "postgres",
    tls: .disable
)
let client = PostgresClient(configuration: config)

// The dialect is always explicit — there is no default. Pass it to every builder and to ApplyOptions.
let dialect = PostgresDialect()

try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { await client.run() }
    defer { group.cancelAll() }

    let m1 = Migration(
        id: 1,
        parentId: nil,
        operations: [
            try createTable(
                "public", "users",
                [
                    ColumnDef(name: "id", typeSql: "SERIAL"),
                    ColumnDef(name: "email", typeSql: "text"),
                ],
                primaryKey: PrimaryKey(columns: ["id"]),
                dialect: dialect
            ),
            try addUnique("public", "users", "users_email_key", ["email"], dialect: dialect),
        ]
    )
    let m2 = Migration(
        id: 2,
        parentId: 1,
        operations: [
            try addColumn("public", "users", ColumnDef(name: "name", typeSql: "text", nullable: true), dialect: dialect),
        ]
    )

    let result = try await applyMigrations([m1, m2], on: client, options: ApplyOptions(dialect: dialect))
    print("Applied: \(result.applied)")        // [1, 2] on first run, [] on re-run
    print("Skipped ops: \(result.skippedOps)")  // ids of operations whose postcheck already held
}
```

A runnable version lives in [Examples/BasicExample/](Examples/BasicExample/):

```bash
DATABASE_URL=postgres://postgres:pw@localhost:5432/postgres swift run BasicExample
```

## Core concepts

### Migration

A `Migration` is an `id`, an optional `parentId`, and an ordered list of operations:

```swift
public struct Migration {
    public var id: Int
    public var parentId: Int?
    public var operations: [Operation]
}
```

Migrations form a **DAG** keyed by `id`. The set you pass to `applyMigrations` must satisfy:

- Exactly one root (`parentId == nil`) when history is empty; no *new* roots once anything has been applied.
- Every `parentId` resolves to a migration in the batch or already in history.
- No duplicate ids and no cycles.

The planner ([`planOrder`](Sources/Migratrom/Graph/DAG.swift)) sorts pending migrations by depth, then by `id`, and skips ids already present in the history table. Violations throw a [`MigratromError`](#error-handling) before any DDL runs.

### Operation

An `Operation` is a single named, self-verifying unit of change:

```swift
public struct Operation {
    public var id: String          // stable logical id, e.g. "table.users"
    public var label: String       // human-readable, e.g. Create table "users"
    public var precheck: [Check]   // boolean probes run before execute
    public var execute: [ExecuteStep]  // the side-effecting DDL/DML
    public var postcheck: [Check]  // boolean probes that prove the result
    public var outsideTransaction: Bool
}
```

A `Check` is a boolean SQL probe (must return exactly one row, one column, boolean). An `ExecuteStep` is a side-effecting statement. You rarely construct these by hand — the [operation builders](#operation-builders) generate them with correct pre/postchecks.

### precheck → execute → postcheck

For each operation the runner:

1. Runs the **postcheck** first. If it already passes, the operation is **skipped** (its `id` is added to `ApplyResult.skippedOps`) — this is what makes re-running safe.
2. Otherwise runs the **precheck**. A failing precheck throws `precheckFailed` (the world is not in the expected starting state).
3. Runs the **execute** steps.
4. Runs the **postcheck** again to confirm the change took effect; a failure throws `postcheckFailed`.

An operation with an empty postcheck is rejected (`emptyPostcheck`) — every operation must be able to prove itself.

### Idempotency and checksums

Because skip-on-postcheck is decided per operation, applying the same batch twice is a no-op. To guard against *silent edits*, the checksum of each migration's operations is stored in the history table on apply. On the next run the stored checksum is compared against the recomputed one; a mismatch throws `checksumMismatch`. The canonical encoding and hash are described in [docs/CHECKSUM_FORMAT.md](docs/CHECKSUM_FORMAT.md).

### History table

Applied migrations are recorded in a history table (default `__migratron_history__`, configurable via [`ApplyOptions`](#apply-options)). It stores each migration's `id`, `parent_id`, `checksum`, and the canonical-encoded `operations`. The table is created automatically on first apply.

### ApplyResult

```swift
public struct ApplyResult {
    public var applied: [Int]       // migration ids applied this run
    public var skippedOps: [String] // operation ids skipped because their postcheck already held
}
```

## Operation builders

All builders live in `Migratrom`, are `throws` (they validate identifiers and dialect capabilities up front), and return an `Operation` with pre/postchecks already wired. Each takes a **required** trailing `dialect:` parameter (e.g. `dialect: PostgresDialect()` or `dialect: SQLiteDialect()`) — there is no default, so the dialect is always chosen explicitly. The signatures below omit it for brevity.

| Builder | Signature (`dialect:` omitted) | Operation id |
|---------|----------------------------------------|--------------|
| `createTable` | `(_ schema:, _ table:, _ columns: [ColumnDef], primaryKey: PrimaryKey?)` | `table.<table>` |
| `addColumn` | `(_ schema:, _ table:, _ col: ColumnDef)` | `column.<table>.<col>` |
| `renameColumn` | `(_ schema:, _ table:, _ from:, _ to:)` | `rename_column.<table>.<from>_to_<to>` |
| `renameTable` | `(_ schema:, _ from:, _ to:)` | `rename_table.<from>_to_<to>` |
| `setColumnDefault` | `(_ schema:, _ table:, _ column:, _ defaultSql:)` | `column_default.<table>.<col>` |
| `setColumnNotNull` | `(_ schema:, _ table:, _ column:)` | `column_not_null.<table>.<col>` |
| `addPrimaryKey` | `(_ schema:, _ table:, _ constraintName:, _ columns: [String])` | `pk.<table>.<name>` |
| `addUnique` | `(_ schema:, _ table:, _ constraintName:, _ columns: [String])` | `unique.<table>.<name>` |
| `addForeignKey` | `(_ schema:, _ table:, _ spec: ForeignKeySpec)` | `fk.<table>.<name>` |
| `addCheck` | `(_ schema:, _ table:, _ constraintName:, _ checkSql:)` | `check.<table>.<name>` |
| `createIndex` | `(_ schema:, _ table:, _ indexName:, _ columns: [String], options: CreateIndexOptions)` | `index.<table>.<name>` |
| `createSchema` | `(_ name:)` | `schema.<name>` |
| `createSequence` | `(_ schema:, _ name:)` | `sequence.<name>` |
| `createView` | `(_ schema:, _ name:, _ selectSql:)` | `view.<name>` |
| `createMaterializedView` | `(_ schema:, _ name:, _ selectSql:)` | `matview.<name>` |
| `createType` | `(_ schema:, _ name:, _ labels: [String])` | `type.<name>` |
| `addEnumValue` | `(_ schema:, _ typeName:, _ value:, options: AddEnumValueOptions)` | `enum.<type>.<value>` |
| `createExtension` | `(_ name:, options: CreateExtensionOptions)` | `extension.<name>` |
| `rawSql` | `(_ input: RawSqlInput)` | caller-supplied or derived from `label` |

### Supporting types

```swift
ColumnDef(name: "email", typeSql: "text", nullable: false, defaultSql: "DEFAULT (now())")
PrimaryKey(columns: ["id"])

ForeignKeySpec(
    name: "posts_author_id_fkey",
    columns: ["author_id"],
    references: ForeignKeyReference(table: "users", columns: ["id"]),
    onDelete: .cascade,   // ReferentialAction: .cascade/.restrict/.setNull/.noAction/.setDefault
    onUpdate: nil
)

CreateIndexOptions(concurrently: true)   // emits CREATE INDEX CONCURRENTLY (see below)
CreateExtensionOptions(schema: "public") // CREATE EXTENSION ... WITH SCHEMA
AddEnumValueOptions(before: "shipped")   // ADD VALUE ... BEFORE 'shipped'
```

`ColumnDef.typeSql` and `defaultSql` are emitted verbatim — they are your escape hatch for any column type or default expression. `nullable` defaults to `false` (column rendered `NOT NULL`).

### Capability checks

A dialect advertises optional features through `DialectCapabilities`. Builders consult these flags up front and throw `unsupported(feature:dialect:)` rather than emitting SQL the dialect can't run. `PostgresDialect` enables every capability; `SQLiteDialect` enables only the base table/column/index/view set.

| Capability | Gated builder(s) | Postgres | SQLite |
|------------|------------------|:--------:|:------:|
| `enumTypes` | `createType`, `addEnumValue` | ✓ | — |
| `sequences` | `createSequence` | ✓ | — |
| `materializedViews` | `createMaterializedView` | ✓ | — |
| `extensions` | `createExtension` | ✓ | — |
| `concurrentIndexes` | `createIndex(concurrently: true)` | ✓ | — |
| `schemas` | `createSchema` | ✓ | — |
| `advisoryLocks` | (advisory lock during apply — skipped when unsupported) | ✓ | — |
| `addCheckConstraints` | `addCheck` | ✓ | — |
| `addPrimaryKeyConstraints` | `addPrimaryKey` | ✓ | — |
| `addUniqueConstraints` | `addUnique` | ✓ | — |
| `addForeignKeys` | `addForeignKey` | ✓ | — |
| `alterColumnDefault` | `setColumnDefault` | ✓ | — |
| `alterColumnNotNull` | `setColumnNotNull` | ✓ | — |

Builders with no capability gate work on every dialect. On `SQLiteDialect` that leaves the usable set as `createTable`, `addColumn`, `renameColumn`, `renameTable`, `createIndex` (non-concurrent), `createView`, and `rawSql` — enough for the common SQLite schema (it has no separate `ALTER … ADD CONSTRAINT`, sequences, enums, or extensions). For anything else on SQLite, fold it into the `createTable` column definitions or drop down to `rawSql`.

## Custom operations

When no builder fits, drop down to `rawSql`. You supply the execute steps and, ideally, your own pre/postchecks so the operation stays idempotent and self-verifying:

```swift
let op = try rawSql(RawSqlInput(
    label: "Backfill users.status",
    precheck: [PartialCheck(sql: "SELECT EXISTS (SELECT 1 FROM users WHERE status IS NULL)")],
    execute: [PartialExecuteStep(description: "set default status",
                                 sql: "UPDATE users SET status = 'active' WHERE status IS NULL")],
    postcheck: [PartialCheck(sql: "SELECT NOT EXISTS (SELECT 1 FROM users WHERE status IS NULL)")],
    id: "backfill.users.status"
))
```

For ad-hoc `Check` and `ExecuteStep` values, the `check(_:_:)` and `step(_:_:)` helpers build them from `(description, sql)`.

## Applying migrations

`options` is **required** on every overload — it carries the dialect, which is never defaulted.

`MigratromPostgresNIO` provides two convenience overloads:

```swift
// Checks out a connection from a running PostgresClient pool.
func applyMigrations(_ migrations: [Migration], on client: PostgresClient,
                     options: ApplyOptions) async throws -> ApplyResult

// Uses an existing connection directly.
func applyMigrations(_ migrations: [Migration], on connection: PostgresConnection,
                     options: ApplyOptions) async throws -> ApplyResult
```

`MigratromSQLite` provides one for a SQift `Connection`:

```swift
func applyMigrations(_ migrations: [Migration], on connection: Connection,
                     options: ApplyOptions) async throws -> ApplyResult
```

The core (driver-agnostic) entry point in `Migratrom` takes any `DB`:

```swift
func applyMigrations(_ migrations: [Migration], db: any DB,
                     options: ApplyOptions) async throws -> ApplyResult
```

## Apply options

`ApplyOptions` controls runtime behavior:

| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `historyTable` | `String` | `__migratron_history__` | Table where applied migrations are recorded. |
| `dryRun` | `Bool` | `false` | Evaluate checks and roll everything back without writing DDL or history. |
| `advisoryLock` | `Bool` | `true` | Serialize concurrent applies via `pg_advisory_lock` keyed on the history table name (when the dialect supports advisory locks). |
| `logger` | `any MigrationLogger` | `ConsoleLogger()` | Progress logging. |
| `dialect` | `any SQLDialect` | **required** (no default) | SQL generation and catalog probes — e.g. `PostgresDialect()` or `SQLiteDialect()`. |

```swift
let result = try await applyMigrations(
    migrations,
    on: client,
    options: ApplyOptions(historyTable: "schema_migrations", dryRun: true, dialect: PostgresDialect())
)
```

The advisory-lock key is the first eight bytes of `SHA-256(historyTable)` as a big-endian `Int64` ([`advisoryLockKey(forHistoryTable:)`](Sources/Migratrom/Runner/Apply.swift)), so concurrent processes targeting the same history table won't apply simultaneously.

## Transactions and `outsideTransaction`

Each migration runs in a single transaction by default: all its operations and the history insert commit together, or none do. Operations marked `outsideTransaction: true` cannot run inside a transaction — the runner segments the migration so those operations execute on their own, and transactional operations around them are batched separately.

The common case is a concurrent index:

```swift
try createIndex("public", "users", "users_email_idx", ["email"],
                options: CreateIndexOptions(concurrently: true),
                dialect: PostgresDialect())
```

`createIndex(concurrently: true)` sets `outsideTransaction` automatically because `CREATE INDEX CONCURRENTLY` is illegal inside a transaction block. (Concurrent indexes are Postgres-only — `SQLiteDialect` lacks the `concurrentIndexes` capability and rejects them.)

## Dry runs

With `dryRun: true`, every operation's checks are evaluated and DDL is executed inside a transaction that is **always rolled back** — nothing is committed and no history is written. The returned `ApplyResult.skippedOps` reflects which operations *would* be skipped. Useful for validating a batch against a real database without changing it.

## Error handling

All failures surface as `MigratromError`, which conforms to `CustomStringConvertible` and `LocalizedError`:

| Case | Meaning |
|------|---------|
| `config(String)` | Invalid configuration. |
| `duplicateMigrationId(Int)` | Two migrations share an `id`. |
| `missingRoot` | Empty history but no `parentId == nil` migration. |
| `multipleRoots([Int])` | More than one root (or a new root after history exists). |
| `missingParent(migration:parent:)` | A `parentId` resolves to neither the batch nor history. |
| `cycleDetected([Int])` | The migration graph contains a cycle. |
| `precheckFailed(operation:check:)` | A precheck returned false. |
| `postcheckFailed(operation:check:)` | Execute ran but the postcheck still failed. |
| `emptyPostcheck(operation:)` | An operation has no postcheck. |
| `migrationFailed(id:cause:)` | A migration threw while applying; `cause` is the underlying error. |
| `checksumMismatch(id:stored:actual:)` | The body of an already-applied migration was edited. |
| `checkShape(message:rowPreview:)` | A check query didn't return exactly one boolean row/column. |
| `unsupported(feature:dialect:)` | The dialect lacks a capability the operation needs. |

Graph and checksum validation happen **before** any DDL runs, so an invalid batch fails fast without partial application.

## Logging

Implement `MigrationLogger` to route progress somewhere other than the console:

```swift
public protocol MigrationLogger: Sendable {
    func info(_ message: String, metadata: String?)
    func warn(_ message: String, metadata: String?)
    func error(_ message: String, metadata: String?)
}
```

`ConsoleLogger` (the default) prints `info` to stdout and `warn`/`error` to stderr. Convenience overloads without `metadata` are provided by a protocol extension.

## Extending: dialects and adapters

### Using SQLite

`MigratromSQLite` ships the `SQiftDB` adapter (built on [SQift](https://github.com/nike-inc/SQift)) and an `applyMigrations(_:on:options:)` overload for a SQift `Connection`. Pair it with `SQLiteDialect()`:

```swift
import Migratrom
import MigratromSQLite
import SQift

let connection = try Connection(storageLocation: .onDisk("app.sqlite"))
let dialect = SQLiteDialect()

let migration = Migration(
    id: 1,
    parentId: nil,
    operations: [
        try createTable(
            "main", "users",
            [
                ColumnDef(name: "id", typeSql: "INTEGER"),
                ColumnDef(name: "email", typeSql: "TEXT"),
            ],
            primaryKey: PrimaryKey(columns: ["id"]),
            dialect: dialect
        ),
        try createIndex("main", "users", "users_email_idx", ["email"], dialect: dialect),
    ]
)

let result = try await applyMigrations([migration], on: connection,
                                       options: ApplyOptions(dialect: dialect))
```

Only the capability-free builders apply on SQLite — see the [capability matrix](#capability-checks). Using a different SQLite driver? Implement the `DB` protocol against it and keep `SQLiteDialect` for SQL generation.

### Custom database adapter

The core depends only on the `DB` protocol — implement it to target a driver other than the bundled ones:

```swift
public protocol DB: Sendable {
    func queryBool(_ sql: String) async throws -> Bool       // exactly one row/column/boolean
    func execute(_ sql: String) async throws
    func queryRows(_ sql: String) async throws -> [any DBRow]
    func withTransaction<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T
}
```

Then call the core `applyMigrations(_:db:options:)` with your adapter. `PostgresNIODB` (PostgresNIO) and `SQiftDB` (SQift) are the reference implementations.

### Custom dialect

`SQLDialect` is the seam for other databases. It declares `name`, `capabilities` (a `DialectCapabilities` set of feature flags), identifier/literal quoting, column rendering, statement rendering that varies by dialect (e.g. `createIndexSql`), the catalog-probe SQL each builder uses, history-table DDL, and advisory-lock acquire/release. `PostgresDialect` and `SQLiteDialect` are the built-in implementations; pass any dialect via `ApplyOptions.dialect` and the per-builder `dialect:` argument (always explicit — there is no default).

## Development

Start a throwaway Postgres:

```bash
docker run --rm -e POSTGRES_PASSWORD=pw -p 5432:5432 -d postgres:16
```

Run the unit tests (no database required):

```bash
swift test
```

This includes the SQLite suite, which runs end-to-end against a temporary on-disk SQLite file via SQift — no Docker or external database needed.

Run the Postgres integration tests against a real database:

```bash
MIGRATROM_TEST_DATABASE_URL=postgres://postgres:pw@localhost:5432/postgres swift test
```

Postgres integration tests are skipped when `MIGRATROM_TEST_DATABASE_URL` is unset. The helper script starts Postgres via Docker when the URL is not provided:

```bash
./scripts/run-integration-tests.sh
```
