public func createSchema(
    _ name: String,
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.schemas else {
        throw MigratromError.unsupported(feature: "schemas", dialect: dialect.name)
    }
    let createSql = "CREATE SCHEMA \(try dialect.quoteIdent(name))"

    return Operation(
        id: "schema.\(name)",
        label: "Create schema \"\(name)\"",
        precheck: [check("ensure schema \"\(name)\" does not exist", dialect.schemaExistsSql(name, negate: true))],
        execute: [step("create schema \"\(name)\"", createSql)],
        postcheck: [check("verify schema \"\(name)\" exists", dialect.schemaExistsSql(name, negate: false))]
    )
}
