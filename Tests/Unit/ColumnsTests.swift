import Testing
@testable import Migratrom

@Suite struct ColumnsTests {
    @Test func notNullByDefault() throws {
        #expect(try renderColumnDef(ColumnDef(name: "id", typeSql: "SERIAL")) == "\"id\" SERIAL NOT NULL")
    }

    @Test func nullableOmitsNotNull() throws {
        #expect(
            try renderColumnDef(ColumnDef(name: "name", typeSql: "text", nullable: true)) == "\"name\" text"
        )
    }

    @Test func includesDefaultClauseVerbatim() throws {
        #expect(
            try renderColumnDef(
                ColumnDef(name: "createdAt", typeSql: "timestamptz", defaultSql: "DEFAULT (now())")
            ) == "\"createdAt\" timestamptz DEFAULT (now()) NOT NULL"
        )
    }

    @Test func booleanDefault() throws {
        #expect(
            try renderColumnDef(
                ColumnDef(name: "published", typeSql: "bool", defaultSql: "DEFAULT false")
            ) == "\"published\" bool DEFAULT false NOT NULL"
        )
    }

    @Test func joinsWithNewlineIndent() throws {
        let cols = [
            ColumnDef(name: "id", typeSql: "SERIAL"),
            ColumnDef(name: "email", typeSql: "text"),
        ]
        #expect(try Migratrom.renderColumnList(cols) == "\"id\" SERIAL NOT NULL,\n  \"email\" text NOT NULL")
    }
}
