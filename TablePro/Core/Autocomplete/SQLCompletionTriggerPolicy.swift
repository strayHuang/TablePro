//
//  SQLCompletionTriggerPolicy.swift
//  TablePro
//
//  Which cursor positions open the popup on their own. The query editor and the raw SQL filter
//  field both auto-trigger on every keystroke and both have to answer the same question, so the
//  answer lives here rather than once per surface. The filter field used to decide it from the
//  character before the caret, which cannot see a clause: that shut the PostgreSQL cast list the
//  editor opens and left the two surfaces disagreeing about the same fragment.
//

import Foundation

enum SQLCompletionTriggerPolicy {
    /// A clause with a full column list behind it stays shut until the user types or asks for it.
    /// The clauses listed here answer with a short, closed list instead, so opening one costs the
    /// user nothing. A window clause is that shape too: `OVER (PARTITION BY …)` answers with the
    /// few clauses that belong inside it plus the columns they partition by, and it is the clause
    /// a window-function skeleton leaves its caret in. A qualified name is always a closed list
    /// too, which is why a dot prefix exempts the position whatever clause it sits in.
    ///
    /// An opening identifier quote is typed input even though it matches nothing: the analyzer
    /// keeps it inside `prefixRange` so an accepted completion overwrites it, and strips it from
    /// `prefix` so the matcher can work. Reading `prefix` alone reads that as an untouched
    /// position and shuts the list the user just asked for by typing the quote.
    ///
    /// The start of a statement is on this list too. Nothing has been typed there, so there is no
    /// prefix to judge the position by, and the statement keywords are a short closed answer — the
    /// position a reader is likeliest to want a list at is the one this must not shut.
    static func suppressesEmptyPrefix(_ context: SQLContext, isManualTrigger: Bool) -> Bool {
        guard !isManualTrigger,
              context.prefix.isEmpty,
              context.prefixRange.isEmpty,
              context.dotPrefix == nil else { return false }

        switch context.clauseType {
        case .from, .join, .into, .set, .insertColumns, .on,
             .alterTableColumn, .returning, .using, .dropObject, .createIndex, .castTarget,
             .window, .ddlObject, .unknown:
            return false
        case .select where !context.isAfterComma:
            return false
        default:
            return true
        }
    }
}
