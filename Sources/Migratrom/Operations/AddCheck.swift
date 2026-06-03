public func addCheck(
    _ schema: String,
    _ table: String,
    _ constraintName: String,
    _ checkSql: String,
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.addCheckConstraints else {
        throw MigratromError.unsupported(feature: "ADD CHECK constraints", dialect: dialect.name)
    }
    let qTable = try dialect.qualified(schema, table)
    let alterSql =
        "ALTER TABLE \(qTable) ADD CONSTRAINT \(try dialect.quoteIdent(constraintName)) CHECK (\(checkSql))"

    return Operation(
        id: "check.\(table).\(constraintName)",
        label: "Add check constraint \"\(constraintName)\" on \"\(table)\"",
        precheck: [
            check(
                "ensure check constraint \"\(constraintName)\" does not exist on \"\(table)\"",
                try dialect.checkConstraintExistsSql(schema, table, constraintName, negate: true)
            ),
        ],
        execute: [step("add check constraint \"\(constraintName)\" on \"\(table)\"", alterSql)],
        postcheck: [
            check(
                "verify check constraint \"\(constraintName)\" exists on \"\(table)\"",
                try dialect.checkConstraintExistsSql(schema, table, constraintName, negate: false)
            ),
        ]
    )
}
