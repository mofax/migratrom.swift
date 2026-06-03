public func addUnique(
    _ schema: String,
    _ table: String,
    _ constraintName: String,
    _ columns: [String],
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.addUniqueConstraints else {
        throw MigratromError.unsupported(feature: "ADD UNIQUE constraints", dialect: dialect.name)
    }
    let qTable = try dialect.qualified(schema, table)
    let alterSql =
        "ALTER TABLE \(qTable) ADD CONSTRAINT \(try dialect.quoteIdent(constraintName)) UNIQUE (\(try dialect.quoteIdentList(columns)))"

    return Operation(
        id: "unique.\(table).\(constraintName)",
        label: "Add unique constraint \"\(constraintName)\" on \"\(table)\"",
        precheck: [
            check(
                "ensure unique constraint \"\(constraintName)\" does not exist on \"\(table)\"",
                try dialect.constraintExistsSql(schema, table, constraintName, negate: true)
            ),
        ],
        execute: [step("add unique constraint \"\(constraintName)\" on \"\(table)\"", alterSql)],
        postcheck: [
            check(
                "verify unique constraint \"\(constraintName)\" exists on \"\(table)\"",
                try dialect.constraintExistsSql(schema, table, constraintName, negate: false)
            ),
        ]
    )
}
