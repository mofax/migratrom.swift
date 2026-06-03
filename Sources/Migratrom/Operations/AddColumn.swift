public func addColumn(
    _ schema: String,
    _ table: String,
    _ col: ColumnDef,
    dialect: any SQLDialect
) throws -> Operation {
    let qTable = try dialect.qualified(schema, table)
    let alterSql = "ALTER TABLE \(qTable) ADD COLUMN \(try dialect.renderColumnDef(col))"

    return Operation(
        id: "column.\(table).\(col.name)",
        label: "Add column \"\(col.name)\" on \"\(table)\"",
        precheck: [
            check(
                "ensure column \"\(col.name)\" does not exist on \"\(table)\"",
                dialect.columnExistsSql(schema, table, col.name, negate: true)
            ),
        ],
        execute: [step("add column \"\(col.name)\" on \"\(table)\"", alterSql)],
        postcheck: [
            check(
                "verify column \"\(col.name)\" exists on \"\(table)\"",
                dialect.columnExistsSql(schema, table, col.name, negate: false)
            ),
        ]
    )
}
