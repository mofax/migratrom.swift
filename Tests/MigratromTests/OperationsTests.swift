import Testing
@testable import Migratrom

@Suite struct OperationsTests {
    @Test func addColumnPasswordHash() throws {
        let dialect = PostgresDialect()
        let op = try addColumn("public", "user", ColumnDef(name: "password_hash", typeSql: "text"), dialect: dialect)
        #expect(op.id == "column.user.password_hash")
        #expect(op.execute[0].sql == "ALTER TABLE \"public\".\"user\" ADD COLUMN \"password_hash\" text NOT NULL")
        #expect(op.precheck[0].sql.contains("information_schema.columns"))
        #expect(op.precheck[0].sql.contains("NOT EXISTS"))
    }

    @Test func addColumnWithDefault() throws {
        let dialect = PostgresDialect()
        let op = try addColumn(
            "public",
            "user",
            ColumnDef(name: "role", typeSql: "text", defaultSql: "DEFAULT 'user'"),
            dialect: dialect
        )
        #expect(op.execute[0].sql == "ALTER TABLE \"public\".\"user\" ADD COLUMN \"role\" text DEFAULT 'user' NOT NULL")
    }

    @Test func addCheckPositiveAmount() throws {
        let dialect = PostgresDialect()
        let op = try addCheck("public", "line", "line_positive_amount", "amount > 0", dialect: dialect)
        #expect(op.id == "check.line.line_positive_amount")
        #expect(
            op.execute[0].sql ==
                "ALTER TABLE \"public\".\"line\" ADD CONSTRAINT \"line_positive_amount\" CHECK (amount > 0)"
        )
        #expect(op.precheck[0].sql.contains("contype = 'c'"))
    }

    @Test func addPrimaryKeyUserPkey() throws {
        let dialect = PostgresDialect()
        let op = try addPrimaryKey("public", "user", "user_pkey", ["id"], dialect: dialect)
        #expect(op.id == "pk.user.user_pkey")
        #expect(
            op.execute[0].sql ==
                "ALTER TABLE \"public\".\"user\" ADD CONSTRAINT \"user_pkey\" PRIMARY KEY (\"id\")"
        )
    }

    @Test func createSchemaApp() throws {
        let op = try createSchema("app", dialect: PostgresDialect())
        #expect(op.id == "schema.app")
        #expect(op.execute[0].sql == "CREATE SCHEMA \"app\"")
    }

    @Test func createExtensionPlpgsql() throws {
        let op = try createExtension("plpgsql", dialect: PostgresDialect())
        #expect(op.id == "extension.plpgsql")
        #expect(op.execute[0].sql == "CREATE EXTENSION \"plpgsql\"")
        #expect(op.precheck[0].sql.contains("pg_extension"))
    }

    @Test func createSequenceOrderSeq() throws {
        let op = try createSequence("public", "order_seq", dialect: PostgresDialect())
        #expect(op.id == "sequence.order_seq")
        #expect(op.execute[0].sql == "CREATE SEQUENCE \"public\".\"order_seq\"")
    }

    @Test func createIndexConcurrently() throws {
        let dialect = PostgresDialect()
        let op = try createIndex(
            "public",
            "post",
            "post_authorId_idx",
            ["authorId"],
            options: CreateIndexOptions(concurrently: true),
            dialect: dialect
        )
        #expect(
            op.execute[0].sql ==
                "CREATE INDEX CONCURRENTLY \"post_authorId_idx\" ON \"public\".\"post\" (\"authorId\")"
        )
        #expect(op.outsideTransaction)
        #expect(op.label.contains("concurrently"))
    }

    @Test func addForeignKeyPostAuthor() throws {
        let dialect = PostgresDialect()
        let op = try Migratrom.addForeignKey(
            "public",
            "post",
            ForeignKeySpec(
                name: "post_authorId_fkey",
                columns: ["authorId"],
                references: ForeignKeyReference(table: "user", columns: ["id"])
            ),
            dialect: dialect
        )
        #expect(op.id == "fk.post.post_authorId_fkey")
        #expect(
            op.execute[0].sql ==
                "ALTER TABLE \"public\".\"post\"\n  ADD CONSTRAINT \"post_authorId_fkey\"\n  FOREIGN KEY (\"authorId\")\n  REFERENCES \"public\".\"user\" (\"id\")"
        )
    }

    @Test func rawSqlDefaultsDescriptions() throws {
        let op = try rawSql(
            RawSqlInput(
                label: "Enable pgcrypto",
                precheck: [
                    PartialCheck(
                        sql: "SELECT NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto')"
                    ),
                ],
                execute: [PartialExecuteStep(sql: "CREATE EXTENSION IF NOT EXISTS pgcrypto")],
                postcheck: [
                    PartialCheck(
                        sql: "SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto')"
                    ),
                ]
            )
        )
        #expect(op.precheck[0].description == op.precheck[0].sql)
        #expect(op.execute[0].description == op.execute[0].sql)
        #expect(op.id == "enable.pgcrypto")
    }

    @Test func rawSqlRequiresExecuteAndPostcheck() {
        #expect(throws: MigratromError.self) {
            try rawSql(RawSqlInput(label: "x", execute: [], postcheck: [PartialCheck(sql: "SELECT true")]))
        }
    }
}
