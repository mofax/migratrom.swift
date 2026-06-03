public func createMaterializedView(
    _ schema: String,
    _ name: String,
    _ selectSql: String,
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.materializedViews else {
        throw MigratromError.unsupported(feature: "materialized views", dialect: dialect.name)
    }
    let createSql = "CREATE MATERIALIZED VIEW \(try dialect.qualified(schema, name)) AS \(selectSql)"

    return Operation(
        id: "matview.\(name)",
        label: "Create materialized view \"\(name)\"",
        precheck: [
            check(
                "ensure materialized view \"\(name)\" does not exist",
                dialect.matviewExistsSql(schema, name, negate: true)
            ),
        ],
        execute: [step("create materialized view \"\(name)\"", createSql)],
        postcheck: [
            check(
                "verify materialized view \"\(name)\" exists",
                dialect.matviewExistsSql(schema, name, negate: false)
            ),
        ]
    )
}
