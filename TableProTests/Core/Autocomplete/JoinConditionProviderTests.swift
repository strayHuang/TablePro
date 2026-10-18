//
//  JoinConditionProviderTests.swift
//  TableProTests
//
//  Tests for JOIN `ON` condition inference
//

import Foundation
@testable import TablePro
import Testing

struct JoinConditionProviderTests {
    // MARK: - Helpers

    private func column(_ name: String, type: String? = nil, pk: Bool = false) -> JoinConditionProvider.Column {
        JoinConditionProvider.Column(name: name, typeName: type, isPrimaryKey: pk)
    }

    private func table(
        _ identifier: String,
        _ tableName: String,
        columns: [JoinConditionProvider.Column] = [],
        foreignKeys: [JoinConditionProvider.ForeignKey] = []
    ) -> JoinConditionProvider.Table {
        JoinConditionProvider.Table(
            identifier: identifier, tableName: tableName, columns: columns, foreignKeys: foreignKeys
        )
    }

    // MARK: - Tier order

    @Test("Foreign key leads, then same-name primary key")
    func foreignKeyLeadsThenSameNamePrimaryKey() {
        let users = table("u", "users", columns: [column("id", type: "int", pk: true)])
        let orders = table(
            "o", "orders",
            columns: [column("user_id", type: "int"), column("id", type: "int", pk: true)],
            foreignKeys: [JoinConditionProvider.ForeignKey(
                column: "user_id", referencedTable: "users", referencedColumn: "id"
            )]
        )

        let items = JoinConditionProvider.items(for: [users, orders])

        // The foreign key leads, then the same-name pair that carries a primary key. Each condition
        // is written once: the mirrored `b = a` ordering is no longer emitted.
        #expect(items.first?.label == "o.user_id = u.id")
        #expect(items.first?.detail == "Foreign key")
        #expect(items.dropFirst().first?.label == "u.id = o.id")
        #expect(items.dropFirst().first?.detail == "Same name · PK")
        #expect(items.count == 2)
    }

    @Test("A condition is offered once, not mirrored")
    func conditionOfferedOnce() {
        let a = table("a", "alpha", columns: [column("code", type: "int", pk: true)])
        let b = table("b", "beta", columns: [column("code", type: "int")])

        let labels = JoinConditionProvider.items(for: [a, b]).map(\.label)
        #expect(labels == ["a.code = b.code"])
    }

    @Test("Tier decides the order regardless of label length")
    func tierOutranksLabelLength() {
        // `code` is the tier-1 pair (a primary key on one side); `a_rather_long_same_name` is the
        // tier-2 pair on both sides. The tier-2 label is the longer one, so with the length term
        // left in the ranking the shorter tier-1 label would still win only by accident — the point
        // is that the tier wins even when its label does not.
        let columns = [column("code", type: "int", pk: true), column("a_rather_long_same_name", type: "int")]
        let a = table("a", "alpha", columns: columns)
        let b = table("b", "beta", columns: columns)

        let items = JoinConditionProvider.items(for: [a, b])
        let pkIndex = items.firstIndex { $0.label == "a.code = b.code" }
        let sameIndex = items.firstIndex { $0.label == "a.a_rather_long_same_name = b.a_rather_long_same_name" }
        #expect(pkIndex != nil && sameIndex != nil)
        #expect((pkIndex ?? 0) < (sameIndex ?? 0))
    }

    @Test("Whole conditions do not fuzzy-match")
    func wholeConditionsDoNotFuzzyMatch() {
        let a = table("a", "alpha", columns: [column("enterdate", type: "int", pk: true)])
        let b = table("b", "beta", columns: [column("enterdate", type: "int", pk: true)])

        // `and` is a subsequence of `a.enterdate = b.enterdate`; a whole condition must not opt into
        // that, or a typed keyword collapses the list to unrelated conditions.
        let item = JoinConditionProvider.items(for: [a, b]).first
        #expect(item?.allowsFuzzyMatch == false)
    }

    // MARK: - AND continuation

    @Test("A condition inserts AND in front of itself when continued")
    func conditionInsertsAndWhenContinued() {
        let a = table("a", "alpha", columns: [column("code", type: "int", pk: true)])
        let b = table("b", "beta", columns: [column("code", type: "int")])

        let item = JoinConditionProvider.items(for: [a, b], continuedWithAnd: true).first
        #expect(item?.label == "a.code = b.code")
        #expect(item?.insertText == "AND a.code = b.code")
    }

