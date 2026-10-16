//
//  SQLCompletionInsertionTests.swift
//  TableProTests
//
//  Tests for SQLCompletionInsertion: the accept-time decision for what text
//  a completion inserts and where the caret lands. Pins the favorite marker
//  rule, the function-paren rule, and the end-of-text default.
//

import Foundation
@testable import TablePro
import Testing

struct SQLCompletionInsertionTests {
    @Test("Favorite with a marker inserts stripped text with the caret at the marker")
    func favoriteWithMarker() {
        let item = SQLCompletionItem.favorite(
            keyword: "slc",
            name: "Count rows",
            query: "SELECT COUNT(*)\nFROM  alias\nWHERE alias.;;"
        )
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "SELECT COUNT(*)\nFROM  alias\nWHERE alias.")
        #expect(resolution.cursorOffset == (resolution.text as NSString).length)
    }

    @Test("Favorite with a mid-query marker places the caret inside the text")
    func favoriteWithMidQueryMarker() {
        let item = SQLCompletionItem.favorite(
            keyword: "cnt",
            name: "Count where",
            query: "SELECT COUNT(*) FROM t WHERE ;; LIMIT 1"
        )
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "SELECT COUNT(*) FROM t WHERE  LIMIT 1")
        #expect(resolution.cursorOffset == 29)
    }

    @Test("Favorite without a marker keeps the caret at the end")
    func favoriteWithoutMarker() {
        let item = SQLCompletionItem.favorite(keyword: "usr", name: "Users", query: "SELECT * FROM users")
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "SELECT * FROM users")
        #expect(resolution.cursorOffset == ("SELECT * FROM users" as NSString).length)
    }

    /// A function's skeleton is what accept inserts, parameters and all, and every `;;` in it is a
    /// stop the editor can walk: the placeholder it names is selected so typing replaces it.
    @Test("Function completion writes the whole signature and stops on every parameter")
    func functionSignatureWritesEveryParameter() {
        let item = SQLCompletionItem.function("COUNT", signature: "COUNT(;;expr)")
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "COUNT(expr)")
        #expect(resolution.cursorOffset == 6)
        #expect(resolution.stops == [SQLCompletionInsertion.Stop(offset: 6, length: 4)])
    }

    @Test("A window function's skeleton walks its OVER clause too")
    func windowSkeletonWalksItsClauses() {
        let item = SQLCompletionItem.function(
            "ROW_NUMBER",
            signature: "ROW_NUMBER() OVER (PARTITION BY ;; ORDER BY ;; )"
        )
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "ROW_NUMBER() OVER (PARTITION BY  ORDER BY  )")
        #expect(resolution.stops == [
            SQLCompletionInsertion.Stop(offset: 32, length: 0),
            SQLCompletionInsertion.Stop(offset: 42, length: 0)
        ])
    }

    /// A signature with no marker keeps the parenthesis rule rather than inserting a skeleton.
    @Test("A markerless function signature parks the caret between the parentheses")
    func markerlessSignatureParkedBetweenParens() {
        let item = SQLCompletionItem.function("PI", signature: "PI()")
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "PI()")
        #expect(resolution.cursorOffset == 3)
        #expect(resolution.stops.isEmpty)
    }

    @Test("Markerless favorite ending in parentheses keeps the paren rule")
    func favoriteEndingInParens() {
        let item = SQLCompletionItem.favorite(keyword: "now", name: "Now", query: "SELECT NOW()")
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "SELECT NOW()")
        #expect(resolution.cursorOffset == ("SELECT NOW()" as NSString).length - 1)
    }

    @Test("Non-favorite item containing the marker keeps it literal")
    func nonFavoriteKeepsLiteralMarker() {
        let item = SQLCompletionItem(label: "BEGIN;;", kind: .keyword)
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "BEGIN;;")
        #expect(resolution.cursorOffset == ("BEGIN;;" as NSString).length)
    }

    @Test("Plain keyword places the caret after the inserted text")
    func plainKeyword() {
        let item = SQLCompletionItem.keyword("SELECT")
        let resolution = SQLCompletionInsertion.resolve(for: item)
        #expect(resolution.text == "SELECT")
        #expect(resolution.cursorOffset == 6)
    }
}
