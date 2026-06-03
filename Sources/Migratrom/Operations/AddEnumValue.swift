public func addEnumValue(
    _ schema: String,
    _ typeName: String,
    _ value: String,
    options: AddEnumValueOptions = AddEnumValueOptions(),
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.enumTypes else {
        throw MigratromError.unsupported(feature: "enum values", dialect: dialect.name)
    }
    let beforeClause = options.before.map { " BEFORE \(dialect.quoteLiteral($0))" } ?? ""
    let alterSql =
        "ALTER TYPE \(try dialect.qualified(schema, typeName)) ADD VALUE \(dialect.quoteLiteral(value))\(beforeClause)"

    return Operation(
        id: "enum.\(typeName).\(value)",
        label: "Add enum value \"\(value)\" to type \"\(typeName)\"",
        precheck: [
            check("ensure enum type \"\(typeName)\" exists", dialect.enumTypeExistsSql(schema, typeName, negate: false)),
            check(
                "ensure enum value \"\(value)\" does not exist on \"\(typeName)\"",
                dialect.enumLabelExistsSql(schema, typeName, value, negate: true)
            ),
        ],
        execute: [step("add enum value \"\(value)\" to \"\(typeName)\"", alterSql)],
        postcheck: [
            check(
                "verify enum value \"\(value)\" exists on \"\(typeName)\"",
                dialect.enumLabelExistsSql(schema, typeName, value, negate: false)
            ),
        ]
    )
}