    @Test("A continued condition matches the typed AND through its filter text")
    func continuedConditionMatchesTypedAnd() {
        let a = table("a", "alpha", columns: [column("code", type: "int", pk: true)])
        let b = table("b", "beta", columns: [column("code", type: "int")])

        // `and` is not a prefix of the bare label, so without the `and ` filter text the whole
        // conditions would vanish the moment the keyword was typed.
        let item = JoinConditionProvider.items(for: [a, b], continuedWithAnd: true).first
        #expect(item?.filterText == "and a.code = b.code")
        #expect(item?.allowsFuzzyMatch == false)
    }

    @Test("A condition written as the first one inserts itself unchanged")
    func firstConditionInsertsUnchanged() {
        let a = table("a", "alpha", columns: [column("code", type: "int", pk: true)])
        let b = table("b", "beta", columns: [column("code", type: "int")])

        let item = JoinConditionProvider.items(for: [a, b]).first
        #expect(item?.insertText == "a.code = b.code")
        #expect(item?.filterText == "a.code = b.code")
    }

    // MARK: - Numeric fallback (Q5: similar names only)

    @Test("Numeric fallback fires only when the names are similar")
    func numericSimilarOnly() {
        let a = table("a", "alpha", columns: [column("customerid", type: "bigint")])
        let b = table("b", "beta", columns: [column("customer_id", type: "int")])

        let items = JoinConditionProvider.items(for: [a, b])
        #expect(items.contains { $0.label == "a.customerid = b.customer_id" })
        #expect(items.allSatisfy { $0.detail == "Numeric" })
    }

    @Test("Unrelated integer columns produce no numeric condition")
    func numericUnrelatedIgnored() {
        let a = table("a", "alpha", columns: [column("flag", type: "int")])
        let b = table("b", "beta", columns: [column("year", type: "int")])
        #expect(JoinConditionProvider.items(for: [a, b]).isEmpty)
    }

    @Test("Numeric fallback only accepts int/bigint, not other numeric types")
    func numericTypeRestricted() {
        let a = table("a", "alpha", columns: [column("amount", type: "numeric")])
        let b = table("b", "beta", columns: [column("amounts", type: "real")])
        #expect(JoinConditionProvider.items(for: [a, b]).isEmpty)
    }

    @Test("isInteger recognizes the int/bigint spellings only")
    func isIntegerSpellings() {
        #expect(JoinConditionProvider.isInteger("INT"))
        #expect(JoinConditionProvider.isInteger("bigint"))
        #expect(JoinConditionProvider.isInteger("int(11)"))
        #expect(JoinConditionProvider.isInteger("bigint unsigned"))
        #expect(!JoinConditionProvider.isInteger("smallint"))
        #expect(!JoinConditionProvider.isInteger("numeric(10,2)"))
        #expect(!JoinConditionProvider.isInteger(nil))
    }

    // MARK: - Bounds & dedupe

    @Test("A single table yields no conditions")
    func singleTableYieldsNothing() {
        let a = table("a", "alpha", columns: [column("id", type: "int", pk: true)])
        #expect(JoinConditionProvider.items(for: [a]).isEmpty)
    }

    @Test("limit caps the number of items")
    func limitCapsItems() {
        let a = table("a", "alpha", columns: (0..<10).map { column("c\($0)", type: "int", pk: true) })
        let b = table("b", "beta", columns: (0..<10).map { column("c\($0)", type: "int") })
        #expect(JoinConditionProvider.items(for: [a, b], limit: 5).count == 5)
    }

    @Test("A pair already written is not offered again")
    func excludedPairsSkipped() {
        let a = table("a", "alpha", columns: [column("customerid", type: "bigint")])
        let b = table("b", "beta", columns: [column("customer_id", type: "int")])
        let items = JoinConditionProvider.items(for: [a, b], excluding: ["a.customerid=b.customer_id"])
        #expect(items.isEmpty)
    }

    // MARK: - Used-condition extraction

    @Test("usedConditionKeys extracts written qualified equalities")
    func usedConditionKeysExtracted() {
        let keys = JoinConditionProvider.usedConditionKeys(
            in: "SELECT * FROM a JOIN b ON a.id = b.a_id AND b.x = c.y"
        )
        #expect(keys.contains("a.id=b.a_id"))
        #expect(keys.contains("b.x=c.y"))
    }

    @Test("usedConditionKeys is empty for a statement with no qualified equality")
    func usedConditionKeysEmpty() {
        #expect(JoinConditionProvider.usedConditionKeys(in: "SELECT * FROM users").isEmpty)
    }
}
