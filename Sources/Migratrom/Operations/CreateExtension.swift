public func createExtension(
    _ name: String,
    options: CreateExtensionOptions = CreateExtensionOptions(),
    dialect: any SQLDialect
) throws -> Operation {
    guard dialect.capabilities.extensions else {
        throw MigratromError.unsupported(feature: "extensions", dialect: dialect.name)
    }
    let withSchema: String
    if let schema = options.schema {
        withSchema = " WITH SCHEMA \(try dialect.quoteIdent(schema))"
    } else {
        withSchema = ""
    }
    let createSql = "CREATE EXTENSION \(try dialect.quoteIdent(name))\(withSchema)"

    return Operation(
        id: "extension.\(name)",
        label: "Create extension \"\(name)\"",
        precheck: [check("ensure extension \"\(name)\" does not exist", dialect.extensionExistsSql(name, negate: true))],
        execute: [step("create extension \"\(name)\"", createSql)],
        postcheck: [check("verify extension \"\(name)\" exists", dialect.extensionExistsSql(name, negate: false))]
    )
}
