import Crypto
import Foundation

private struct DryRunRollback: Error, Sendable {
    let skippedOps: [String]
}

/// Stable `pg_advisory_lock` key for a history table name: first eight bytes of SHA-256(name) as big-endian `Int64`.
public func advisoryLockKey(forHistoryTable name: String) -> Int64 {
    let digest = Array(SHA256.hash(data: Data(name.utf8)))
    let bytes = digest.prefix(8)
    var value: UInt64 = 0
    for byte in bytes {
        value = (value << 8) | UInt64(byte)
    }
    return Int64(bitPattern: value)
}

public func applyMigrations(
    _ migrations: [Migration],
    db: any DB,
    options: ApplyOptions
) async throws -> ApplyResult {
    if options.advisoryLock && options.dialect.capabilities.advisoryLocks {
        let key = advisoryLockKey(forHistoryTable: options.historyTable)
        return try await withAdvisoryLock(db: db, dialect: options.dialect, key: key) {
            try await applyMigrationsUnlocked(migrations, db: db, options: options)
        }
    }
    return try await applyMigrationsUnlocked(migrations, db: db, options: options)
}

private func withAdvisoryLock<T: Sendable>(
    db: any DB,
    dialect: any SQLDialect,
    key: Int64,
    _ body: @Sendable () async throws -> T
) async throws -> T {
    try await dialect.acquireLock(db, key: key)
    do {
        let result = try await body()
        try await dialect.releaseLock(db, key: key)
        return result
    } catch {
        try? await dialect.releaseLock(db, key: key)
        throw error
    }
}

private func applyMigrationsUnlocked(
    _ migrations: [Migration],
    db: any DB,
    options: ApplyOptions
) async throws -> ApplyResult {
    let historyTable = options.historyTable
    let logger = options.logger
    let dryRun = options.dryRun
    let dialect = options.dialect

    try await ensureHistoryTable(db, name: historyTable, dialect: dialect)
    let appliedIds = try await readAppliedIds(db, name: historyTable, dialect: dialect)
    let storedRecords = try await readAppliedRecords(db, name: historyTable, dialect: dialect)

    for migration in migrations where appliedIds.contains(migration.id) {
        guard let stored = storedRecords[migration.id] else { continue }
        try verifyChecksum(stored.checksum, against: migration.operations, migrationId: migration.id)
    }

    let pending = try planOrder(migrations, appliedIds: appliedIds)
    var applied: [Int] = []
    var skippedOps: [String] = []

    for migration in pending {
        logger.info("migration \(migration.id)", metadata: dryRun ? "{\"dryRun\":true}" : nil)
        do {
            let hasOutside = migration.operations.contains(where: \.outsideTransaction)

            if dryRun {
                if hasOutside {
                    skippedOps.append(contentsOf: try await runMigrationOps(
                        migration.operations,
                        db: db,
                        logger: logger,
                        dryRun: true,
                        onOp: { op in logger.info(String(reflecting: op)) },
                        segmentedTx: true,
                        dialect: dialect
                    ))
                } else {
                    do {
                        try await db.withTransaction {
                            let batchSkipped = try await runMigrationOps(
                                migration.operations,
                                db: db,
                                logger: logger,
                                dryRun: true,
                                onOp: { op in logger.info(String(reflecting: op)) },
                                dialect: dialect
                            )
                            throw DryRunRollback(skippedOps: batchSkipped)
                        }
                    } catch let rollback as DryRunRollback {
                        skippedOps.append(contentsOf: rollback.skippedOps)
                    }
                }
                continue
            }

            if hasOutside {
                skippedOps.append(contentsOf: try await runMigrationOps(
                    migration.operations,
                    db: db,
                    logger: logger,
                    recordHistory: (table: historyTable, migration: migration),
                    dialect: dialect
                ))
            } else {
                let batchSkipped = try await db.withTransaction {
                    let batchSkipped = try await runMigrationOps(
                        migration.operations,
                        db: db,
                        logger: logger,
                        dialect: dialect
                    )
                    try await recordMigration(db, name: historyTable, migration: migration, dialect: dialect)
                    return batchSkipped
                }
                skippedOps.append(contentsOf: batchSkipped)
            }
            applied.append(migration.id)
        } catch {
            throw MigratromError.migrationFailed(id: migration.id, cause: error)
        }
    }

    return ApplyResult(applied: applied, skippedOps: skippedOps)
}

private func runMigrationOps(
    _ operations: [Operation],
    db: any DB,
    logger: any MigrationLogger,
    dryRun: Bool = false,
    onOp: (@Sendable (Operation) -> Void)? = nil,
    segmentedTx: Bool = false,
    recordHistory: (table: String, migration: Migration)? = nil,
    dialect: any SQLDialect
) async throws -> [String] {
    let segmented = recordHistory != nil || segmentedTx
    var transactional: [Operation] = []
    var skippedOps: [String] = []

    func flushTransactional(final: Bool) async throws {
        guard !transactional.isEmpty else { return }
        let batch = transactional
        transactional.removeAll(keepingCapacity: true)

        let runBatch: @Sendable () async throws -> [String] = {
            var batchSkipped: [String] = []
            for op in batch {
                onOp?(op)
                let result = try await runOperation(db, op, logger, dryRun: dryRun)
                if result == .skipped {
                    batchSkipped.append(op.id)
                }
            }
            if final, let recordHistory {
                try await recordMigration(db, name: recordHistory.table, migration: recordHistory.migration, dialect: dialect)
            }
            return batchSkipped
        }

        if segmented {
            do {
                let batchSkipped = try await db.withTransaction {
                    let batchSkipped = try await runBatch()
                    if dryRun {
                        throw DryRunRollback(skippedOps: batchSkipped)
                    }
                    return batchSkipped
                }
                skippedOps.append(contentsOf: batchSkipped)
            } catch let rollback as DryRunRollback {
                skippedOps.append(contentsOf: rollback.skippedOps)
            }
            return
        }
        skippedOps.append(contentsOf: try await runBatch())
    }

    for op in operations {
        if op.outsideTransaction {
            try await flushTransactional(final: false)
            onOp?(op)
            let result = try await runOperation(db, op, logger, dryRun: dryRun)
            if result == .skipped {
                skippedOps.append(op.id)
            }
            continue
        }
        transactional.append(op)
    }
    try await flushTransactional(final: true)
    return skippedOps
}
