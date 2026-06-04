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

    // MARK: - Builders previously without a Postgres SQL assertion

    @Test func createTableWithPrimaryKey() throws {
        let op = try createTable(
            "public",
            "user",
            [ColumnDef(name: "id", typeSql: "bigint")],
            primaryKey: PrimaryKey(columns: ["id"]),
            dialect: PostgresDialect()
        )
        #expect(op.id == "table.user")
        #expect(op.execute[0].sql == """
        CREATE TABLE "public"."user" (
          "id" bigint NOT NULL,
          PRIMARY KEY ("id")
        )
        """)
        #expect(op.precheck[0].sql.contains("to_regclass"))
        #expect(op.precheck[0].sql.contains("IS NULL"))
    }

    @Test func createTypeEnum() throws {
        let op = try createType("public", "mood", ["happy", "sad"], dialect: PostgresDialect())
        #expect(op.id == "type.mood")
        #expect(op.execute[0].sql == "CREATE TYPE \"public\".\"mood\" AS ENUM ('happy', 'sad')")
    }

    @Test func addEnumValueAppends() throws {
        let op = try addEnumValue("public", "mood", "thrilled", dialect: PostgresDialect())
        #expect(op.id == "enum.mood.thrilled")
        #expect(op.execute[0].sql == "ALTER TYPE \"public\".\"mood\" ADD VALUE 'thrilled'")
        #expect(op.precheck[0].sql.contains("pg_type"))
    }

    @Test func createViewSelect() throws {
        let op = try createView("public", "active_users", "SELECT 1", dialect: PostgresDialect())
        #expect(op.id == "view.active_users")
        #expect(op.execute[0].sql == "CREATE VIEW \"public\".\"active_users\" AS SELECT 1")
    }

    @Test func createMaterializedViewSelect() throws {
        let op = try createMaterializedView("public", "mv", "SELECT 1", dialect: PostgresDialect())
        #expect(op.id == "matview.mv")
        #expect(op.execute[0].sql == "CREATE MATERIALIZED VIEW \"public\".\"mv\" AS SELECT 1")
    }

    @Test func addUniqueConstraint() throws {
        let op = try addUnique("public", "user", "user_email_key", ["email"], dialect: PostgresDialect())
        #expect(op.id == "unique.user.user_email_key")
        #expect(
            op.execute[0].sql ==
                "ALTER TABLE \"public\".\"user\" ADD CONSTRAINT \"user_email_key\" UNIQUE (\"email\")"
        )
    }

    @Test func renameColumnUserName() throws {
        let op = try renameColumn("public", "user", "name", "full_name", dialect: PostgresDialect())
        #expect(op.id == "rename_column.user.name_to_full_name")
        #expect(
            op.execute[0].sql ==
                "ALTER TABLE \"public\".\"user\" RENAME COLUMN \"name\" TO \"full_name\""
        )
    }

    @Test func renameTableUserAccount() throws {
        let op = try renameTable("public", "user", "account", dialect: PostgresDialect())
        #expect(op.id == "rename_table.user_to_account")
        #expect(op.execute[0].sql == "ALTER TABLE \"public\".\"user\" RENAME TO \"account\"")
    }

    @Test func setColumnDefaultRole() throws {
        let op = try setColumnDefault("public", "user", "role", "DEFAULT 'user'", dialect: PostgresDialect())
        #expect(op.id == "column_default.user.role")
        #expect(
            op.execute[0].sql ==
                "ALTER TABLE \"public\".\"user\" ALTER COLUMN \"role\" SET DEFAULT 'user'"
        )
    }

    @Test func setColumnNotNullEmail() throws {
        let op = try setColumnNotNull("public", "user", "email", dialect: PostgresDialect())
        #expect(op.id == "column_not_null.user.email")
        #expect(
            op.execute[0].sql ==
                "ALTER TABLE \"public\".\"user\" ALTER COLUMN \"email\" SET NOT NULL"
        )
    }
}
