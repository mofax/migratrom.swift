public func addForeignKey(
    _ schema: String,
    _ table: String,
    _ spec: ForeignKeySpec,
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.addForeignKeys else {
        throw MigratromError.unsupported(feature: "ADD FOREIGN KEY constraints", dialect: dialect.name)
    }
    let qTable = try dialect.qualified(schema, table)
    let refTable = try dialect.qualified(schema, spec.references.table)
    var parts = [
        "ALTER TABLE \(qTable)",
        "  ADD CONSTRAINT \(try dialect.quoteIdent(spec.name))",
        "  FOREIGN KEY (\(try dialect.quoteIdentList(spec.columns)))",
        "  REFERENCES \(refTable) (\(try dialect.quoteIdentList(spec.references.columns)))",
    ]
    if let onDelete = spec.onDelete {
        parts.append("  ON DELETE \(onDelete.sql)")
    }
    if let onUpdate = spec.onUpdate {
        parts.append("  ON UPDATE \(onUpdate.sql)")
    }
    let alterSql = parts.joined(separator: "\n")

    return Operation(
        id: "fk.\(table).\(spec.name)",
        label: "Add foreign key \"\(spec.name)\" on \"\(table)\"",
        precheck: [
            check(
                "ensure foreign key \"\(spec.name)\" does not exist on \"\(table)\"",
                try dialect.constraintExistsSql(schema, table, spec.name, negate: true)
            ),
        ],
        execute: [step("add foreign key \"\(spec.name)\" on \"\(table)\"", alterSql)],
        postcheck: [
            check(
                "verify foreign key \"\(spec.name)\" exists on \"\(table)\"",
                try dialect.constraintExistsSql(schema, table, spec.name, negate: false)
            ),
        ]
    )
}
