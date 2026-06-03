public func renameTable(
    _ schema: String,
    _ from: String,
    _ to: String,
    dialect: any SQLDialect
) throws -> Operation {
    let alterSql = "ALTER TABLE \(try dialect.qualified(schema, from)) RENAME TO \(try dialect.quoteIdent(to))"

    return Operation(
        id: "rename_table.\(from)_to_\(to)",
        label: "Rename table \"\(from)\" to \"\(to)\"",
        precheck: [
            check("ensure table \"\(from)\" exists", try dialect.tableExistsSql(schema, from, negate: false)),
            check("ensure table \"\(to)\" does not exist", try dialect.tableExistsSql(schema, to, negate: true)),
        ],
        execute: [step("rename table \"\(from)\" to \"\(to)\"", alterSql)],
        postcheck: [check("verify table \"\(to)\" exists", try dialect.tableExistsSql(schema, to, negate: false))]
    )
}
