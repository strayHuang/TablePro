//
//  SQLContextAnalyzerJoinAndTests.swift
//  TableProTests
//
//  Tests for `AND`/`OR` that continue a JOIN `ON` clause
//

import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

struct SQLContextAnalyzerJoinAndTests {
    let analyzer = SQLContextAnalyzer()

    @Test("AND after ON still resolves to .and")
    func andAfterOnIsAnd() {
        let query = "SELECT * FROM users u JOIN orders o ON u.id = o.user_id AND "
        let context = analyzer.analyze(query: query, cursorPosition: query.count)
        #expect(context.clauseType == .and)
    }

    @Test("AND after ON reports that it continues the join")
    func andAfterOnContinuesJoin() {
        let query = "SELECT * FROM users u JOIN orders o ON u.id = o.user_id AND "
        let context = analyzer.analyze(query: query, cursorPosition: query.count)
        #expect(context.andContinuesJoin)
    }

    @Test("OR after ON reports that it continues the join")
    func orAfterOnContinuesJoin() {
        let query = "SELECT * FROM users u JOIN orders o ON u.id = o.user_id OR "
        let context = analyzer.analyze(query: query, cursorPosition: query.count)
        #expect(context.clauseType == .and)
        #expect(context.andContinuesJoin)
    }

    @Test("AND after WHERE does not continue a join")
    func andAfterWhereIsNotJoin() {
        let query = "SELECT * FROM users WHERE id = 1 AND "
        let context = analyzer.analyze(query: query, cursorPosition: query.count)
        #expect(context.clauseType == .and)
        #expect(!context.andContinuesJoin)
    }

    @Test("AND after HAVING does not continue a join")
    func andAfterHavingIsNotJoin() {
        let query = "SELECT * FROM users GROUP BY dept HAVING total > 1 AND "
        let context = analyzer.analyze(query: query, cursorPosition: query.count)
        #expect(context.clauseType == .and)
        #expect(!context.andContinuesJoin)
    }

    @Test("A bare ON does not continue a join")
    func bareOnIsNotJoinContinuation() {
        let query = "SELECT * FROM users u JOIN orders o ON "
        let context = analyzer.analyze(query: query, cursorPosition: query.count)
        #expect(context.clauseType == .on)
        #expect(!context.andContinuesJoin)
    }
}
