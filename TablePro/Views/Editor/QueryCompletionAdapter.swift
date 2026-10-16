//
//  QueryCompletionAdapter.swift
//  TablePro
//
//  Bridges a per-language QueryCompletionService to TableProEditorKit's
//  CodeSuggestionDelegate.
//

import AppKit
import SwiftUI
import TableProEditorKit
import TableProPluginKit
import TableProTextEngine

@MainActor
final class QueryCompletionAdapter: CodeSuggestionDelegate {
    private struct Session {
        var candidates: [SQLCompletionItem]
        var replacementRange: NSRange
        var tokenStart: Int
    }

    private struct Configuration: Equatable {
        let schemaProvider: ObjectIdentifier?
        let databaseType: DatabaseType?
        let profileRevision: String?
    }

    /// The Tab-walkable stops of the snippet the user just accepted, in UTF-16 offsets from where
    /// it was inserted, so Tab and Shift-Tab can visit every parameter before the caret leaves it.
    /// `index` is the stop the caret currently sits on.
    private struct SnippetSession {
        let baseLocation: Int
        let stops: [SQLCompletionInsertion.Stop]
        let endLocation: Int
        var index: Int
    }

    private var service: QueryCompletionService
    private var configuration: Configuration?
    private var favoriteKeywords: [String: (name: String, query: String)] = [:]
    private var session: Session?
    private var snippetSession: SnippetSession?

    private let debounceNanoseconds: UInt64 = 50_000_000
    private let maximumPrefixLength = 500

    init(schemaProvider: SQLSchemaProvider?, databaseType: DatabaseType? = nil) {
        self.service = QueryCompletionServiceFactory.make(schemaProvider: schemaProvider, databaseType: databaseType)
    }

    /// Rebuilding the service drops the open completion session, so it happens only when the
    /// inputs actually differ. The editor reconfigures on appear, on a connection change and
    /// again when the profile resolves, and a refresh in any window of the connection bumps the
    /// profile revision the editor's `.task(id:)` keys on: rebuilding unconditionally closed the
    /// popup under whoever was typing.
    func configure(
        schemaProvider: SQLSchemaProvider?,
        databaseType: DatabaseType?,
        profile: QueryCompletionProfile? = nil
    ) {
        let requested = Configuration(
            schemaProvider: schemaProvider.map(ObjectIdentifier.init),
            databaseType: databaseType,
            profileRevision: profile?.revision
        )
        guard requested != configuration else { return }
        configuration = requested
        service = QueryCompletionServiceFactory.make(
            schemaProvider: schemaProvider,
            databaseType: databaseType,
            profile: profile
        )
        service.updateFavoriteKeywords(favoriteKeywords)
        session = nil
        snippetSession = nil
    }

    #if DEBUG
    /// Identifies the built service so a test can tell a rebuild from a no-op without reaching
    /// for the private session state a rebuild discards.
    var serviceIdentityForTesting: ObjectIdentifier { ObjectIdentifier(service) }

    init(serviceForTesting service: QueryCompletionService) {
        self.service = service
    }
    #endif

    func updateFavoriteKeywords(_ keywords: [String: (name: String, query: String)]) {
        favoriteKeywords = keywords
        service.updateFavoriteKeywords(keywords)
    }

    // MARK: - CodeSuggestionDelegate

