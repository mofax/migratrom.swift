public func createSequence(
    _ schema: String,
    _ name: String,
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.sequences else {
        throw MigratromError.unsupported(feature: "sequences", dialect: dialect.name)
    }
    let createSql = "CREATE SEQUENCE \(try dialect.qualified(schema, name))"

    return Operation(
        id: "sequence.\(name)",
        label: "Create sequence \"\(name)\"",
        precheck: [
            check("ensure sequence \"\(name)\" does not exist", try dialect.tableExistsSql(schema, name, negate: true)),
        ],
        execute: [step("create sequence \"\(name)\"", createSql)],
        postcheck: [
            check("verify sequence \"\(name)\" exists", try dialect.tableExistsSql(schema, name, negate: false)),
        ]
    )
}
