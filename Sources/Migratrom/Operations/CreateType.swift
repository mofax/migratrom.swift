public func createType(
    _ schema: String,
    _ name: String,
    _ labels: [String],
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.enumTypes else {
        throw MigratromError.unsupported(feature: "enum types", dialect: dialect.name)
    }
    let labelList = labels.map { dialect.quoteLiteral($0) }.joined(separator: ", ")
    let createSql = "CREATE TYPE \(try dialect.qualified(schema, name)) AS ENUM (\(labelList))"

    return Operation(
        id: "type.\(name)",
        label: "Create enum type \"\(name)\"",
        precheck: [
            check("ensure type \"\(name)\" does not exist", dialect.enumTypeExistsSql(schema, name, negate: true)),
        ],
        execute: [step("create enum type \"\(name)\"", createSql)],
        postcheck: [check("verify type \"\(name)\" exists", dialect.enumTypeExistsSql(schema, name, negate: false))]
    )
}
