//
//  JoinConditionProvider.swift
//  TablePro
//
//  Generates "whole-condition" completions for a JOIN `ON` (and its `AND`/`OR`
//  continuations): `t1.col = t2.col`, inferred from foreign keys and column
//  name/type metadata. Pure logic, so it can be unit tested without a database.
//

import Foundation

/// Infers the conditions that relate the tables in scope, ranked by how likely
/// each one is the join the user means.
enum JoinConditionProvider {
    /// One table in scope, carrying the metadata the schema provider has already read.
    struct Table {
        /// The identifier written before the dot: an alias when one exists, else the table name.
        let identifier: String
        /// The real table name, which foreign keys are matched against.
        let tableName: String
        let columns: [Column]
        let foreignKeys: [ForeignKey]
    }

    struct Column {
        let name: String
        let typeName: String?
        let isPrimaryKey: Bool
    }

    struct ForeignKey {
        let column: String
        let referencedTable: String
        let referencedColumn: String
    }

    /// How many condition items are offered in total.
    static let maxConditions = 12

    /// Sort priority per tier (lower ranks higher). All sit below the single-column
    /// candidates' priorities, so the inferred conditions lead the list.
    private static let tierPriorities = [5, 12, 19, 26]

    private enum Tier {
        static let foreignKey = 0
        static let sameNamePrimaryKey = 1
        static let sameName = 2
        static let numeric = 3
    }

    /// Column type names that count as `int`/`bigint` for the numeric fallback.
    private static let intTypeNames: Set<String> = ["int", "integer", "int4", "bigint", "int8"]

    /// The candidate conditions relating `tables`, ranked by tier and cut to `limit`.
    ///
    /// Each pair is written once, in table order (`FROM` table first, joined table second), so
    /// the list carries no mirrored duplicate of the same condition. `excluding` carries the
    /// pairs already written so a continuation does not repeat them.
    static func items(
        for tables: [Table],
        excluding used: Set<String> = [],
        limit: Int = maxConditions
    ) -> [SQLCompletionItem] {
        guard tables.count > 1, limit > 0 else { return [] }

        var best: [String: Candidate] = [:]
        for left in tables.indices {
            for right in tables.indices where right > left {
                offerPairs(between: tables[left], and: tables[right], into: &best, excluding: used)
            }
        }

        // Highest tier first, then alphabetically so two runs emit the same order.
        let ranked = best.values.sorted {
            $0.tier == $1.tier ? canonicalKey($0.left, $0.right) < canonicalKey($1.left, $1.right)
                : $0.tier < $1.tier
        }

        var items: [SQLCompletionItem] = []
        for candidate in ranked {
            guard items.count < limit else { break }
            let label = "\(candidate.left) = \(candidate.right)"
            items.append(conditionItem(label: label, tier: candidate.tier))
        }
        return items
    }

    // MARK: - Pair Generation

    private struct Candidate {
        let left: String
        let right: String
        let tier: Int
        let relation: String
    }

    private static func offerPairs(
        between left: Table,
        and right: Table,
        into best: inout [String: Candidate],
        excluding used: Set<String>
    ) {
        offerForeignKeys(from: left, to: right, into: &best, excluding: used)
        offerForeignKeys(from: right, to: left, into: &best, excluding: used)
        offerSameNames(between: left, and: right, into: &best, excluding: used)
        offerNumeric(between: left, and: right, into: &best, excluding: used)
    }

    /// tier0: `left.c1` is a foreign key referencing a column of `right`.
    private static func offerForeignKeys(
        from left: Table,
        to right: Table,
        into best: inout [String: Candidate],
        excluding used: Set<String>
    ) {
        let rightColumns = right.columns.map { $0.name.lowercased() }
        for key in left.foreignKeys {
            guard key.referencedTable.caseInsensitiveCompare(right.tableName) == .orderedSame,
                  rightColumns.contains(key.referencedColumn.lowercased()) else { continue }
            offer(
                Candidate(
                    left: "\(left.identifier).\(key.column)",
                    right: "\(right.identifier).\(key.referencedColumn)",
                    tier: Tier.foreignKey,
                    relation: "Foreign key"
                ),
                into: &best,
                excluding: used
            )
        }
    }

