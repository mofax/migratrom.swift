public func createView(
    _ schema: String,
    _ name: String,
    _ selectSql: String,
    dialect: any SQLDialect
) throws -> Operation {
    let createSql = "CREATE VIEW \(try dialect.qualified(schema, name)) AS \(selectSql)"

    return Operation(
        id: "view.\(name)",
        label: "Create view \"\(name)\"",
        precheck: [check("ensure view \"\(name)\" does not exist", dialect.viewExistsSql(schema, name, negate: true))],
        execute: [step("create view \"\(name)\"", createSql)],
        postcheck: [check("verify view \"\(name)\" exists", dialect.viewExistsSql(schema, name, negate: false))]
    )
}
