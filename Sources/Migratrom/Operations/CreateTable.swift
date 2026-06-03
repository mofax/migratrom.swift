public func createTable(
    _ schema: String,
    _ table: String,
    _ columns: [ColumnDef],
    primaryKey: PrimaryKey? = nil,
    dialect: any SQLDialect
) throws -> Operation {
    var lines = [try dialect.renderColumnList(columns)]
    if let primaryKey {
        lines.append("PRIMARY KEY (\(try dialect.quoteIdentList(primaryKey.columns)))")
    }
    let createSql = "CREATE TABLE \(try dialect.qualified(schema, table)) (\n  \(lines.joined(separator: ",\n  "))\n)"

    return Operation(
        id: "table.\(table)",
        label: "Create table \"\(table)\"",
        precheck: [
            check("ensure table \"\(table)\" does not exist", try dialect.tableExistsSql(schema, table, negate: true)),
        ],
        execute: [step("create table \"\(table)\"", createSql)],
        postcheck: [
            check("verify table \"\(table)\" exists", try dialect.tableExistsSql(schema, table, negate: false)),
        ]
    )
}
