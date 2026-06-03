public func createIndex(
    _ schema: String,
    _ table: String,
    _ indexName: String,
    _ columns: [String],
    options: CreateIndexOptions = CreateIndexOptions(),
    dialect: any SQLDialect
) throws -> Operation {
    let concurrently = options.concurrently
    if concurrently && !dialect.capabilities.concurrentIndexes {
        throw MigratromError.unsupported(feature: "CREATE INDEX CONCURRENTLY", dialect: dialect.name)
    }
    let createSql = try dialect.createIndexSql(
        schema: schema,
        table: table,
        indexName: indexName,
        columns: columns,
        concurrently: concurrently
    )
    let labelSuffix = concurrently ? " concurrently" : ""

    return Operation(
        id: "index.\(table).\(indexName)",
        label: "Create index\(labelSuffix) \"\(indexName)\" on \"\(table)\"",
        precheck: [
            check("ensure index \"\(indexName)\" does not exist", try dialect.tableExistsSql(schema, indexName, negate: true)),
        ],
        execute: [step("create index\(labelSuffix) \"\(indexName)\" on \"\(table)\"", createSql)],
        postcheck: [
            check("verify index \"\(indexName)\" exists", try dialect.tableExistsSql(schema, indexName, negate: false)),
        ],
        outsideTransaction: concurrently
    )
}
