public func addPrimaryKey(
    _ schema: String,
    _ table: String,
    _ constraintName: String,
    _ columns: [String],
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.addPrimaryKeyConstraints else {
        throw MigratromError.unsupported(feature: "ADD PRIMARY KEY constraints", dialect: dialect.name)
    }
    let qTable = try dialect.qualified(schema, table)
    let alterSql =
        "ALTER TABLE \(qTable) ADD CONSTRAINT \(try dialect.quoteIdent(constraintName)) PRIMARY KEY (\(try dialect.quoteIdentList(columns)))"

    return Operation(
        id: "pk.\(table).\(constraintName)",
        label: "Add primary key \"\(constraintName)\" on \"\(table)\"",
        precheck: [
            check(
                "ensure primary key \"\(constraintName)\" does not exist on \"\(table)\"",
                try dialect.constraintExistsSql(schema, table, constraintName, negate: true)
            ),
        ],
        execute: [step("add primary key \"\(constraintName)\" on \"\(table)\"", alterSql)],
        postcheck: [
            check(
                "verify primary key \"\(constraintName)\" exists on \"\(table)\"",
                try dialect.constraintExistsSql(schema, table, constraintName, negate: false)
            ),
        ]
    )
}
