//
//  SQLCompletionInsertion.swift
//  TablePro
//
//  Accept-time resolution of what text a completion inserts and where the caret lands, in UTF-16
//  units relative to the insertion start. Favorites and function skeletons honor the
//  SQLSnippetMarker cursor tokens and report every stop they carry, so the editor can walk them
//  with Tab; a function skeleton without markers parks the caret between its parentheses; and
//  everything else places the caret after the inserted text.
//

import Foundation

enum SQLCompletionInsertion {
    /// One Tab stop inside the inserted text: where it starts and how much of the placeholder the
    /// user should have selected there.
    struct Stop: Equatable {
        let offset: Int
        let length: Int
    }

    struct Resolution: Equatable {
        let text: String
        let cursorOffset: Int
        /// Every stop the snippet declared, in order. Empty for a completion that has none.
        let stops: [Stop]
    }

    static func resolve(for item: SQLCompletionItem) -> Resolution {
        if carriesSnippet(item), let expansion = SQLSnippetMarker.expand(item.insertText) {
            let stops = zip(expansion.cursorOffsets, expansion.placeholderLengths)
                .map { Stop(offset: $0.0, length: $0.1) }
            return Resolution(
                text: expansion.text,
                cursorOffset: expansion.cursorOffset,
                stops: stops
            )
        }

        let length = (item.insertText as NSString).length
        let cursorOffset = item.insertText.hasSuffix("()") ? length - 1 : length
        return Resolution(text: item.insertText, cursorOffset: cursorOffset, stops: [])
    }

    /// Kinds whose text is a snippet rather than a literal: a saved favorite may hold the marker
    /// by construction, and a function skeleton carries one wherever it has parameters.
    private static func carriesSnippet(_ item: SQLCompletionItem) -> Bool {
        item.kind == .favorite || item.kind == .function
    }
}
