public func check(_ description: String, _ sql: String) -> Check {
    Check(description: description, sql: sql)
}

public func step(_ description: String, _ sql: String) -> ExecuteStep {
    ExecuteStep(description: description, sql: sql)
}