    func completionTriggerCharacters() -> Set<String> {
        service.triggerCharacters
    }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        isManualTrigger: Bool
    ) async -> CodeSuggestionResponse? {
        guard !textView.textView.hasMarkedText() else { return nil }

        do {
            try await Task.sleep(nanoseconds: debounceNanoseconds)
        } catch {
            return nil
        }

        guard !textView.textView.hasMarkedText() else { return nil }

        let liveCursorPosition = textView.cursorPositions.first ?? cursorPosition
        let text = (textView.textView.textStorage?.string ?? "") as NSString
        let offset = liveCursorPosition.range.location
        guard offset >= 0, offset <= text.length else { return nil }

        let tokenStart = service.tokenStart(in: text, endingAt: offset)
        let prefixRange = NSRange(location: tokenStart, length: offset - tokenStart)
        let prefix = CodeSuggestionPrefix(range: prefixRange, text: text.substring(with: prefixRange))

        guard let result = await service.completions(
            in: text,
            at: offset,
            isManualTrigger: isManualTrigger
        ), !Task.isCancelled else {
            return nil
        }

        session = Session(
            candidates: result.candidates,
            replacementRange: result.replacementRange,
            tokenStart: tokenStart
        )

        return CodeSuggestionResponse(
            items: result.items.map { SQLSuggestionEntry(item: $0) },
            windowPosition: liveCursorPosition,
            prefix: prefix
        )
    }

    /// Filters and ranks the open session's candidates for the token the cursor sits at the end of.
    ///
    /// Ranking happens here, on the keystroke, rather than on a debounced task writing to a cache:
    /// the list handed back is the list the suggestion window shows and preselects its first row
    /// from, so a list ordered for an earlier prefix commits the wrong item on Return. It costs no
    /// debounce, because filtering already matches every candidate in the session and ordering the
    /// survivors is the cheaper half.
    ///
    /// The survivors come from the session's own candidates rather than the previous keystroke's,
    /// so deleting a character widens the list back out.
    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        guard let session, !textView.textView.hasMarkedText() else { return nil }

        let offset = cursorPosition.range.location
        guard let text = textView.textView.textStorage?.string as NSString?,
              offset >= 0, offset <= text.length else { return nil }

        let start = service.tokenStart(in: text, endingAt: offset)
        guard start == session.tokenStart else { return nil }
        let length = offset - start
        guard length > 0, length <= maximumPrefixLength else { return nil }

        let prefix = text.substring(with: NSRange(location: start, length: length))
        guard !prefix.isEmpty else { return nil }

        let ranked = service.rank(session.candidates, prefix: prefix)
        return ranked.isEmpty ? nil : ranked.map { SQLSuggestionEntry(item: $0) }
    }

    func completionWindowDidClose() {
        session = nil
    }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard !textView.textView.hasMarkedText(),
              let entry = item as? SQLSuggestionEntry,
              let session else { return }

        let text = textView.textView.textStorage?.string as NSString?
        let replaceRange = resolvedReplacementRange(
            in: text,
            cursor: cursorPosition?.range.location,
            fallback: session.replacementRange
        )
        let resolution = SQLCompletionInsertion.resolve(for: entry.item)

        textView.textView.replaceCharacters(in: [replaceRange], with: resolution.text)

        let base = replaceRange.location
        guard !resolution.stops.isEmpty else {
            snippetSession = nil
            textView.setCursorPositions([
                CursorPosition(range: NSRange(location: base + resolution.cursorOffset, length: 0))
            ])
            return
        }

        snippetSession = SnippetSession(
            baseLocation: base,
            stops: resolution.stops,
            endLocation: base + (resolution.text as NSString).length,
            index: 0
        )
        selectSnippetStop(0, in: textView)

        // The stop the caret just landed on is a parameter, so the list that belongs there is the
        // one its clause answers with — `OVER (PARTITION BY ` offers PARTITION BY, ORDER BY and the
        // columns they take. Asking on the next turn of the run loop is what makes it survive: the
        // window that accepted the item closes synchronously behind this call, and that close
        // cancels a request started inline. A position whose list the trigger policy keeps shut
        // simply stays shut.
        Task { @MainActor in
            textView.requestCompletions()
        }
    }

    // MARK: - Snippet Tab Stops

    /// Walks the accepted snippet's stops. The session is dropped the moment the caret is no longer
    /// inside the inserted text, so a Tab after the user has moved on indents as it always did
    /// instead of jumping back into a skeleton they left.
    func completionSnippetAdvance(textView: TextViewController, forward: Bool) -> Bool {
        guard let session = snippetSession else { return false }
        guard let current = textView.textView.selectionManager.textSelections.first?.range,
              current.location >= session.baseLocation,
              current.location + current.length <= session.endLocation else {
            snippetSession = nil
            return false
        }

        let target = forward ? session.index + 1 : max(session.index - 1, 0)
        guard target < session.stops.count else {
            snippetSession = nil
            textView.setCursorPositions([
                CursorPosition(range: NSRange(location: session.endLocation, length: 0))
            ])
            return true
        }

        snippetSession?.index = target
        selectSnippetStop(target, in: textView)
        return true
    }

    private func selectSnippetStop(_ index: Int, in textView: TextViewController) {
        guard let snippetSession, snippetSession.stops.indices.contains(index) else { return }
        let stop = snippetSession.stops[index]
        textView.setCursorPositions([
            CursorPosition(
                range: NSRange(location: snippetSession.baseLocation + stop.offset, length: stop.length)
            )
        ])
    }

    private func resolvedReplacementRange(in text: NSString?, cursor: Int?, fallback: NSRange) -> NSRange {
        guard let text, let cursor, cursor >= 0, cursor <= text.length else { return fallback }
        let start = service.tokenStart(in: text, endingAt: cursor)
        return NSRange(location: start, length: cursor - start)
    }
}

// MARK: - SQLSuggestionEntry

final class SQLSuggestionEntry: CodeSuggestionEntry {
    let item: SQLCompletionItem

    init(item: SQLCompletionItem) {
        self.item = item
    }

    var label: String { item.label }
    var detail: String? { item.detail }
    /// Tables and columns carry their comment inline instead, so the preview pane is not shown
    /// for them; every other kind keeps its documentation.
    var documentation: String? {
        switch item.kind {
        case .table, .view, .column: return nil
        default: return item.documentation
        }
    }
    var inlineNote: String? { item.inlineNote }
    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }
    var deprecated: Bool { MongoVocabulary.deprecatedCollectionMethods.contains(item.label) }
    var matchedRanges: [Range<Int>] { item.matchedRanges }

    var image: Image {
        Image(systemName: item.kind.iconName)
    }

    var imageColor: Color {
        Color(nsColor: item.kind.iconColor)
    }
}
