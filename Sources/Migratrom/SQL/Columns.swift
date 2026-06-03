/// Render one column line: `"name" type [DEFAULT ...] [NOT NULL]`.
public func renderColumnDef(_ col: ColumnDef) throws -> String {
    var parts = [try quoteIdent(col.name), col.typeSql]
    if let defaultSql = col.defaultSql {
        parts.append(defaultSql)
    }
    if !col.nullable {
        parts.append("NOT NULL")
    }
    return parts.joined(separator: " ")
}

/// Comma-joined column definition lines.
public func renderColumnList(_ columns: [ColumnDef]) throws -> String {
    try columns.map(renderColumnDef).joined(separator: ",\n  ")
}
