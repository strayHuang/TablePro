//
//  CodeSuggestionDelegate.swift
//  TableProEditorKit
//
//  Created by Abe Malla on 12/26/24.
//

@MainActor
public protocol CodeSuggestionDelegate: AnyObject {
    func completionTriggerCharacters() -> Set<String>

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        isManualTrigger: Bool
    ) async -> CodeSuggestionResponse?

    // This can't be async, we need it to be snappy. At most, it should just be filtering completion items
    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]?

    // Optional
    func completionWindowDidClose()

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    )
    // Optional
    func completionWindowDidSelect(item: CodeSuggestionEntry)

    /// Asks the delegate to claim Tab or Shift-Tab as a walk between the stops of the snippet it
    /// last inserted. Returning `true` consumes the key; `false` leaves the editor's own Tab —
    /// indent or outdent — in place, which is also what a caret that has left the snippet gets.
    func completionSnippetAdvance(textView: TextViewController, forward: Bool) -> Bool
}

public extension CodeSuggestionDelegate {
    func completionTriggerCharacters() -> Set<String> { [] }
    func completionWindowDidClose() { }
    func completionWindowDidSelect(item: CodeSuggestionEntry) { }
    func completionSnippetAdvance(textView: TextViewController, forward: Bool) -> Bool { false }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        isManualTrigger: Bool
    ) async -> CodeSuggestionResponse? {
        await completionSuggestionsRequested(textView: textView, cursorPosition: cursorPosition)
    }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> CodeSuggestionResponse? {
        nil
    }
}