    /// tier1/tier2: a column of the same name on both sides, one of them a primary key.
    private static func offerSameNames(
        between left: Table,
        and right: Table,
        into best: inout [String: Candidate],
        excluding used: Set<String>
    ) {
        let rightByName = Dictionary(
            right.columns.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for leftColumn in left.columns {
            guard let rightColumn = rightByName[leftColumn.name.lowercased()] else { continue }
            let hasPrimaryKey = leftColumn.isPrimaryKey || rightColumn.isPrimaryKey
            offer(
                Candidate(
                    left: "\(left.identifier).\(leftColumn.name)",
                    right: "\(right.identifier).\(rightColumn.name)",
                    tier: hasPrimaryKey ? Tier.sameNamePrimaryKey : Tier.sameName,
                    relation: hasPrimaryKey ? "Same name · PK" : "Same name"
                ),
                into: &best,
                excluding: used
            )
        }
    }

    /// tier3: both columns are `int`/`bigint` and their names are similar. The name check
    /// is what keeps unrelated integer columns (a flag beside a year) out of the list.
    private static func offerNumeric(
        between left: Table,
        and right: Table,
        into best: inout [String: Candidate],
        excluding used: Set<String>
    ) {
        let leftNumeric = left.columns.filter { isInteger($0.typeName) }
        let rightNumeric = right.columns.filter { isInteger($0.typeName) }
        for leftColumn in leftNumeric {
            for rightColumn in rightNumeric {
                guard namesAreSimilar(leftColumn.name, rightColumn.name) else { continue }
                offer(
                    Candidate(
                        left: "\(left.identifier).\(leftColumn.name)",
                        right: "\(right.identifier).\(rightColumn.name)",
                        tier: Tier.numeric,
                        relation: "Numeric"
                    ),
                    into: &best,
                    excluding: used
                )
            }
        }
    }

    /// Keeps the lowest-tier candidate per unordered column pair, and skips pairs already written.
    private static func offer(
        _ candidate: Candidate,
        into best: inout [String: Candidate],
        excluding used: Set<String>
    ) {
        let key = canonicalKey(candidate.left, candidate.right)
        guard !used.contains(key) else { return }
        if let existing = best[key], existing.tier <= candidate.tier { return }
        best[key] = candidate
    }

    // MARK: - Condition Items

    private static func conditionItem(label: String, tier: Int) -> SQLCompletionItem {
        let tierBase = tier < tierPriorities.count
            ? tierPriorities[tier]
            : (tierPriorities.last ?? Tier.numeric * 10)
        return SQLCompletionItem(
            label: label,
            kind: .column,
            insertText: label,
            detail: relationLabel(for: tier),
            // The ranker adds the label's length back as a tie-breaker ("shorter names slightly
            // preferred"), which is longer than the gap between tiers here. Subtracting it cancels
            // that term, so the tier decides the order and a same-name primary key (tier 1) can no
            // longer be overtaken by a longer column name of a lower tier (tier 2).
            sortPriority: tierBase - (label as NSString).length,
            // A whole condition is a long phrase, so a three-letter word is a subsequence of most
            // of them: typing `and` used to collapse the list to whichever condition happened to
            // spell a-n-d. Matching anchor and substring only keeps the prefix behaviour honest.
            allowsFuzzyMatch: false
        )
    }

    private static func relationLabel(for tier: Int) -> String {
        switch tier {
        case Tier.foreignKey: return "Foreign key"
        case Tier.sameNamePrimaryKey: return "Same name · PK"
        case Tier.sameName: return "Same name"
        default: return "Numeric"
        }
    }

    // MARK: - Used Conditions

    /// The `a.x = b.y` pairs already written in `text`, as canonical keys, so a
    /// continuation after `AND`/`OR` does not offer a condition that is already there.
    static func usedConditionKeys(in text: String) -> Set<String> {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var keys: Set<String> = []
        for match in qualifiedEqualityRegex.matches(in: text, range: range) {
            guard match.numberOfRanges >= 5 else { continue }
            let leftAlias = ns.substring(with: match.range(at: 1))
            let leftColumn = ns.substring(with: match.range(at: 2))
            let rightAlias = ns.substring(with: match.range(at: 3))
            let rightColumn = ns.substring(with: match.range(at: 4))
            keys.insert(canonicalKey("\(leftAlias).\(leftColumn)", "\(rightAlias).\(rightColumn)"))
        }
        return keys
    }

    private static let qualifiedEqualityRegex: NSRegularExpression = (try? NSRegularExpression(
        pattern: #"([A-Za-z_][\w$]*)\.([A-Za-z_][\w$]*)\s*=\s*([A-Za-z_][\w$]*)\.([A-Za-z_][\w$]*)"#
    )) ?? NSRegularExpression()

    /// A stable identity for an unordered column pair, so `a.x = b.y` and `b.y = a.x`
    /// are the same condition.
    private static func canonicalKey(_ left: String, _ right: String) -> String {
        let lhs = left.lowercased()
        let rhs = right.lowercased()
        return lhs <= rhs ? "\(lhs)=\(rhs)" : "\(rhs)=\(lhs)"
    }

    // MARK: - Type & Name Helpers

    /// Whether a column's type is `int`/`bigint` (including the PostgreSQL aliases).
    /// A size or modifier (`int(11)`, `bigint unsigned`) is stripped before the check.
    static func isInteger(_ typeName: String?) -> Bool {
        guard let typeName else { return false }
        var normalized = typeName.lowercased()
        if let cut = normalized.firstIndex(where: { $0 == "(" || $0 == " " }) {
            normalized = String(normalized[normalized.startIndex..<cut])
        }
        return intTypeNames.contains(normalized)
    }

    /// Whether two column names are alike enough for the numeric fallback: equal after
    /// dropping a trailing `_id`/`id`, or one containing the other.
    static func namesAreSimilar(_ first: String, _ second: String) -> Bool {
        let lhs = strippedIdentifier(first)
        let rhs = strippedIdentifier(second)
        if lhs == rhs { return true }
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs.contains(rhs) || rhs.contains(lhs)
    }

    private static func strippedIdentifier(_ name: String) -> String {
        var value = name.lowercased()
        for suffix in ["_id", "id"] where value.hasSuffix(suffix) && value.count > suffix.count {
            value = String(value.dropLast(suffix.count))
            break
        }
        return value
    }
}
