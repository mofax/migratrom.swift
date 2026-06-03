import Testing
@testable import Migratrom

@Suite struct IdentifiersTests {
    @Test func quoteIdentSimple() throws {
        #expect(try quoteIdent("user") == "\"user\"")
    }

    @Test func quoteIdentEscapesEmbeddedQuotes() throws {
        #expect(try quoteIdent("weird\"name") == "\"weird\"\"name\"")
    }

    @Test func quoteIdentRejectsNUL() {
        #expect(throws: MigratromError.self) {
            _ = try quoteIdent("a\0b")
        }
    }

    @Test func quoteLiteralSimple() {
        #expect(quoteLiteral("hello") == "'hello'")
    }

    @Test func quoteLiteralEscapesQuotes() {
        #expect(quoteLiteral("it's") == "'it''s'")
    }

    @Test func qualifiedName() throws {
        #expect(try qualified("public", "user") == "\"public\".\"user\"")
    }

    @Test func regclassLiteralValue() throws {
        #expect(try Migratrom.regclassLiteral("public", "user") == "'\"public\".\"user\"'")
    }

    @Test func quoteIdentListJoins() throws {
        #expect(try Migratrom.quoteIdentList(["email", "name"]) == "\"email\", \"name\"")
    }
}
