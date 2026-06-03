public func renameColumn(
    _ schema: String,
    _ table: String,
    _ from: String,
    _ to: String,
    dialect: any SQLDialect
) throws -> Operation {
    let qTable = try dialect.qualified(schema, table)
    let alterSql = "ALTER TABLE \(qTable) RENAME COLUMN \(try dialect.quoteIdent(from)) TO \(try dialect.quoteIdent(to))"

    return Operation(
        id: "rename_column.\(table).\(from)_to_\(to)",
        label: "Rename column \"\(from)\" to \"\(to)\" on \"\(table)\"",
        precheck: [
            check(
                "ensure column \"\(from)\" exists on \"\(table)\"",
                dialect.columnExistsSql(schema, table, from, negate: false)
            ),
            check(
                "ensure column \"\(to)\" does not exist on \"\(table)\"",
                dialect.columnExistsSql(schema, table, to, negate: true)
            ),
        ],
        execute: [step("rename column \"\(from)\" to \"\(to)\" on \"\(table)\"", alterSql)],
        postcheck: [
            check(
                "verify column \"\(to)\" exists on \"\(table)\"",
                dialect.columnExistsSql(schema, table, to, negate: false)
            ),
        ]
    )
}
