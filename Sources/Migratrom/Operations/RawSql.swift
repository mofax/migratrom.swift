import Foundation

public struct PartialCheck: Sendable, Equatable {
    public var description: String?
    public var sql: String

    public init(description: String? = nil, sql: String) {
        self.description = description
        self.sql = sql
    }
}

public struct PartialExecuteStep: Sendable, Equatable {
    public var description: String?
    public var sql: String

    public init(description: String? = nil, sql: String) {
        self.description = description
        self.sql = sql
    }
}

public struct RawSqlInput: Sendable, Equatable {
    public var label: String
    public var precheck: [PartialCheck]?
    public var execute: [PartialExecuteStep]
    public var postcheck: [PartialCheck]?
    public var id: String?

    public init(
        label: String,
        precheck: [PartialCheck]? = nil,
        execute: [PartialExecuteStep],
        postcheck: [PartialCheck]? = nil,
        id: String? = nil
    ) {
        self.label = label
        self.precheck = precheck
        self.execute = execute
        self.postcheck = postcheck
        self.id = id
    }
}

private func slugify(_ label: String) -> String {
    let lowered = label.lowercased()
    let replaced = lowered.replacingOccurrences(
        of: #"[^a-z0-9]+"#,
        with: ".",
        options: .regularExpression
    )
    return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "."))
}

private func normalizeChecks(_ checks: [PartialCheck]?) -> [Check] {
    checks?.map { partial in
        Check(description: partial.description ?? partial.sql, sql: partial.sql)
    } ?? []
}

private func normalizeSteps(_ steps: [PartialExecuteStep]) -> [ExecuteStep] {
    steps.map { partial in
        ExecuteStep(description: partial.description ?? partial.sql, sql: partial.sql)
    }
}

public func rawSql(_ input: RawSqlInput) throws -> Operation {
    let execute = normalizeSteps(input.execute)
    guard !execute.isEmpty else {
        throw MigratromError.config("rawSql requires at least one execute step")
    }

    let postcheck = normalizeChecks(input.postcheck)
    guard !postcheck.isEmpty else {
        throw MigratromError.config("rawSql requires at least one postcheck step")
    }

    return Operation(
        id: input.id ?? slugify(input.label),
        label: input.label,
        precheck: normalizeChecks(input.precheck),
        execute: execute,
        postcheck: postcheck
    )
}
