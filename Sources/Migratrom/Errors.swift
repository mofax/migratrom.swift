import Foundation

public enum MigratromError: Error, Sendable {
    case config(String)
    case duplicateMigrationId(Int)
    case missingRoot
    case multipleRoots([Int])
    case missingParent(migration: Int, parent: Int)
    case cycleDetected([Int])
    case precheckFailed(operation: String, check: Check)
    case postcheckFailed(operation: String, check: Check)
    case emptyPostcheck(operation: String)
    case migrationFailed(id: Int, cause: any Error)
    case checksumMismatch(id: Int, stored: String, actual: String)
    case checkShape(message: String, rowPreview: String?)
    case unsupported(feature: String, dialect: String)
}

extension MigratromError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .config(let message):
            return message
        case .duplicateMigrationId(let id):
            return "duplicate migration id: \(id)"
        case .missingRoot:
            return "no root migration (parentId === null) in an empty history"
        case .multipleRoots(let rootIds):
            return "multiple root migrations: \(rootIds.map(String.init).joined(separator: ", "))"
        case .missingParent(let migration, let parent):
            return "migration \(migration) references missing parent \(parent)"
        case .cycleDetected(let cycle):
            return "cycle detected in migration graph: \(cycle.map(String.init).joined(separator: " -> "))"
        case .precheckFailed(let operation, let check):
            return "precheck failed for operation \"\(operation)\": \(check.description)"
        case .postcheckFailed(let operation, let check):
            return "postcheck failed for operation \"\(operation)\": \(check.description)"
        case .emptyPostcheck(let operation):
            return "operation \"\(operation)\" has no postcheck"
        case .migrationFailed(let id, let cause):
            let detail = (cause as? LocalizedError)?.errorDescription
                ?? String(describing: cause)
            return "migration \(id) failed: \(detail)"
        case .checksumMismatch(let id, let stored, let actual):
            return "migration \(id) checksum mismatch (applied body was edited): expected \(stored), got \(actual)"
        case .checkShape(let message, let rowPreview):
            if let rowPreview {
                return "\(message) — row: \(rowPreview)"
            }
            return message
        case let .unsupported(feature, dialect):
            return "\(feature) is not supported by the \(dialect) dialect"
        }
    }
}

extension MigratromError: LocalizedError {
    public var errorDescription: String? { description }
}
