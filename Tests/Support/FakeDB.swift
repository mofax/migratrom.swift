import Foundation
@testable import Migratrom

struct FakeRow: DBRow, Sendable {
    var id: Int?
    var checksum: String?
    var operations: String?

    func int(at index: Int) throws -> Int? {
        switch index {
        case 0: id
        default: nil
        }
    }

    func string(at index: Int) throws -> String? {
        switch index {
        case 1: checksum
        case 2: operations
        default: nil
        }
    }
}

/// In-memory `DB` for unit tests (mirrors `fake.ts`).
final class FakeDB: DB, @unchecked Sendable {
    @TaskLocal private static var inTransaction = false

    private(set) var executed: [String] = []
    private var boolResults: [String: Bool] = [:]
    private var boolSequences: [String: [Bool]] = [:]
    private var boolSequenceIndexes: [String: Int] = [:]
    private var history: [Int: AppliedMigrationRecord] = [:]
    private var transactionRolledBack = false

    func setBool(_ sql: String, _ value: Bool) {
        boolResults[sql] = value
    }

    func setBoolSequence(_ sql: String, _ values: [Bool]) {
        boolSequences[sql] = values
        boolSequenceIndexes[sql] = 0
    }

    func seedHistory(_ records: [Int: AppliedMigrationRecord]) {
        history = records
    }

    var historyRecords: [Int: AppliedMigrationRecord] {
        history
    }

    func wasRolledBack() -> Bool {
        transactionRolledBack
    }

    func queryBool(_ sql: String) async throws -> Bool {
        if let sequence = boolSequences[sql] {
            let index = boolSequenceIndexes[sql, default: 0]
            if index < sequence.count {
                boolSequenceIndexes[sql] = index + 1
                return sequence[index]
            }
        }
        return boolResults[sql] ?? false
    }

    func execute(_ sql: String) async throws {
        executed.append(sql)
        if let insert = Self.parseHistoryInsert(sql) {
            history[insert.id] = AppliedMigrationRecord(
                checksum: insert.checksum,
                operations: insert.operations
            )
        }
    }

    func queryRows(_ sql: String) async throws -> [any DBRow] {
        if sql.contains("checksum") {
            return history.keys.sorted().map { id in
                let record = history[id]!
                return FakeRow(id: id, checksum: record.checksum, operations: record.operations)
            }
        }
        return history.keys.sorted().map { FakeRow(id: $0) }
    }

    func withTransaction<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        if Self.inTransaction {
            return try await body()
        }
        let snapshotExecuted = executed
        let snapshotHistory = history
        transactionRolledBack = false
        do {
            return try await Self.$inTransaction.withValue(true) {
                try await body()
            }
        } catch {
            transactionRolledBack = true
            executed = snapshotExecuted
            history = snapshotHistory
            throw error
        }
    }

    private static func parseHistoryInsert(_ sql: String) -> (id: Int, checksum: String, operations: String)? {
        guard sql.hasPrefix("INSERT INTO"), sql.contains("checksum") else { return nil }
        guard let valuesStart = sql.range(of: "VALUES (") else { return nil }
        let tail = sql[valuesStart.upperBound...]
        guard tail.hasSuffix(")") else { return nil }
        let values = tail.dropLast()
        guard let parsed = parseSQLValues(String(values)), parsed.count >= 4 else { return nil }
        guard let id = Int(parsed[0]) else { return nil }
        let checksum = unquoteSQLLiteral(parsed[2])
        let operations = unquoteSQLLiteral(parsed[3])
        return (id, checksum, operations)
    }

    private static func parseSQLValues(_ input: String) -> [String]? {
        var values: [String] = []
        var current = ""
        var inQuote = false
        var index = input.startIndex

        while index < input.endIndex {
            let char = input[index]
            if inQuote {
                if char == "'" {
                    let next = input.index(after: index)
                    if next < input.endIndex, input[next] == "'" {
                        current.append("'")
                        index = input.index(after: next)
                        continue
                    }
                    inQuote = false
                    current.append(char)
                } else {
                    current.append(char)
                }
            } else if char == "'" {
                inQuote = true
                current.append(char)
            } else if char == "," {
                values.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
            index = input.index(after: index)
        }
        if !current.isEmpty {
            values.append(current.trimmingCharacters(in: .whitespaces))
        }
        return values
    }

    private static func unquoteSQLLiteral(_ value: String) -> String {
        guard value.hasPrefix("'"), value.hasSuffix("'") else { return value }
        let inner = value.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "''", with: "'")
    }
}
