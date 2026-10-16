//
//  SQLSnippetMarker.swift
//  TablePro
//
//  Cursor-placement marker shared by SQL favorite expansion and function skeletons. Every ";;"
//  in a snippet marks one stop: the first is where the caret lands, the rest are where Tab and
//  Shift-Tab walk to. The markers are stripped from the inserted text, and the token that follows
//  a marker — the parameter name in a function skeleton — travels with it as the placeholder to
//  select, so typing replaces it instead of pushing it aside. Offsets are UTF-16 units so the
//  caret resolves correctly after multibyte text.
//

import Foundation

enum SQLSnippetMarker {
    static let token = ";;"

    struct Expansion {
        let text: String
        /// UTF-16 offsets in `text`, one per marker, in the order they appeared.
        let cursorOffsets: [Int]
        /// The length of the placeholder token following each offset; zero when the marker was
        /// followed by whitespace or punctuation.
        let placeholderLengths: [Int]

        /// Where the caret lands when the snippet is accepted: the first stop, or the end of the
        /// text for a marker that only closes a stop-free skeleton.
        var cursorOffset: Int { cursorOffsets.first ?? (text as NSString).length }
    }

    /// The snippet with its markers removed — the text as the preview pane shows it.
    static func stripped(_ raw: String) -> String {
        guard raw.contains(token) else { return raw }
        return raw.replacingOccurrences(of: token, with: "")
    }

    /// `nil` when the raw text carries no marker: such a snippet has no stops and the caller falls
    /// back to its own caret rule.
    static func expand(_ raw: String) -> Expansion? {
        let ns = NSMutableString(string: raw)
        var offsets: [Int] = []
        var searchStart = 0
        while searchStart <= ns.length {
            let range = ns.range(
                of: token, options: [], range: NSRange(location: searchStart, length: ns.length - searchStart)
            )
            guard range.location != NSNotFound else { break }
            offsets.append(range.location)
            ns.deleteCharacters(in: range)
            searchStart = range.location
        }
        guard !offsets.isEmpty else { return nil }

        let text = ns as String
        return Expansion(
            text: text,
            cursorOffsets: offsets,
            placeholderLengths: offsets.map { placeholderLength(in: text, at: $0) }
        )
    }

    /// The identifier the marker hands to the user: the run of word characters starting at the
    /// stop. A parameter name is always spelled that way (`expr`, `start`, `len`, `new_value`),
    /// and a marker dropped before a space or a bracket yields an empty slot to type into.
    private static func placeholderLength(in text: String, at offset: Int) -> Int {
        let ns = text as NSString
        var index = offset
        while index < ns.length, isPlaceholderCharacter(ns.character(at: index)) {
            index += 1
        }
        return index - offset
    }

    private static func isPlaceholderCharacter(_ character: unichar) -> Bool {
        switch character {
        case 48...57, 65...90, 97...122, 95: return true
        default: return false
        }
    }
}
