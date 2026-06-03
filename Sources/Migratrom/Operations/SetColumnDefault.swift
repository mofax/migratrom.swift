public func setColumnDefault(
    _ schema: String,
    _ table: String,
    _ column: String,
    _ defaultSql: String,
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.alterColumnDefault else {
        throw MigratromError.unsupported(feature: "ALTER COLUMN SET DEFAULT", dialect: dialect.name)
    }
    let qTable = try dialect.qualified(schema, table)
    let alterSql = "ALTER TABLE \(qTable) ALTER COLUMN \(try dialect.quoteIdent(column)) SET \(defaultSql)"

    return Operation(
        id: "column_default.\(table).\(column)",
        label: "Set default on column \"\(column)\" of \"\(table)\"",
        precheck: [
            check(
                "ensure column \"\(column)\" exists on \"\(table)\"",
                dialect.columnExistsSql(schema, table, column, negate: false)
            ),
            check(
                "ensure column \"\(column)\" has no default yet on \"\(table)\"",
                dialect.columnDefaultSetSql(schema, table, column, negate: true)
            ),
        ],
        execute: [step("set default on column \"\(column)\" of \"\(table)\"", alterSql)],
        postcheck: [
            check(
                "verify column \"\(column)\" has a default on \"\(table)\"",
                dialect.columnDefaultSetSql(schema, table, column, negate: false)
            ),
        ]
    )
}
