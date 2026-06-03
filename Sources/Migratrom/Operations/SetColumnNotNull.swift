public func setColumnNotNull(
    _ schema: String,
    _ table: String,
    _ column: String,
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.alterColumnNotNull else {
        throw MigratromError.unsupported(feature: "ALTER COLUMN SET NOT NULL", dialect: dialect.name)
    }
    let qTable = try dialect.qualified(schema, table)
    let alterSql = "ALTER TABLE \(qTable) ALTER COLUMN \(try dialect.quoteIdent(column)) SET NOT NULL"

    return Operation(
        id: "column_not_null.\(table).\(column)",
        label: "Set NOT NULL on column \"\(column)\" of \"\(table)\"",
        precheck: [
            check(
                "ensure column \"\(column)\" exists on \"\(table)\"",
                dialect.columnExistsSql(schema, table, column, negate: false)
            ),
            check(
                "ensure column \"\(column)\" is nullable on \"\(table)\"",
                dialect.columnNotNullSql(schema, table, column, negate: true)
            ),
        ],
        execute: [step("set NOT NULL on column \"\(column)\" of \"\(table)\"", alterSql)],
        postcheck: [
            check(
                "verify column \"\(column)\" is NOT NULL on \"\(table)\"",
                dialect.columnNotNullSql(schema, table, column, negate: false)
            ),
        ]
    )
}
