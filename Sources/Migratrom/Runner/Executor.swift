public enum OperationResult: Sendable, Equatable {
    case executed
    case skipped
}

public func runOperation(
    _ db: any DB,
    _ op: Operation,
    _ log: any MigrationLogger,
    dryRun: Bool = false
) async throws -> OperationResult {
    if op.postcheck.isEmpty {
        throw MigratromError.emptyPostcheck(operation: op.id)
    }

    let postResults = try await evalChecks(db, operationId: op.id, checks: op.postcheck)
    if postResults.allSatisfy({ $0 }) {
        log.info("skip operation \(op.id) (already applied)")
        return .skipped
    }

    let preResults = try await evalChecks(db, operationId: op.id, checks: op.precheck)
    for (index, check) in op.precheck.enumerated() where !preResults[index] {
        throw MigratromError.precheckFailed(operation: op.id, check: check)
    }

    if dryRun {
        log.info("dry-run would execute operation \(op.id)")
        return .executed
    }

    for step in op.execute {
        try await db.execute(step.sql)
    }

    let verifyResults = try await evalChecks(db, operationId: op.id, checks: op.postcheck)
    for (index, check) in op.postcheck.enumerated() where !verifyResults[index] {
        throw MigratromError.postcheckFailed(operation: op.id, check: check)
    }

    log.info("executed operation \(op.id)")
    return .executed
}

private func evalChecks(
    _ db: any DB,
    operationId: String,
    checks: [Check]
) async throws -> [Bool] {
    var results: [Bool] = []
    results.reserveCapacity(checks.count)
    for check in checks {
        do {
            results.append(try await db.queryBool(check.sql))
        } catch let error as MigratromError {
            if case .checkShape(let message, let rowPreview) = error {
                throw MigratromError.checkShape(
                    message: "\(message) (operation \(operationId), check: \(check.description))",
                    rowPreview: rowPreview
                )
            }
            throw error
        }
    }
    return results
}
