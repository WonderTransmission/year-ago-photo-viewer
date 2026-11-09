import Foundation
import Testing
@testable import YearAgoCore

@Suite struct DatabaseTests {
    @Test func migratesToCurrentVersion() throws {
        let database = try Database(path: ":memory:")
        #expect(try database.userVersion == 0)
        try Schema.migrate(database)
        #expect(try database.userVersion == Schema.currentVersion)
        try Schema.migrate(database)  // idempotent
        #expect(try database.userVersion == Schema.currentVersion)
    }

    @Test func bindsAndReadsValues() throws {
        let database = try Database(path: ":memory:")
        try database.execute("CREATE TABLE t (i INTEGER, s TEXT, n INTEGER)")
        try database.prepare("INSERT INTO t VALUES (?, ?, ?)").run([.int(42), .text("héllo"), .null])
        let query = try database.prepare("SELECT i, s, n FROM t")
        try query.bind([])
        #expect(try query.step())
        #expect(query.int64(0) == 42)
        #expect(query.text(1) == "héllo")
        #expect(query.optionalInt64(2) == nil)
        #expect(try !query.step())
    }

    @Test func transactionRollsBackOnError() throws {
        let database = try Database(path: ":memory:")
        try database.execute("CREATE TABLE t (i INTEGER)")
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try database.transaction {
                try database.prepare("INSERT INTO t VALUES (1)").run()
                throw Boom()
            }
        }
        let query = try database.prepare("SELECT COUNT(*) FROM t")
        try query.bind([])
        _ = try query.step()
        #expect(query.int64(0) == 0)
    }

    @Test func badSQLThrows() throws {
        let database = try Database(path: ":memory:")
        #expect(throws: DatabaseError.self) { try database.execute("NOT SQL") }
        #expect(throws: DatabaseError.self) { _ = try database.prepare("SELECT * FROM missing") }
    }
}
